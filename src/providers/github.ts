// GitHub provider client, built on @octokit/rest. Talks to api.github.com;
// config.baseUrl is unused.

import type { Octokit } from "@octokit/rest";
import type { AccountConfig } from "../shared/types";
import type { FetchedItem, ProviderClient } from "./types";
import {
  TIMEOUT_MS,
  statusMessage,
  timeoutMessage,
  unreachableMessage,
  type RequestContext,
} from "./errors";

const MAX_PAGES = 2;
const PER_PAGE = 50;

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

export function createGithubClient(): ProviderClient {
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

    async fetchItems(config: AccountConfig): Promise<FetchedItem[]> {
      const octokit = await createClient(config);
      const items: FetchedItem[] = [];
      let hasNext = true;

      for (let page = 1; page <= MAX_PAGES && hasNext; page++) {
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
            items.push(toFetchedItem(raw as GithubNotification));
          } catch {
            // One malformed thread must not kill the whole fetch.
          }
        }
        hasNext = hasNextLink(link);
      }

      return items;
    },
  };
}
