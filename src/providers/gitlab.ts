// GitLab provider client for self-hosted instances. config.baseUrl is the
// instance origin (e.g. "https://gitlab.example.com") and is required.

import type { AccountConfig, FetchedItem, ProviderClient } from "../shared/types";
import { getJson, type RequestContext } from "./http";

const MAX_PAGES = 2;

const MENTION_ACTIONS = new Set(["mentioned", "directly_addressed", "review_requested"]);

// Minimal shapes: only the fields we read.
interface GitlabUser {
  username: string;
}

interface GitlabTodo {
  id: number;
  action_name: string;
  created_at: string;
  target_type: string;
  target_url: string;
  target?: { title?: string } | null;
  project?: { path_with_namespace?: string } | null;
  body?: string | null;
}

/** Normalizes and validates the user-supplied base URL. Throws a UI-ready message. */
function resolveBaseUrl(config: AccountConfig): string {
  const trimmed = (config.baseUrl ?? "").trim().replace(/\/+$/, "");
  if (trimmed === "") {
    throw new Error(
      "GitLab needs the URL of your instance (e.g. https://gitlab.example.com) — add it in the Accounts pane."
    );
  }
  try {
    const parsed = new URL(trimmed);
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
      throw new Error("not http(s)");
    }
  } catch {
    throw new Error(
      `"${trimmed}" does not look like a URL — expected something like https://gitlab.example.com.`
    );
  }
  return trimmed;
}

function context(baseUrl: string): RequestContext {
  return { service: "GitLab", origin: baseUrl, originIsUserSupplied: true };
}

function headers(config: AccountConfig): Record<string, string> {
  return { "PRIVATE-TOKEN": config.token };
}

function toFetchedItem(todo: GitlabTodo): FetchedItem {
  return {
    id: `gitlab:${todo.id}`,
    provider: "gitlab",
    kind: todo.target_type === "MergeRequest" ? "merge" : "issue",
    title: todo.target?.title ?? todo.body ?? "(untitled)",
    repo: todo.project?.path_with_namespace ?? "",
    url: todo.target_url,
    reason: todo.action_name,
    isMention: MENTION_ACTIONS.has(todo.action_name),
    updatedAt: todo.created_at,
  };
}

export function createGitlabClient(): ProviderClient {
  return {
    id: "gitlab",

    async validate(config: AccountConfig): Promise<{ username: string }> {
      const baseUrl = resolveBaseUrl(config);
      const { body } = await getJson(
        `${baseUrl}/api/v4/user`,
        headers(config),
        context(baseUrl)
      );
      const user = body as GitlabUser | undefined;
      if (!user || typeof user.username !== "string") {
        throw new Error(
          `${baseUrl} accepted the token but returned no username — is it really a GitLab instance?`
        );
      }
      return { username: user.username };
    },

    async fetchItems(config: AccountConfig): Promise<FetchedItem[]> {
      const baseUrl = resolveBaseUrl(config);
      const ctx = context(baseUrl);
      const items: FetchedItem[] = [];
      let page: string | undefined = "1";

      for (let fetched = 0; fetched < MAX_PAGES && page; fetched++) {
        const { headers: responseHeaders, body } = await getJson(
          `${baseUrl}/api/v4/todos?state=pending&per_page=50&page=${page}`,
          headers(config),
          ctx
        );
        if (body === undefined || !Array.isArray(body)) break;

        for (const raw of body) {
          try {
            items.push(toFetchedItem(raw as GitlabTodo));
          } catch {
            // One malformed todo must not kill the whole fetch.
          }
        }

        const next = responseHeaders.get("x-next-page");
        page = next && next.trim() !== "" ? next.trim() : undefined;
      }

      return items;
    },
  };
}
