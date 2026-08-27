// Shared error phrasing for provider clients. The client libraries throw
// their own error shapes; the providers map every failure through these
// helpers so that only human-readable messages reach the UI. The strings
// surface directly in the Accounts pane, so they must be helpful.

/** Time cap applied to every request either provider makes. */
export const TIMEOUT_MS = 15_000;

/** Context used to phrase error messages for a given provider. */
export interface RequestContext {
  /** Display name used in messages, e.g. "GitHub" or "GitLab". */
  service: string;
  /** Origin shown in reachability errors, e.g. "https://gitlab.example.com". */
  origin: string;
  /** True when the origin was typed by the user (self-hosted GitLab). */
  originIsUserSupplied: boolean;
}

/** The request hit the 15-second cap. */
export function timeoutMessage(ctx: RequestContext): string {
  return `${ctx.service} did not respond within 15 seconds — ${ctx.origin} may be slow or unreachable.`;
}

/** The host could not be reached at all (DNS, refused connection, offline). */
export function unreachableMessage(ctx: RequestContext): string {
  return ctx.originIsUserSupplied
    ? `Could not reach ${ctx.origin} — is the URL right?`
    : `Could not reach ${ctx.service} — check your network connection.`;
}

/** The host answered, but with a body that was not JSON. */
export function invalidJsonMessage(ctx: RequestContext): string {
  return (
    `${ctx.service} returned a response that was not valid JSON — ` +
    (ctx.originIsUserSupplied
      ? `is ${ctx.origin} really a ${ctx.service} instance?`
      : "try again later.")
  );
}

/** The host answered with a non-success HTTP status. */
export function statusMessage(status: number, ctx: RequestContext): string {
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
