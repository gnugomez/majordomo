import type { InboxItem } from "../../shared/types";
import { KindIcon, ProviderIcon } from "../components/Icons";
import { humanizeReason, relativeTime } from "../format";

interface ItemRowProps {
  item: InboxItem;
  now: number;
  onOpen: (id: string) => void;
}

export function ItemRow({ item, now, onOpen }: ItemRowProps) {
  // A merged/closed/draft PR or MR shows its STATE in the capsule — the
  // stored reason ("review requested" on a merged PR) would be stale. Open
  // or unknown state keeps the reason capsule; issues always keep it (their
  // state shows via the icon alone).
  const isPullLike = item.kind === "pull" || item.kind === "merge";
  const stateCapsule
    = isPullLike && item.state && item.state !== "open" ? item.state : null;

  // GitHub renders completed issues purple, not red — only closed PRs/MRs
  // are red.
  const kindIconClass = !item.state
    ? "kind-icon"
    : item.state === "closed" && item.kind === "issue"
      ? "kind-icon state-closed-issue"
      : `kind-icon state-${item.state}`;

  return (
    <button
      type="button"
      className={item.read ? "row" : "row unread"}
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
          <span className={kindIconClass}>
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
          {stateCapsule
            ? (
                <span className={`capsule state-${stateCapsule}`}>{stateCapsule}</span>
              )
            : (
                <span className={item.isMention ? "capsule mention" : "capsule"}>
                  {humanizeReason(item.reason)}
                </span>
              )}
        </span>
      </span>
    </button>
  );
}
