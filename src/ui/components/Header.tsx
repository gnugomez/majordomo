import { syncedLabel } from "../format";
import { GearIcon, MarkAllReadIcon, RefreshIcon, SpinnerIcon } from "./Icons";
import { IconButton } from "./IconButton";

interface HeaderProps {
  syncing: boolean;
  lastSyncAt: string | null;
  now: number;
  anyUnread: boolean;
  settingsOpen: boolean;
  onRefresh: () => void;
  onMarkAllRead: () => void;
  onToggleSettings: () => void;
}

export function Header({
  syncing,
  lastSyncAt,
  now,
  anyUnread,
  settingsOpen,
  onRefresh,
  onMarkAllRead,
  onToggleSettings,
}: HeaderProps) {
  return (
    <header className="header">
      <h1 className="panel-title">Majordomo</h1>
      <div className="sync-status" aria-live="polite">
        {syncing ? (
          <>
            <SpinnerIcon />
            <span>Syncing…</span>
          </>
        ) : (
          syncedLabel(lastSyncAt, now)
        )}
      </div>
      <IconButton icon={<RefreshIcon />} label="Refresh now" disabled={syncing} onClick={onRefresh} />
      <IconButton
        icon={<MarkAllReadIcon />}
        label="Mark all as read"
        disabled={!anyUnread}
        onClick={onMarkAllRead}
      />
      {/* The gear toggles: pressing it again closes the settings pane. */}
      <IconButton
        icon={<GearIcon />}
        label="Settings"
        active={settingsOpen}
        onClick={onToggleSettings}
      />
    </header>
  );
}
