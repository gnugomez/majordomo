// Shared HTTP helper for provider clients: 15s timeout, JSON parsing, and
// mapping of failures to human-readable messages. The messages thrown here
// surface directly in the Accounts pane, so they must be helpful.

const TIMEOUT_MS = 15_000;

/** Context used to phrase error messages for a given provider. */
export interface RequestContext {
  /** Display name used in messages, e.g. "GitHub" or "GitLab". */
  service: string;
  /** Origin shown in reachability errors, e.g. "https://gitlab.example.com". */
  origin: string;
  /** True when the origin was typed by the user (self-hosted GitLab). */
  originIsUserSupplied: boolean;
}

/** Result of a successful (2xx or 304) request. */
export interface JsonResponse {
  status: number;
  headers: Headers;
  /** Parsed JSON body, or undefined for a 304 / empty body. */
  body: unknown;
}

/**
 * Performs a GET request with a 15-second timeout and parses the JSON body.
 * 2xx and 304 resolve; everything else (including network failures and
 * timeouts) rejects with an Error whose message is fit for the UI.
 */
export async function getJson(
  url: string,
  headers: Record<string, string>,
  ctx: RequestContext
): Promise<JsonResponse> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);

  let response: Response;
  try {
    response = await fetch(url, { headers, signal: controller.signal });
  } catch (error) {
    throw new Error(reachabilityMessage(error, ctx));
  } finally {
    clearTimeout(timer);
  }

  if (!response.ok && response.status !== 304) {
    throw new Error(statusMessage(response.status, ctx));
  }

  if (response.status === 304 || response.status === 204) {
    return { status: response.status, headers: response.headers, body: undefined };
  }

  const text = await response.text();
  if (text.trim() === "") {
    return { status: response.status, headers: response.headers, body: undefined };
  }

  try {
    return { status: response.status, headers: response.headers, body: JSON.parse(text) };
  } catch {
    throw new Error(
      `${ctx.service} returned a response that was not valid JSON — ` +
        (ctx.originIsUserSupplied
          ? `is ${ctx.origin} really a ${ctx.service} instance?`
          : "try again later.")
    );
  }
}

function reachabilityMessage(error: unknown, ctx: RequestContext): string {
  if (error instanceof Error && error.name === "AbortError") {
    return `${ctx.service} did not respond within 15 seconds — ${ctx.origin} may be slow or unreachable.`;
  }
  return ctx.originIsUserSupplied
    ? `Could not reach ${ctx.origin} — is the URL right?`
    : `Could not reach ${ctx.service} — check your network connection.`;
}

function statusMessage(status: number, ctx: RequestContext): string {
  switch (status) {
    case 401:
      return `${ctx.service} token was rejected (401) — check the token and its scopes.`;
    case 403:
      return `${ctx.service} refused the request (403) — the token may be missing scopes, or you may be rate-limited.`;
    case 404:
      return ctx.originIsUserSupplied
        ? `${ctx.origin} answered with 404 — is the base URL pointing at a ${ctx.service} instance?`
        : `${ctx.service} returned an unexpected 404 — try again later.`;
    default:
      if (status >= 500) {
        return `${ctx.service} is having trouble right now (HTTP ${status}) — try again later.`;
      }
      return `${ctx.service} request failed (HTTP ${status}).`;
  }
}
