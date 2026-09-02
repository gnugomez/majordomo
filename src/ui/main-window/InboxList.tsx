// Left pane of the main window: every inbox item, newest first, as the same
// rows the popover draws — clicking selects for the preview instead of
// opening the browser.

import type { InboxItem } from "../../shared/types";
import { EmptyState } from "../components/EmptyState";
import { CheckCircleIcon, InboxIcon } from "../components/Icons";
import { ItemRow } from "../inbox/ItemRow";

interface InboxListProps {
  items: InboxItem[];
  anyConnected: boolean;
  selectedId: string | null;
  now: number;
  onSelect: (id: string) => void;
}

export function InboxList({ items, anyConnected, selectedId, now, onSelect }: InboxListProps) {
  if (!anyConnected) {
    return (
      <EmptyState
        icon={<InboxIcon />}
        title="No accounts connected"
        caption="Connect GitHub or a self-hosted GitLab from the tray popover to see your inbox here."
      />
    );
  }
  if (items.length === 0) {
    return (
      <EmptyState
        icon={<CheckCircleIcon />}
        title="You're all caught up"
        caption="Nothing needs your attention right now."
      />
    );
  }
  return (
    <div className="rows">
      {items.map((item) => (
        <ItemRow
          key={item.id}
          item={item}
          now={now}
          selected={item.id === selectedId}
          onOpen={onSelect}
        />
      ))}
    </div>
  );
}
