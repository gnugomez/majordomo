// Middle pane of the main window: the selected category's items, newest
// first, as the same rows the popover draws — clicking selects for the
// preview instead of opening the browser.

import type { InboxItem } from "../../shared/types";
import type { CategoryId } from "../inbox/categories";
import { EmptyState } from "../components/EmptyState";
import { CheckCircleIcon, InboxIcon } from "../components/Icons";
import { ItemRow } from "../inbox/ItemRow";

interface InboxListProps {
  items: InboxItem[];
  categoryId: CategoryId;
  anyConnected: boolean;
  selectedId: string | null;
  now: number;
  onSelect: (id: string) => void;
}

export function InboxList({
  items,
  categoryId,
  anyConnected,
  selectedId,
  now,
  onSelect,
}: InboxListProps) {
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
    return categoryId === "recent"
      ? (
          <EmptyState
            icon={<CheckCircleIcon />}
            title="You're all caught up"
            caption="Nothing needs your attention right now."
          />
        )
      : (
          <EmptyState
            icon={<InboxIcon />}
            title="Nothing here"
            caption="Pick another category in the sidebar to see the rest of your inbox."
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
