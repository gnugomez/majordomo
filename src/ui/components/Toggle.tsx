/** macOS-style switch: accent when on, translucent gray when off. */

interface ToggleProps {
  checked: boolean;
  label: string;
  onChange: (next: boolean) => void;
}

export function Toggle({ checked, label, onChange }: ToggleProps) {
  return (
    <button
      type="button"
      className="toggle"
      role="switch"
      aria-checked={checked}
      aria-label={label}
      onClick={() => onChange(!checked)}
    >
      <span className="toggle-knob" />
    </button>
  );
}
