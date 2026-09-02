// Right pane of the main window: everything AppState already knows about the
// selected item. Deliberately no provider fetches — bodies and comments need
// extra token scopes, so the browser is one click away instead.

import type { InboxItem, ProviderId } from "../../shared/types";
import { EmptyState } from "../components/EmptyState";
import { ArrowOutwardIcon, InboxIcon, KindIcon, ProviderIcon } from "../components/Icons";
import { humanizeReason, relativeTime } from "../format";
import { kindIconClass, stateCapsule } from "../inbox/itemVisuals";

const PROVIDER_NAMES: Record<ProviderId, string> = { github: "GitHub", gitlab: "GitLab" };

interface PreviewPaneProps {
  item: InboxItem | null;
  now: number;
  /** The shared openItem action: opens in the browser and marks read. */
  onOpen: (id: string) => void;
}

/** "2026-09-02T08:41:00Z" → "Sep 2, 2026, 10:41" in the user's locale. */
function absoluteTime(iso: string): string {
  const date = new Date(iso);
  if (Number.isNaN(date.getTime())) {
    return iso;
  }
  return date.toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
}

export function PreviewPane({ item, now, onOpen }: PreviewPaneProps) {
  if (!item) {
    return (
      <EmptyState
        icon={<InboxIcon />}
        title="Nothing selected"
        caption="Select an item from the list to see its details."
      />
    );
  }

  const capsule = stateCapsule(item);
  const providerName = PROVIDER_NAMES[item.provider];

  return (
    <article className="preview">
      <div className="preview-top">
        <span className={kindIconClass(item)}>
          <KindIcon kind={item.kind} state={item.state} />
        </span>
        <h2 className="preview-title">{item.title}</h2>
      </div>
      <div className="preview-badges">
        {capsule && <span className={`capsule state-${capsule}`}>{capsule}</span>}
        <span className={item.isMention ? "capsule mention" : "capsule"}>
          {humanizeReason(item.reason)}
        </span>
        {!item.read && <span className="capsule unread">unread</span>}
      </div>
      <dl className="preview-fields">
        <dt>Provider</dt>
        <dd className="preview-provider">
          <ProviderIcon provider={item.provider} />
          {providerName}
        </dd>
        <dt>Repository</dt>
        <dd>{item.repo}</dd>
        {item.author && (
          <>
            <dt>Author</dt>
            <dd>{item.author}</dd>
          </>
        )}
        <dt>Updated</dt>
        <dd>
          {absoluteTime(item.updatedAt)}
          {" · "}
          {relativeTime(item.updatedAt, now)}
        </dd>
      </dl>
      <div className="preview-actions">
        <button type="button" className="primary-btn preview-open" onClick={() => onOpen(item.id)}>
          <ArrowOutwardIcon />
          {`Open in ${providerName}`}
        </button>
        <span className="preview-hint">Opens in your browser and marks the item read.</span>
      </div>
    </article>
  );
}
