// Main-window title bar: draggable chrome (the frame's title bar is hidden on
// macOS) naming the category the list is showing, with the sync status and
// quick actions gathered on the trailing edge. The traffic lights sit on the
// sidebar, so this bar starts where the list does.

import { IconButton } from "../components/IconButton";
import { MarkAllReadIcon, RefreshIcon, SpinnerIcon } from "../components/Icons";
import { syncedLabel } from "../format";

interface MainHeaderProps {
  /** The selected category — what the list below is showing. */
  title: string;
  subtitle: string;
  syncing: boolean;
  lastSyncAt: string | null;
  now: number;
  anyUnread: boolean;
  onRefresh: () => void;
  onMarkAllRead: () => void;
}

export function MainHeader({
  title,
  subtitle,
  syncing,
  lastSyncAt,
  now,
  anyUnread,
  onRefresh,
  onMarkAllRead,
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
    </header>
  );
}
