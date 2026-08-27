// Sync-error banner: connected accounts whose last sync failed, shown only
// while the inbox pane is visible.

import type { AccountState, ProviderId } from "../../shared/types";
import { WarningIcon } from "./Icons";

const PROVIDER_NAMES: Record<ProviderId, string> = { github: "GitHub", gitlab: "GitLab" };

interface BannerProps {
  accounts: AccountState[];
  show: boolean;
}

export function Banner({ accounts, show }: BannerProps) {
  const errors = accounts
    .filter((a) => a.connected && a.error)
    .map((a) => `${PROVIDER_NAMES[a.provider]}: ${a.error ?? ""}`);
  if (!show || errors.length === 0) {
    return null;
  }
  const text = errors.join(" · ");
  return (
    <div id="banner" title={text}>
      <WarningIcon />
      <span className="banner-text">{text}</span>
    </div>
  );
}
