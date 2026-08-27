import type { InboxItem } from "../../shared/types";
import { humanizeReason, relativeTime } from "../format";
import { KindIcon, ProviderIcon } from "../components/Icons";

interface ItemRowProps {
  item: InboxItem;
  now: number;
  onOpen: (id: string) => void;
}

export function ItemRow({ item, now, onOpen }: ItemRowProps) {
  return (
    <button
      type="button"
      className={item.read ? "row" : "row unread"}
      title={item.title}
      onClick={() => onOpen(item.id)}
    >
      {/* Circular provider badge, like the device/network circles in the
          system's own menus: accent-filled while unread, translucent gray
          once read. */}
      <span className="provider-badge">
        <ProviderIcon provider={item.provider} />
      </span>
      <span className="row-content">
        <span className="row-line1">
          <span className="kind-icon">
            <KindIcon kind={item.kind} />
          </span>
          <span className="row-title">{item.title}</span>
        </span>
        <span className="row-line2">
          <span className="row-meta">
            <span className="row-repo">{item.repo}</span>
            <span className="row-sep">·</span>
            <span className="rel-time">{relativeTime(item.updatedAt, now)}</span>
          </span>
          <span className={item.isMention ? "capsule mention" : "capsule"}>
            {humanizeReason(item.reason)}
          </span>
        </span>
      </span>
    </button>
  );
}
