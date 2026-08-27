// App shell: owns which pane is visible plus the document-level side effects
// (accent CSS variable, Escape, popover-dismiss reset, focus-ring scrub).
// App state itself lives in useAppState.

import { useEffect, useState } from "react";
import { Banner } from "./components/Banner";
import { Header } from "./components/Header";
import { InboxPane } from "./inbox/InboxPane";
import { SettingsPane } from "./settings/SettingsPane";
import { useAppState } from "./hooks/useAppState";
import { useNow } from "./hooks/useNow";

type Pane = "inbox" | "settings";

export function App() {
  const { state, connecting, actions } = useAppState();
  const [pane, setPane] = useState<Pane>("inbox");
  const now = useNow();

  // Follow the macOS system accent; the stylesheet's per-theme blues are the
  // fallback when the main process couldn't read it. (CSSOM writes are fine
  // under the CSP; only inline <style> is forbidden.)
  useEffect(() => {
    if (state.accentColor) {
      document.documentElement.style.setProperty("--accent", state.accentColor);
    } else {
      document.documentElement.style.removeProperty("--accent");
    }
  }, [state.accentColor]);

  // Escape closes the settings pane.
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent): void => {
      if (event.key === "Escape") {
        setPane((p) => (p === "settings" ? "inbox" : p));
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  // The popover must always reopen on the inbox. The window is never actually
  // hidden (it fades to opacity 0 so macOS can't play its window-show
  // animation), so dismissal arrives as an explicit push from the main
  // process. Resetting on dismiss (rather than on show) avoids any visible
  // pane flash; form input values are left alone — only the pane switches.
  useEffect(
    () =>
      window.majordomo?.onPopoverVisibility((visible) => {
        if (!visible) {
          setPane("inbox");
        }
      }),
    []
  );

  // The main process focuses the window on every popover open, which lands
  // keyboard focus on the first header button and paints a focus ring. Native
  // menus open focus-clean; drop the ring unless focus is in a text field.
  useEffect(() => {
    const onFocus = (): void => {
      const active = document.activeElement;
      if (active instanceof HTMLElement && !(active instanceof HTMLInputElement)) {
        active.blur();
      }
    };
    window.addEventListener("focus", onFocus);
    return () => window.removeEventListener("focus", onFocus);
  }, []);

  const settingsOpen = pane === "settings";

  return (
    <div id="app" className={settingsOpen ? "settings-open" : undefined}>
      <Header
        syncing={state.syncing}
        lastSyncAt={state.lastSyncAt}
        now={now}
        anyUnread={state.items.some((i) => !i.read)}
        settingsOpen={settingsOpen}
        onRefresh={actions.refresh}
        onMarkAllRead={actions.markAllRead}
        onToggleSettings={() => setPane(settingsOpen ? "inbox" : "settings")}
      />
      <Banner accounts={state.accounts} show={pane === "inbox"} />
      <div className="content">
        <InboxPane
          state={state}
          now={now}
          onOpenItem={actions.openItem}
          onOpenSettings={() => setPane("settings")}
        />
        <SettingsPane
          state={state}
          connecting={connecting}
          open={settingsOpen}
          onConnect={actions.connect}
          onDisconnect={actions.disconnect}
          onToggleLaunchAtLogin={actions.setLaunchAtLogin}
        />
      </div>
    </div>
  );
}
