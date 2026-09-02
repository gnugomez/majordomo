// The popover's settings pane: the shared settings content in the sliding
// overlay the popover animates in over the inbox.

import type { SettingsContentProps } from "./SettingsContent";
import { SettingsContent } from "./SettingsContent";

interface SettingsPaneProps extends SettingsContentProps {
  open: boolean;
}

export function SettingsPane({ open, ...content }: SettingsPaneProps) {
  return (
    <section className="pane" id="settings" aria-hidden={!open}>
      <SettingsContent {...content} />
    </section>
  );
}
