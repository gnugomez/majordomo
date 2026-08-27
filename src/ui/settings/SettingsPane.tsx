// Settings pane, styled as native grouped lists (the System Settings
// "Known Networks" pattern): a caption above a single rounded container per
// section, hairline-separated rows inside. Each provider is one row; its
// connect form expands inline beneath the row as extra rows in the same
// container, one open at a time.

import { useEffect, useState } from "react";
import type { AccountConfig, AccountState, AppState, ProviderId } from "../../shared/types";
import { GeneralGroup } from "./GeneralGroup";
import { ProviderRow } from "./ProviderRow";

export interface ProviderDef {
  id: ProviderId;
  name: string;
  needsBaseUrl: boolean;
}

const PROVIDERS: ProviderDef[] = [
  { id: "github", name: "GitHub", needsBaseUrl: false },
  { id: "gitlab", name: "GitLab", needsBaseUrl: true },
];

interface SettingsPaneProps {
  state: AppState;
  connecting: Record<ProviderId, boolean>;
  open: boolean;
  onConnect: (provider: ProviderId, config: AccountConfig) => void;
  onDisconnect: (provider: ProviderId) => void;
  onToggleLaunchAtLogin: (next: boolean) => void;
}

export function SettingsPane({
  state,
  connecting,
  open,
  onConnect,
  onDisconnect,
  onToggleLaunchAtLogin,
}: SettingsPaneProps) {
  // Which provider's inline form is open (one at a time). Collapsed forms
  // keep their typed values — the form components stay mounted.
  const [openForm, setOpenForm] = useState<ProviderId | null>(null);

  // Collapse the form once its connect lands (also covers pushes that
  // arrive already-connected).
  useEffect(() => {
    if (openForm && state.accounts.some((a) => a.provider === openForm && a.connected)) {
      setOpenForm(null);
    }
  }, [state.accounts, openForm]);

  return (
    <section className="pane" id="settings" aria-hidden={!open}>
      <h3 className="settings-caption">Accounts</h3>
      <section className="settings-group has-glyphs">
        {PROVIDERS.map((def) => {
          const account: AccountState = state.accounts.find((a) => a.provider === def.id) ?? {
            provider: def.id,
            connected: false,
          };
          return (
            <ProviderRow
              key={def.id}
              def={def}
              account={account}
              busy={connecting[def.id]}
              formOpen={openForm === def.id}
              onToggleForm={() => setOpenForm(openForm === def.id ? null : def.id)}
              onConnect={(config) => onConnect(def.id, config)}
              onDisconnect={() => onDisconnect(def.id)}
            />
          );
        })}
      </section>
      <h3 className="settings-caption">General</h3>
      <GeneralGroup launchAtLogin={state.launchAtLogin} onToggleLaunchAtLogin={onToggleLaunchAtLogin} />
    </section>
  );
}
