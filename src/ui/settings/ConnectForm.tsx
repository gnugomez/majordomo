// Inline connect form: display:contents, so its rows sit in the group
// container and pick up the same inset hairlines. The component stays
// mounted while collapsed (rows hidden per-row) so typed values survive
// collapse/expand, state pushes, and re-renders.

import type { FormEvent } from "react";
import type { AccountConfig, AccountState } from "../../shared/types";
import type { ProviderDef } from "./SettingsPane";
import { useEffect, useRef, useState } from "react";

interface ConnectFormProps {
  def: ProviderDef;
  account: AccountState;
  busy: boolean;
  open: boolean;
  onConnect: (config: AccountConfig) => void;
}

function validBaseUrl(value: string): boolean {
  if (!value) {
    return false;
  }
  try {
    const url = new URL(value);
    return url.protocol === "http:" || url.protocol === "https:";
  } catch {
    return false;
  }
}

export function ConnectForm({ def, account, busy, open, onConnect }: ConnectFormProps) {
  const [url, setUrl] = useState("");
  const [token, setToken] = useState("");
  const [localError, setLocalError] = useState<string | null>(null);
  const urlRef = useRef<HTMLInputElement>(null);
  const tokenRef = useRef<HTMLInputElement>(null);

  // Clear the secret once the connect lands so it doesn't linger in the DOM
  // (stale validation errors go with it).
  useEffect(() => {
    if (account.connected) {
      setToken("");
      setLocalError(null);
    }
  }, [account.connected]);

  // Expanding the form focuses its first field.
  useEffect(() => {
    if (open) {
      (urlRef.current ?? tokenRef.current)?.focus();
    }
  }, [open]);

  const submit = (event: FormEvent): void => {
    event.preventDefault();
    const trimmedToken = token.trim();
    let baseUrl: string | undefined;
    if (def.needsBaseUrl) {
      baseUrl = url.trim().replace(/\/+$/, "");
      if (!validBaseUrl(baseUrl)) {
        setLocalError("Enter your GitLab instance URL, e.g. https://gitlab.example.com");
        return;
      }
    }
    if (!trimmedToken) {
      setLocalError("Enter a personal access token.");
      return;
    }
    setLocalError(null);
    onConnect(
      baseUrl !== undefined ? { token: trimmedToken, baseUrl } : { token: trimmedToken },
    );
  };

  const error
    = busy || account.connected ? "" : localError ?? account.error ?? "";

  return (
    <form className="connect-form" noValidate onSubmit={submit}>
      {def.needsBaseUrl && (
        <div className="group-row field-row" hidden={!open}>
          <input
            ref={urlRef}
            type="text"
            placeholder="https://gitlab.example.com"
            aria-label={`${def.name} base URL`}
            autoComplete="off"
            spellCheck={false}
            autoCapitalize="off"
            autoCorrect="off"
            disabled={busy}
            value={url}
            onChange={(e) => setUrl(e.target.value)}
          />
        </div>
      )}
      <div className="group-row field-row" hidden={!open}>
        <input
          ref={tokenRef}
          type="password"
          placeholder="Personal access token"
          aria-label={`${def.name} personal access token`}
          autoComplete="off"
          spellCheck={false}
          autoCapitalize="off"
          autoCorrect="off"
          disabled={busy}
          value={token}
          onChange={(e) => setToken(e.target.value)}
        />
      </div>
      <div className="group-row action-row" hidden={!open}>
        <button type="submit" className="primary-btn" disabled={busy}>
          {busy ? "Validating…" : "Connect"}
        </button>
      </div>
      <div className="group-row error-row" role="alert" hidden={!open}>
        {error}
      </div>
    </form>
  );
}
