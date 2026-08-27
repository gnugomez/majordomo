import type { ReactNode } from "react";

interface IconButtonProps {
  icon: ReactNode;
  label: string;
  onClick: () => void;
  disabled?: boolean;
  active?: boolean;
}

export function IconButton({ icon, label, onClick, disabled, active }: IconButtonProps) {
  return (
    <button
      type="button"
      className={active ? "icon-btn active" : "icon-btn"}
      title={label}
      aria-label={label}
      disabled={disabled}
      onClick={onClick}
    >
      {icon}
    </button>
  );
}
