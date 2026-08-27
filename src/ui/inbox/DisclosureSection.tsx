// Collapsible section: a full-row disclosure header (caption, muted count,
// chevron) over the item rows. Collapsed sections render the header only.

import type { InboxItem } from "../../shared/types";
import { ChevronIcon } from "../components/Icons";
import { useCollapse } from "../hooks/useCollapse";
import { ItemRow } from "./ItemRow";

interface DisclosureSectionProps {
  /** Stable id, also the localStorage key suffix (e.g. "collapse:overview"). */
  id: string;
  label: string;
  items: InboxItem[];
  defaultCollapsed: boolean;
  now: number;
  onOpenItem: (id: string) => void;
}

export function DisclosureSection({
  id,
  label,
  items,
  defaultCollapsed,
  now,
  onOpenItem,
}: DisclosureSectionProps) {
  const [collapsed, toggle] = useCollapse(id, defaultCollapsed);
  return (
    <section className="section">
      <button
        type="button"
        className="section-header"
        aria-expanded={!collapsed}
        aria-controls={`rows-${id}`}
        onClick={toggle}
      >
        <span className="section-label">{label}</span>
        <span className="section-count">{items.length}</span>
        <span className="disclosure-chevron">
          <ChevronIcon />
        </span>
      </button>
      {!collapsed && (
        <div className="rows" id={`rows-${id}`}>
          {items.map((item) => (
            <ItemRow key={item.id} item={item} now={now} onOpen={onOpenItem} />
          ))}
        </div>
      )}
    </section>
  );
}
