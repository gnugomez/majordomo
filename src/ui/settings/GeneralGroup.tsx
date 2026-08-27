import { Toggle } from "../components/Toggle";

interface GeneralGroupProps {
  launchAtLogin: boolean;
  onToggleLaunchAtLogin: (next: boolean) => void;
}

export function GeneralGroup({ launchAtLogin, onToggleLaunchAtLogin }: GeneralGroupProps) {
  return (
    <section className="settings-group">
      <div className="group-row">
        <span className="settings-label">Launch at login</span>
        <Toggle checked={launchAtLogin} label="Launch at login" onChange={onToggleLaunchAtLogin} />
      </div>
    </section>
  );
}
