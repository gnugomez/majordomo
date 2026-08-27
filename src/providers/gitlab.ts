// GitLab provider client for self-hosted instances, built on @gitbeaker/rest.
// config.baseUrl is the instance origin (e.g. "https://gitlab.example.com")
// and is required.

import type { Gitlab } from "@gitbeaker/rest";
import type { AccountConfig } from "../shared/types";
import type { FetchedItem, ProviderClient } from "./types";
import {
  TIMEOUT_MS,
  invalidJsonMessage,
  statusMessage,
  timeoutMessage,
  unreachableMessage,
  type RequestContext,
} from "./errors";

const MAX_PAGES = 2;
const PER_PAGE = 50;

const MENTION_ACTIONS = new Set(["mentioned", "directly_addressed", "review_requested"]);

// Loaded lazily at the point of use so the library is never evaluated during
// startup — createProviders() runs in the main process boot path.
let gitbeakerModule: Promise<typeof import("@gitbeaker/rest")> | undefined;

function loadGitbeaker(): Promise<typeof import("@gitbeaker/rest")> {
  gitbeakerModule ??= import("@gitbeaker/rest");
  return gitbeakerModule;
}

// Minimal shapes: only the fields we read. Gitbeaker's TodoSchema types
// project and target as required; the API can omit them, so we keep our own
// honest shape and narrow each entry to it.
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

async function createClient(config: AccountConfig, baseUrl: string): Promise<Gitlab> {
  const { Gitlab } = await loadGitbeaker();
  return new Gitlab({
    host: baseUrl,
    token: config.token,
    queryTimeout: TIMEOUT_MS,
  });
}

/** Reads the HTTP status a GitbeakerRequestError carries in its cause. */
function requestErrorStatus(error: Error): number | undefined {
  const cause = (error as { cause?: { response?: { status?: unknown } } }).cause;
  const status = cause?.response?.status;
  return typeof status === "number" ? status : undefined;
}

/** Maps a gitbeaker failure to an Error whose message is fit for the UI. */
function toFriendlyError(error: unknown, ctx: RequestContext): Error {
  if (error instanceof Error) {
    switch (error.name) {
      case "GitbeakerTimeoutError":
        // queryTimeout elapsed before the instance answered.
        return new Error(timeoutMessage(ctx));
      case "GitbeakerRequestError": {
        // The instance answered with a non-success status.
        const status = requestErrorStatus(error);
        return new Error(
          status === undefined ? unreachableMessage(ctx) : statusMessage(status, ctx)
        );
      }
      case "GitbeakerRetryError": {
        // Thrown after gitbeaker exhausts its built-in retries on 429/502;
        // the final status only travels in the message text.
        const match = /last status code: (\d+)/.exec(error.message);
        const status = match ? Number(match[1]) : 502;
        return new Error(statusMessage(status, ctx));
      }
      case "SyntaxError":
        // The body claimed to be JSON but did not parse.
        return new Error(invalidJsonMessage(ctx));
      case "AbortError":
      case "TimeoutError":
        return new Error(timeoutMessage(ctx));
      default:
        break;
    }
  }
  // Anything else is a network-level failure (DNS, refused connection, TLS).
  return new Error(unreachableMessage(ctx));
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
      const api = await createClient(config, baseUrl);
      let body: unknown;
      try {
        body = await api.Users.showCurrentUser();
      } catch (error) {
        throw toFriendlyError(error, context(baseUrl));
      }
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
      const api = await createClient(config, baseUrl);
      // Pending todos are the inbox; one page of recently-done todos rides
      // along so items handled on the web while the app was closed still
      // arrive (as already-read).
      const lists: Array<{ state: "pending" | "done"; maxPages: number; read: boolean }> = [
        { state: "pending", maxPages: MAX_PAGES, read: false },
        { state: "done", maxPages: 1, read: true },
      ];
      const items: FetchedItem[] = [];
      for (const list of lists) {
        let body: unknown;
        try {
          // perPage + maxPages cap each fetch; gitbeaker follows the
          // pagination headers under the hood.
          body = await api.TodoLists.all({
            state: list.state,
            perPage: PER_PAGE,
            maxPages: list.maxPages,
          });
        } catch (error) {
          throw toFriendlyError(error, context(baseUrl));
        }
        if (!Array.isArray(body)) continue;
        for (const raw of body) {
          try {
            items.push({ ...toFetchedItem(raw as GitlabTodo), upstreamRead: list.read });
          } catch {
            // One malformed todo must not kill the whole fetch.
          }
        }
      }
      return items;
    },
  };
}
