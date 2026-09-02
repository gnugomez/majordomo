// App shell: owns which pane is visible plus the document-level side effects
// (accent CSS variable, Escape, popover-dismiss reset, focus-ring scrub).
// App state itself lives in useAppState.

import { useEffect, useRef, useState } from "react";
import { Banner } from "./components/Banner";
import { Header } from "./components/Header";
import { useAccent } from "./hooks/useAccent";
import { useAppState } from "./hooks/useAppState";
import { useNow } from "./hooks/useNow";
import { InboxPane } from "./inbox/InboxPane";
import { SettingsPane } from "./settings/SettingsPane";

type Pane = "inbox" | "settings";

export function App() {
  const { state, connecting, actions } = useAppState();
  const [pane, setPane] = useState<Pane>("inbox");
  const now = useNow();

  useAccent(state.accentColor);

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

  // The popover must always reopen on the inbox. Dismissal arrives as an
  // explicit push from the main process; resetting on dismiss (rather than
  // on show) means the pane switches while the window is hidden, so it is
  // never seen. Form input values are left alone — only the pane switches.
  useEffect(
    () =>
      window.majordomo?.onPopoverVisibility((visible) => {
        if (!visible) {
          setPane("inbox");
        }
      }),
    [],
  );

  // The main process focuses the window on every popover open, which can land
  // keyboard focus on the first header button and paint a focus ring. Native
  // menus open focus-clean; drop the ring unless focus is in a text field.
  // Chromium sometimes (re)assigns focus just after the window-focus event
  // and again around show, so scrub on both signals plus a following tick.
  useEffect(() => {
    const scrub = (): void => {
      const active = document.activeElement;
      if (active instanceof HTMLElement && !(active instanceof HTMLInputElement)) {
        active.blur();
      }
    };
    let scrubTimer = 0;
    const scrubNowAndNext = (): void => {
      scrub();
      window.clearTimeout(scrubTimer);
      scrubTimer = window.setTimeout(scrub, 0);
    };
    window.addEventListener("focus", scrubNowAndNext);
    const unsubscribe = window.majordomo?.onPopoverVisibility((visible) => {
      if (visible)
        scrubNowAndNext();
    });
    return () => {
      window.clearTimeout(scrubTimer);
      window.removeEventListener("focus", scrubNowAndNext);
      unsubscribe?.();
    };
  }, []);

  const settingsOpen = pane === "settings";

  // Without the translucent material the page paints its own solid, rounded
  // panel (the window itself stays transparent).
  const appClass
    = [
      `platform-${state.platform}`,
      settingsOpen && "settings-open",
      !state.glassEnabled && "opaque",
    ]
      .filter(Boolean)
      .join(" ") || undefined;

  // Report the content height so the window can hug it, the way native menu
  // extras resize with their content. Runs after every App render AND on any
  // pane-child resize (section collapse is DisclosureSection-local state that
  // never re-renders App — the section element shrinking is the only signal).
  // Empty states stretch to fill (flex: 1), so they get a fixed height.
  const lastSentHeightRef = useRef(0);
  const measure = () => {
    const header = document.querySelector<HTMLElement>("#app .header");
    const banner = document.querySelector<HTMLElement>("#app #banner");
    const open = document.querySelector("#app.settings-open") !== null;
    const paneEl = document.querySelector<HTMLElement>(open ? "#settings" : "#inbox");
    if (!header || !paneEl)
      return;
    let content: number;
    if (paneEl.querySelector(".empty")) {
      content = 380;
    } else {
      let bottom = 0;
      for (const child of Array.from(paneEl.children) as HTMLElement[]) {
        bottom = Math.max(bottom, child.offsetTop + child.offsetHeight);
      }
      content = bottom + Number.parseFloat(getComputedStyle(paneEl).paddingBottom || "0");
    }
    const desired = Math.ceil(header.offsetHeight + (banner?.offsetHeight ?? 0) + content);
    if (desired !== lastSentHeightRef.current) {
      lastSentHeightRef.current = desired;
      void window.majordomo?.setPopoverHeight(desired);
    }
  };
  useEffect(measure);
  useEffect(() => {
    const panes = ["#inbox", "#settings"]
      .map((sel) => document.querySelector<HTMLElement>(sel))
      .filter((el): el is HTMLElement => el !== null);
    const resizes = new ResizeObserver(measure);
    const watchChildren = () => {
      resizes.disconnect();
      for (const pane of panes) {
        for (const child of Array.from(pane.children)) resizes.observe(child);
      }
    };
    const mutations = new MutationObserver(() => {
      watchChildren();
      measure();
    });
    for (const pane of panes) mutations.observe(pane, { childList: true });
    watchChildren();
    return () => {
      resizes.disconnect();
      mutations.disconnect();
    };
  }, []);

  return (
    <div id="app" className={appClass}>
      <Header
        syncing={state.syncing}
        lastSyncAt={state.lastSyncAt}
        now={now}
        anyUnread={state.items.some((i) => !i.read)}
        settingsOpen={settingsOpen}
        onRefresh={actions.refresh}
        onMarkAllRead={actions.markAllRead}
        onToggleSettings={() => setPane(settingsOpen ? "inbox" : "settings")}
        onOpenMainWindow={() => void window.majordomo?.openMainWindow()}
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
          onToggleGlassEnabled={actions.setGlassEnabled}
        />
      </div>
    </div>
  );
}
