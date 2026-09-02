// Main-window title bar: draggable chrome (the frame's title bar is hidden on
// macOS) naming what the content below is showing, with the sync status and
// quick actions gathered on the trailing edge. The traffic lights sit on the
// sidebar, so this bar starts where the list does.

import { IconButton } from "../components/IconButton";
import { MarkAllReadIcon, RefreshIcon, SettingsIcon, SpinnerIcon } from "../components/Icons";
import { syncedLabel } from "../format";

interface MainHeaderProps {
  /** What the content below is: the selected category, or "Settings". */
  title: string;
  subtitle: string;
  /** Refresh and mark-all-read are about the inbox, so settings hides them. */
  showActions: boolean;
  settingsOpen: boolean;
  syncing: boolean;
  lastSyncAt: string | null;
  now: number;
  anyUnread: boolean;
  onRefresh: () => void;
  onMarkAllRead: () => void;
  onToggleSettings: () => void;
}

export function MainHeader({
  title,
  subtitle,
  showActions,
  settingsOpen,
  syncing,
  lastSyncAt,
  now,
  anyUnread,
  onRefresh,
  onMarkAllRead,
  onToggleSettings,
}: MainHeaderProps) {
  return (
    <header className="main-header">
      <div className="main-title">
        <h1 className="panel-title">{title}</h1>
        <span className="main-subtitle">{subtitle}</span>
      </div>
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
      {showActions && (
        <>
          <IconButton
            icon={<RefreshIcon />}
            label="Refresh now"
            disabled={syncing}
            onClick={onRefresh}
          />
          <IconButton
            icon={<MarkAllReadIcon />}
            label="Mark all as read"
            disabled={!anyUnread}
            onClick={onMarkAllRead}
          />
        </>
      )}
      {/* Toggles: pressing it again goes back to the inbox. */}
      <IconButton
        icon={<SettingsIcon />}
        label="Settings"
        active={settingsOpen}
        onClick={onToggleSettings}
      />
    </header>
  );
}
