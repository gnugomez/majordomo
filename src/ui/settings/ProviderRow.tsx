// One provider in the Accounts group: glyph + name left; connection status
// and actions right. The inline connect form and the sync-warning row render
// as sibling rows in the same group container (hairline rhythm).

import type { AccountConfig, AccountState } from "../../shared/types";
import type { ProviderDef } from "./SettingsPane";
import { ProviderIcon, WarningIcon } from "../components/Icons";
import { ConnectForm } from "./ConnectForm";

interface ProviderRowProps {
  def: ProviderDef;
  account: AccountState;
  busy: boolean;
  formOpen: boolean;
  onToggleForm: () => void;
  onConnect: (config: AccountConfig) => void;
  onDisconnect: () => void;
}

function safeHost(baseUrl: string): string {
  try {
    return new URL(baseUrl).host;
  } catch {
    return "";
  }
}

export function ProviderRow({
  def,
  account,
  busy,
  formOpen,
  onToggleForm,
  onConnect,
  onDisconnect,
}: ProviderRowProps) {
  const connected = account.connected;
  const warn = connected && Boolean(account.error);
  const host = connected && def.id === "gitlab" && account.baseUrl ? safeHost(account.baseUrl) : "";

  return (
    <>
      <div className="group-row provider-row">
        <span className="provider-mark">
          <ProviderIcon provider={def.id} />
        </span>
        <span className="provider-label">
          <span className="provider-name">{def.name}</span>
          {host && <span className="provider-sub">{host}</span>}
        </span>
        {connected
          ? (
              <span className="connected-side">
                <span className="acct-user">
                  @
                  {account.username ?? "unknown"}
                </span>
                <span
                  className={warn ? "status-dot warn" : "status-dot ok"}
                  title={warn ? "Sync error" : "Connected"}
                />
                <button
                  type="button"
                  className="row-btn"
                  aria-label={`Disconnect ${def.name}`}
                  onClick={onDisconnect}
                >
                  Disconnect
                </button>
              </span>
            )
          : (
              <button
                type="button"
                className="row-btn"
                disabled={busy}
                aria-expanded={formOpen}
                aria-label={formOpen ? `Cancel connecting ${def.name}` : `Connect ${def.name}`}
                onClick={onToggleForm}
              >
                {formOpen ? "Cancel" : "Connect…"}
              </button>
            )}
      </div>
      <ConnectForm
        def={def}
        account={account}
        busy={busy}
        open={formOpen && !connected}
        onConnect={onConnect}
      />
      {warn && (
        <div className="group-row warn-row">
          <WarningIcon />
          <span>{account.error}</span>
        </div>
      )}
    </>
  );
}
