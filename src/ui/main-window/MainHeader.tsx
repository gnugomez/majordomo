// Main-window title bar: draggable chrome (the frame's title bar is hidden
// on macOS) carrying the same title, sync status, and quick actions as the
// popover header — minus the popover-only settings toggle.

import { IconButton } from "../components/IconButton";
import { MarkAllReadIcon, RefreshIcon, SpinnerIcon } from "../components/Icons";
import { syncedLabel } from "../format";

interface MainHeaderProps {
  syncing: boolean;
  lastSyncAt: string | null;
  now: number;
  anyUnread: boolean;
  onRefresh: () => void;
  onMarkAllRead: () => void;
}

export function MainHeader({
  syncing,
  lastSyncAt,
  now,
  anyUnread,
  onRefresh,
  onMarkAllRead,
}: MainHeaderProps) {
  return (
    <header className="main-header">
      <h1 className="panel-title">Majordomo</h1>
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
    </header>
  );
}
