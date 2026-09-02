import type { AppState } from "../../shared/types";
import { Toggle } from "../components/Toggle";

interface GeneralGroupProps {
  platform: AppState["platform"];
  launchAtLogin: boolean;
  glassEnabled: boolean;
  onToggleLaunchAtLogin: (next: boolean) => void;
  onToggleGlassEnabled: (next: boolean) => void;
}

export function GeneralGroup({
  platform,
  launchAtLogin,
  glassEnabled,
  onToggleLaunchAtLogin,
  onToggleGlassEnabled,
}: GeneralGroupProps) {
  return (
    <section className="settings-group">
      {/* Login items aren't supported on Linux; hide the row entirely. */}
      {platform !== "linux" && (
        <div className="group-row">
          <span className="settings-label">Launch at login</span>
          <Toggle
            checked={launchAtLogin}
            label="Launch at login"
            onChange={onToggleLaunchAtLogin}
          />
        </div>
      )}
      {/* macOS always has a material to draw, so there is nothing to turn
          off; elsewhere the blur may not be available and this is the escape
          hatch (see glassConfigurable() in electron/window.ts). */}
      {platform !== "darwin" && (
        <div className="group-row">
          <span className="settings-label">Translucent background</span>
          <Toggle
            checked={glassEnabled}
            label="Translucent background"
            onChange={onToggleGlassEnabled}
          />
        </div>
      )}
    </section>
  );
}
