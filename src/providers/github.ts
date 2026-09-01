// GitHub provider client, built on @octokit/rest. Talks to api.github.com;
// config.baseUrl is unused.

import type { Octokit } from "@octokit/rest";
import type { AccountConfig, ItemState } from "../shared/types";
import type { FetchedItem, FetchResult, ProviderClient } from "./types";
import {
  TIMEOUT_MS,
  statusMessage,
  timeoutMessage,
  unreachableMessage,
  type RequestContext,
} from "./errors";

const MAX_PAGES = 2;
const PER_PAGE = 50;

// The notifications payload carries no issue/PR state, so it is fetched per
// item from subject.url. STATE_BUDGET caps the uncached lookups per sync
// (items over budget just omit state this round and catch up on later syncs
// as the cache fills); STATE_CONCURRENCY bounds how many run at once.
const STATE_BUDGET = 20;
const STATE_CONCURRENCY = 5;

const MENTION_REASONS = new Set(["mention", "team_mention", "review_requested"]);

const CONTEXT: RequestContext = {
  service: "GitHub",
  origin: "https://api.github.com",
  originIsUserSupplied: false,
};

// Loaded lazily at the point of use so the library is never evaluated during
// startup — createProviders() runs in the main process boot path.
let octokitModule: Promise<typeof import("@octokit/rest")> | undefined;

function loadOctokit(): Promise<typeof import("@octokit/rest")> {
  octokitModule ??= import("@octokit/rest");
  return octokitModule;
}

async function createClient(config: AccountConfig): Promise<Octokit> {
  const { Octokit } = await loadOctokit();
  return new Octokit({
    auth: config.token,
    // Octokit's request-log plugin writes every failed request to the
    // console; failures are expected here (bad tokens, offline) and are
    // already surfaced in the UI, so keep the main process quiet.
    log: { debug: () => {}, info: () => {}, warn: () => {}, error: () => {} },
  });
}

/** Per-request options: a fresh 15-second cap for every request. */
function requestOptions(): { signal: AbortSignal } {
  return { signal: AbortSignal.timeout(TIMEOUT_MS) };
}

// Minimal shapes: only the fields we read. Octokit's generated response types
// mark some of these non-nullable even though the API returns null (e.g.
// subject.url on Discussion threads), so we keep our own honest shape and
// narrow each entry to it.
interface GithubUser {
  login: string;
}

interface GithubNotification {
  id: string;
  reason: string;
  unread?: boolean;
  updated_at: string;
  subject: {
    title: string;
    url: string | null;
    latest_comment_url: string | null;
    type: string;
  };
  repository: {
    full_name: string;
    html_url: string;
  };
}

// Octokit throws RequestError (name "HttpError") for HTTP failures, and also
// wraps network-level failures in it (with status forced to 500 and no
// response attached). Detected structurally so the class itself never has to
// be loaded eagerly.
interface OctokitRequestError extends Error {
  status: number;
  response?: unknown;
  cause?: unknown;
}

function isRequestError(error: unknown): error is OctokitRequestError {
  return (
    error instanceof Error &&
    error.name === "HttpError" &&
    typeof (error as { status?: unknown }).status === "number"
  );
}

function isTimeoutError(error: unknown): boolean {
  return (
    error instanceof Error &&
    (error.name === "AbortError" || error.name === "TimeoutError")
  );
}

/** Maps an octokit failure to an Error whose message is fit for the UI. */
function toFriendlyError(error: unknown): Error {
  if (isRequestError(error)) {
    if (error.response !== undefined) {
      // GitHub answered with a non-success status.
      return new Error(statusMessage(error.status, CONTEXT));
    }
    // No response: octokit wrapped a network-level failure (it forces the
    // status to 500, so the status is meaningless here).
    return new Error(
      isTimeoutError(error.cause) ? timeoutMessage(CONTEXT) : unreachableMessage(CONTEXT)
    );
  }
  // Octokit re-throws aborts raw rather than wrapping them.
  if (isTimeoutError(error)) {
    return new Error(timeoutMessage(CONTEXT));
  }
  return new Error(unreachableMessage(CONTEXT));
}

/** True when a Link header advertises a rel="next" page. */
function hasNextLink(linkHeader: string | undefined): boolean {
  if (!linkHeader) return false;
  for (const part of linkHeader.split(",")) {
    if (/<([^>]+)>\s*;\s*rel="next"/.test(part)) return true;
  }
  return false;
}

/** Derives the html URL for a notification without extra API calls. */
function htmlUrl(thread: GithubNotification): string {
  const subjectUrl = thread.subject.url;
  if (!subjectUrl) {
    // Discussions, security alerts, etc. carry no subject URL.
    return thread.repository.html_url;
  }
  let url = subjectUrl
    .replace("https://api.github.com/repos/", "https://github.com/")
    .replace("/pulls/", "/pull/");
  const commentUrl = thread.subject.latest_comment_url;
  const comment = commentUrl ? /\/issues\/comments\/(\d+)$/.exec(commentUrl) : null;
  if (comment) {
    url += `#issuecomment-${comment[1]}`;
  }
  return url;
}

function toFetchedItem(thread: GithubNotification): FetchedItem {
  return {
    id: `github:${thread.id}`,
    provider: "github",
    kind: thread.subject.type === "PullRequest" ? "pull" : "issue",
    title: thread.subject.title,
    repo: thread.repository.full_name,
    url: htmlUrl(thread),
    reason: thread.reason,
    isMention: MENTION_REASONS.has(thread.reason),
    updatedAt: thread.updated_at,
    upstreamRead: thread.unread === false,
  };
}

/** The fields read off a subject.url (issue or pull) response. */
interface GithubSubject {
  state?: string;
  merged?: boolean;
  merged_at?: string | null;
  draft?: boolean;
  user?: { login?: string } | null;
}

/** What one subject lookup teaches us; cached per thread id + updated_at. */
interface Enrichment {
  state?: ItemState;
  author?: string;
}

function applyEnrichment(item: FetchedItem, known: Enrichment): void {
  if (known.state !== undefined) item.state = known.state;
  if (known.author !== undefined) item.author = known.author;
}

/** Maps a subject payload to the item's lifecycle state, if determinable. */
function toItemState(subjectType: string, subject: GithubSubject): ItemState | undefined {
  if (subjectType === "PullRequest") {
    if (subject.merged === true || typeof subject.merged_at === "string") return "merged";
    if (subject.draft === true) return "draft";
  }
  if (subject.state === "open") return "open";
  if (subject.state === "closed") return "closed";
  return undefined;
}

/**
 * Fills in `state` on the fetched items by looking up each thread's
 * subject.url, at most STATE_BUDGET uncached lookups per call (newest first).
 * Results — including "couldn't determine" — are cached per thread id +
 * updated_at, so unchanged items never refetch across the sync loop and
 * failed lookups don't retry every minute. Lookup failures are per-item and
 * silent: the item just ships without a state.
 */
async function enrichStates(
  octokit: Octokit,
  entries: Array<{ item: FetchedItem; thread: GithubNotification }>,
  cache: Map<string, Enrichment>
): Promise<void> {
  // Rebuilt from this round's threads so the cache never outgrows the inbox.
  const nextCache = new Map<string, Enrichment>();
  const pending: Array<{ item: FetchedItem; thread: GithubNotification; key: string }> = [];

  for (const { item, thread } of entries) {
    // Discussions, security alerts, etc. carry no subject URL — no state.
    if (!thread.subject.url) continue;
    const key = `${thread.id}:${thread.updated_at}`;
    const known = cache.get(key);
    if (known !== undefined) {
      nextCache.set(key, known);
      applyEnrichment(item, known);
    } else {
      pending.push({ item, thread, key });
    }
  }

  pending.sort((a, b) => b.thread.updated_at.localeCompare(a.thread.updated_at));
  const batch = pending.slice(0, STATE_BUDGET);

  let cursor = 0;
  async function worker(): Promise<void> {
    while (cursor < batch.length) {
      const job = batch[cursor++];
      let known: Enrichment;
      try {
        // subject.url is absolute, so request() uses it verbatim.
        const response = await octokit.request(`GET ${job.thread.subject.url}`, {
          request: requestOptions(),
        });
        const subject = response.data as GithubSubject;
        known = {
          state: toItemState(job.thread.subject.type, subject),
          author: subject.user?.login ?? undefined,
        };
      } catch {
        known = {};
      }
      nextCache.set(job.key, known);
      applyEnrichment(job.item, known);
    }
  }
  await Promise.all(
    Array.from({ length: Math.min(STATE_CONCURRENCY, batch.length) }, () => worker())
  );

  cache.clear();
  for (const [key, known] of nextCache) cache.set(key, known);
}

export function createGithubClient(): ProviderClient {
  // Lives as long as the client (the app's lifetime); see enrichStates.
  const stateCache = new Map<string, Enrichment>();

  return {
    id: "github",

    async validate(config: AccountConfig): Promise<{ username: string }> {
      const octokit = await createClient(config);
      let data: unknown;
      try {
        ({ data } = await octokit.rest.users.getAuthenticated({
          request: requestOptions(),
        }));
      } catch (error) {
        throw toFriendlyError(error);
      }
      const user = data as GithubUser | undefined;
      if (!user || typeof user.login !== "string") {
        throw new Error("GitHub accepted the token but returned no username — try again later.");
      }
      return { username: user.login };
    },

    async fetchItems(config: AccountConfig): Promise<FetchResult> {
      const octokit = await createClient(config);
      const entries: Array<{ item: FetchedItem; thread: GithubNotification }> = [];
      // Set once the last page is consumed. Hitting MAX_PAGES with pages
      // left — or bailing on a 304/malformed body — leaves the fetch
      // incomplete, so absence proves nothing this round (see sync.ts).
      let complete = false;

      for (let page = 1; page <= MAX_PAGES; page++) {
        let status: number;
        let link: string | undefined;
        let body: unknown;
        try {
          const response = await octokit.rest.activity.listNotificationsForAuthenticatedUser({
            // Read threads too: items handled on the web while the app was
            // closed still arrive (as already-read) instead of never showing.
            all: true,
            per_page: PER_PAGE,
            page,
            request: requestOptions(),
          });
          ({ status } = response);
          link = response.headers.link;
          body = response.data;
        } catch (error) {
          // Octokit surfaces 304 as a thrown error, but it means "nothing
          // new", not a failure.
          if (isRequestError(error) && error.status === 304) break;
          throw toFriendlyError(error);
        }
        if (status === 304 || body === undefined) break;
        if (!Array.isArray(body)) break;

        for (const raw of body) {
          try {
            const thread = raw as GithubNotification;
            entries.push({ item: toFetchedItem(thread), thread });
          } catch {
            // One malformed thread must not kill the whole fetch.
          }
        }
        if (!hasNextLink(link)) {
          complete = true;
          break;
        }
      }

      await enrichStates(octokit, entries, stateCache);
      return { items: entries.map(({ item }) => item), complete };
    },
  };
}
