import type { InboxItem } from "../../shared/types";
import { KindIcon, ProviderIcon } from "../components/Icons";
import { reasonLabel, relativeTime } from "../format";
import { kindIconClass, stateCapsule } from "./itemVisuals";

interface ItemRowProps {
  item: InboxItem;
  now: number;
  /** Popover: opens in the browser. Main window: selects for the preview. */
  onOpen: (id: string) => void;
  /** Highlights the row as the main window's current selection. */
  selected?: boolean;
}

export function ItemRow({ item, now, onOpen, selected }: ItemRowProps) {
  const capsule = stateCapsule(item);
  const className = [item.read ? "row" : "row unread", selected && "selected"]
    .filter(Boolean)
    .join(" ");

  return (
    <button
      type="button"
      className={className}
      // The main window's keyboard navigation scrolls rows into view by id.
      data-item-id={item.id}
      title={item.title}
      onClick={() => onOpen(item.id)}
    >
      {/* Circular provider badge, like the device/network circles in the
          system's own menus; unread shows as a small accent dot on the
          badge's top-right corner (CSS ::after). */}
      <span className="provider-badge">
        <ProviderIcon provider={item.provider} />
      </span>
      <span className="row-content">
        <span className="row-line1">
          <span className={kindIconClass(item)}>
            <KindIcon kind={item.kind} state={item.state} />
          </span>
          <span className="row-title">{item.title}</span>
        </span>
        <span className="row-line2">
          <span className="row-meta">
            <span className="row-repo">{item.repo}</span>
            {item.author && (
              <>
                <span className="row-sep">·</span>
                <span className="row-author">{item.author}</span>
              </>
            )}
            <span className="row-sep">·</span>
            <span className="rel-time">{relativeTime(item.updatedAt, now)}</span>
          </span>
          {capsule
            ? (
                <span className={`capsule state-${capsule}`}>{capsule}</span>
              )
            : (
                <span className={item.isMention ? "capsule mention" : "capsule"}>
                  {reasonLabel(item.reason)}
                </span>
              )}
        </span>
      </span>
    </button>
  );
}
