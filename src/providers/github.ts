// GitHub provider client. Talks to api.github.com; config.baseUrl is unused.

import type { AccountConfig, FetchedItem, ProviderClient } from "../shared/types";
import { getJson, type RequestContext } from "./http";

const API_ROOT = "https://api.github.com";
const MAX_PAGES = 2;

const MENTION_REASONS = new Set(["mention", "team_mention", "review_requested"]);

const CONTEXT: RequestContext = {
  service: "GitHub",
  origin: API_ROOT,
  originIsUserSupplied: false,
};

// Minimal shapes: only the fields we read.
interface GithubUser {
  login: string;
}

interface GithubNotification {
  id: string;
  reason: string;
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

function headers(config: AccountConfig): Record<string, string> {
  return {
    Authorization: `Bearer ${config.token}`,
    Accept: "application/vnd.github+json",
    "X-GitHub-Api-Version": "2022-11-28",
  };
}

/** Extracts the rel="next" URL from a Link header, if any. */
function nextLink(linkHeader: string | null): string | undefined {
  if (!linkHeader) return undefined;
  for (const part of linkHeader.split(",")) {
    const match = /<([^>]+)>\s*;\s*rel="next"/.exec(part);
    if (match) return match[1];
  }
  return undefined;
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
  };
}

export function createGithubClient(): ProviderClient {
  return {
    id: "github",

    async validate(config: AccountConfig): Promise<{ username: string }> {
      const { body } = await getJson(`${API_ROOT}/user`, headers(config), CONTEXT);
      const user = body as GithubUser | undefined;
      if (!user || typeof user.login !== "string") {
        throw new Error("GitHub accepted the token but returned no username — try again later.");
      }
      return { username: user.login };
    },

    async fetchItems(config: AccountConfig): Promise<FetchedItem[]> {
      const items: FetchedItem[] = [];
      let url: string | undefined = `${API_ROOT}/notifications?per_page=50`;

      for (let page = 0; page < MAX_PAGES && url; page++) {
        const { status, headers: responseHeaders, body } = await getJson(
          url,
          headers(config),
          CONTEXT
        );
        // 304 or an empty body means "nothing new", not an error.
        if (status === 304 || body === undefined) break;
        if (!Array.isArray(body)) break;

        for (const raw of body) {
          try {
            items.push(toFetchedItem(raw as GithubNotification));
          } catch {
            // One malformed thread must not kill the whole fetch.
          }
        }
        url = nextLink(responseHeaders.get("link"));
      }

      return items;
    },
  };
}
