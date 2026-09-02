// Left column of the main window: a macOS source list of the inbox
// categories. It is the one surface that stays frosted — no background of its
// own, so the window's glass material shows through, the way native sidebars
// do. The top spacer keeps the first source clear of the traffic lights.

import type { ReactNode } from "react";
import type { Category, CategoryId } from "../inbox/categories";
import {
  GitPullRequestIcon,
  InboxIcon,
  IssueOpenedIcon,
  MentionIcon,
  ReviewIcon,
} from "../components/Icons";

const CATEGORY_ICONS: Record<CategoryId, ReactNode> = {
  recent: <InboxIcon />,
  mentions: <MentionIcon />,
  reviews: <ReviewIcon />,
  issues: <IssueOpenedIcon />,
  pulls: <GitPullRequestIcon />,
};

interface SidebarProps {
  categories: Category[];
  selectedId: CategoryId;
  onSelect: (id: CategoryId) => void;
}

export function Sidebar({ categories, selectedId, onSelect }: SidebarProps) {
  return (
    <nav className="sidebar" aria-label="Categories">
      <div className="sidebar-top" />
      <ul className="side-rows">
        {categories.map((category) => {
          const unread = category.items.filter((item) => !item.read).length;
          return (
            <li key={category.id}>
              <button
                type="button"
                className={category.id === selectedId ? "side-row selected" : "side-row"}
                aria-current={category.id === selectedId ? "true" : undefined}
                onClick={() => onSelect(category.id)}
              >
                <span className="side-icon">{CATEGORY_ICONS[category.id]}</span>
                <span className="side-label">{category.label}</span>
                {/* Like a native source list, the trailing number counts what
                    still needs attention — nothing at all when it's zero. */}
                {unread > 0 && <span className="side-count">{unread}</span>}
              </button>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
