import { syncedLabel } from "../format";
import { IconButton } from "./IconButton";
import {
  MarkAllReadIcon,
  RefreshIcon,
  SettingsIcon,
  SpinnerIcon,
} from "./Icons";

interface HeaderProps {
  syncing: boolean;
  lastSyncAt: string | null;
  now: number;
  anyUnread: boolean;
  settingsOpen: boolean;
  onRefresh: () => void;
  onMarkAllRead: () => void;
  onToggleSettings: () => void;
  onOpenMainWindow: () => void;
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
  onOpenMainWindow,
}: HeaderProps) {
  return (
    <header className="header">
      {/* The app name doubles as the way into the main window — a fourth icon
          for it crowded a header that is only 380px wide. */}
      <h1 className="panel-title">
        <button type="button" className="title-btn" title="Open Majordomo" onClick={onOpenMainWindow}>
          Majordomo
        </button>
      </h1>
      <div className="sync-status" aria-live="polite">
        {syncing
          ? (
              <>
                <SpinnerIcon />
                <span>Syncing…</span>
              </>
            )
          : (
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
      {/* Toggles: pressing it again closes the settings pane. */}
      <IconButton
        icon={<SettingsIcon />}
        label="Settings"
        active={settingsOpen}
        onClick={onToggleSettings}
      />
    </header>
  );
}
