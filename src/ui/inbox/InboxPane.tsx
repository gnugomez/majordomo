import type { ReactNode } from "react";
import type { AppState } from "../../shared/types";
import { EmptyState } from "../components/EmptyState";
import { CheckCircleIcon, InboxIcon } from "../components/Icons";
import { byNewest, categorize } from "./categories";
import { DisclosureSection } from "./DisclosureSection";

interface InboxPaneProps {
  state: AppState;
  now: number;
  onOpenItem: (id: string) => void;
  onOpenSettings: () => void;
}

export function InboxPane({ state, now, onOpenItem, onOpenSettings }: InboxPaneProps) {
  let content: ReactNode;

  const anyConnected = state.accounts.some((a) => a.connected);
  const items = byNewest(state.items);

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
      .filter((category) => category.items.length > 0)
      .map((category) => (
        <DisclosureSection
          key={category.id}
          id={category.id}
          label={category.label}
          items={category.items}
          // Only the catch-all section starts open.
          defaultCollapsed={category.id !== "recent"}
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
