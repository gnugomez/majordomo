import type { ReactNode } from "react";

interface EmptyStateProps {
  icon: ReactNode;
  title: string;
  caption: string;
  action?: { label: string; onClick: () => void };
}

export function EmptyState({ icon, title, caption, action }: EmptyStateProps) {
  return (
    <div className="empty">
      {icon}
      <div className="empty-title">{title}</div>
      <div className="empty-caption">{caption}</div>
      {action && (
        <button type="button" className="primary-btn" onClick={action.onClick}>
          {action.label}
        </button>
      )}
    </div>
  );
}
