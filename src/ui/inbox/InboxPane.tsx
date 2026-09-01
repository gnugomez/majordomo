import type { ReactNode } from "react";
import type { AppState, InboxItem } from "../../shared/types";
import { EmptyState } from "../components/EmptyState";
import { CheckCircleIcon, InboxIcon } from "../components/Icons";
import { DisclosureSection } from "./DisclosureSection";

interface InboxPaneProps {
  state: AppState;
  now: number;
  onOpenItem: (id: string) => void;
  onOpenSettings: () => void;
}

function itemTime(iso: string): number {
  const t = Date.parse(iso);
  return Number.isNaN(t) ? 0 : t;
}

interface SectionDef {
  id: string;
  label: string;
  items: InboxItem[];
  defaultCollapsed: boolean;
}

/**
 * "Overview" holds everything, newest first; the categories below re-show
 * the same items grouped. Categories are disjoint: review requests are
 * carved out first (both providers flag reason "review_requested" as a
 * mention, so a plain isMention filter would swallow them all), then
 * mentions, then the remainder splits by kind.
 */
function categorize(items: InboxItem[]): SectionDef[] {
  const reviews = items.filter((i) => i.reason === "review_requested");
  const mentions = items.filter((i) => i.isMention && i.reason !== "review_requested");
  const rest = items.filter((i) => !i.isMention && i.reason !== "review_requested");
  const issues = rest.filter((i) => i.kind === "issue");
  const pulls = rest.filter((i) => i.kind === "pull" || i.kind === "merge");
  return [
    { id: "overview", label: "Overview", items, defaultCollapsed: false },
    { id: "mentions", label: "Mentions", items: mentions, defaultCollapsed: true },
    { id: "reviews", label: "Review requests", items: reviews, defaultCollapsed: true },
    { id: "issues", label: "Issues", items: issues, defaultCollapsed: true },
    { id: "pulls", label: "Pull & merge requests", items: pulls, defaultCollapsed: true },
  ];
}

export function InboxPane({ state, now, onOpenItem, onOpenSettings }: InboxPaneProps) {
  let content: ReactNode;

  const anyConnected = state.accounts.some((a) => a.connected);
  const items = [...state.items].sort((a, b) => itemTime(b.updatedAt) - itemTime(a.updatedAt));

  if (!anyConnected) {
    content = (
      <EmptyState
        icon={<InboxIcon />}
        title="No accounts connected"
        caption="Connect GitHub or a self-hosted GitLab to see your mentions in one place."
        action={{ label: "Connect an account", onClick: onOpenSettings }}
      />
    );
  } else if (items.length === 0) {
    content = (
      <EmptyState
        icon={<CheckCircleIcon />}
        title="You're all caught up"
        caption="Nothing needs your attention right now."
      />
    );
  } else {
    content = categorize(items)
      .filter((def) => def.items.length > 0)
      .map((def) => (
        <DisclosureSection
          key={def.id}
          id={def.id}
          label={def.label}
          items={def.items}
          defaultCollapsed={def.defaultCollapsed}
          now={now}
          onOpenItem={onOpenItem}
        />
      ));
  }

  return (
    <div className="pane" id="inbox">
      {content}
    </div>
  );
}
