// Main-window shell: a mail-style three-column view (frosted source list,
// inbox, preview) over the same pushed AppState the popover renders. None of
// the popover's window effects (content-height reporting, visibility reset,
// focus scrubbing) belong here — this is a normal resizable window.

import type { PointerEvent as ReactPointerEvent } from "react";
import type { PaneWidth } from "../hooks/usePaneWidth";
import type { CategoryId } from "../inbox/categories";
import { useEffect, useRef, useState } from "react";
import { useAccent } from "../hooks/useAccent";
import { useAppState } from "../hooks/useAppState";
import { useNow } from "../hooks/useNow";
import { usePaneWidth } from "../hooks/usePaneWidth";
import { byNewest, categorize } from "../inbox/categories";
import { InboxList } from "./InboxList";
import { MainHeader } from "./MainHeader";
import { PreviewPane } from "./PreviewPane";
import { Sidebar } from "./Sidebar";

// Both dividers stop before the preview is squeezed into an unreadable
// column; the window's own minWidth (main-window.ts) leaves room for all
// three minimums at once.
const SIDEBAR = { min: 170, max: 320, default: 200 };
const LIST = { min: 260, max: 560, default: 340 };
const MIN_PREVIEW_WIDTH = 360;

function clamp(value: number, min: number, max: number): number {
  return Math.min(Math.max(value, min), Math.max(min, max));
}

export function MainApp() {
  const { state, actions } = useAppState();
  const now = useNow();
  useAccent(state.accentColor);

  const [categoryId, setCategoryId] = useState<CategoryId>("recent");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const sidebar = usePaneWidth("sidebar", SIDEBAR.default);
  const list = usePaneWidth("list", LIST.default);
  const rootRef = useRef<HTMLDivElement>(null);

  const categories = categorize(byNewest(state.items));
  const category = categories.find((c) => c.id === categoryId) ?? categories[0];
  const items = category.items;
  // Selection is by id, so it survives sync updates; an item that left the
  // inbox (or the current category) falls back to the empty preview.
  const selected = items.find((item) => item.id === selectedId) ?? null;

  // Up/down walk the visible list wherever focus happens to be, and Enter
  // opens the selection — the keyboard contract of every mail-style window.
  // A ref keeps the listener off the re-subscribe treadmill as items change.
  const navRef = useRef({ items, selectedId, openItem: actions.openItem });
  navRef.current = { items, selectedId, openItem: actions.openItem };
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent): void => {
      if (event.metaKey || event.ctrlKey || event.altKey) {
        return;
      }
      const active = document.activeElement;
      // Any focused control other than a row keeps its own key handling.
      if (active instanceof HTMLElement && active.closest("button:not(.row), input, textarea")) {
        return;
      }
      const { items: rows, selectedId: current, openItem } = navRef.current;
      if (rows.length === 0) {
        return;
      }
      const index = rows.findIndex((item) => item.id === current);
      if (event.key === "ArrowDown") {
        event.preventDefault();
        setSelectedId(rows[index < 0 ? 0 : Math.min(rows.length - 1, index + 1)].id);
      } else if (event.key === "ArrowUp") {
        event.preventDefault();
        setSelectedId(rows[index < 0 ? rows.length - 1 : Math.max(0, index - 1)].id);
      } else if (event.key === "Enter" && index >= 0) {
        event.preventDefault();
        openItem(rows[index].id);
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  // Divider drags: pointer capture keeps the events flowing to the divider
  // even when the pointer outruns its 1px track. Each divider caps itself
  // against the other panes so the preview always keeps its minimum.
  const dragRef = useRef<
    { pointerId: number; startX: number; startWidth: number; pane: PaneWidth; max: () => number } | null
  >(null);
  const dividerProps = (
    pane: PaneWidth,
    bounds: { min: number; max: number },
    /** The width of the pane on the far side of the preview. */
    others: () => number,
  ) => {
    const maxWidth = (): number => {
      const total = rootRef.current?.clientWidth;
      if (total === undefined) {
        return bounds.max;
      }
      // Two 1px dividers sit between the three panes.
      return Math.min(bounds.max, total - others() - MIN_PREVIEW_WIDTH - 2);
    };
    const end = (event: ReactPointerEvent<HTMLDivElement>): void => {
      if (dragRef.current?.pointerId === event.pointerId) {
        dragRef.current.pane.commit();
        dragRef.current = null;
      }
    };
    return {
      "className": "pane-divider",
      "role": "separator" as const,
      "aria-orientation": "vertical" as const,
      "onPointerDown": (event: ReactPointerEvent<HTMLDivElement>): void => {
        dragRef.current = {
          pointerId: event.pointerId,
          startX: event.clientX,
          startWidth: pane.width,
          pane,
          max: maxWidth,
        };
        event.currentTarget.setPointerCapture(event.pointerId);
      },
      "onPointerMove": (event: ReactPointerEvent<HTMLDivElement>): void => {
        const drag = dragRef.current;
        if (!drag || drag.pointerId !== event.pointerId) {
          return;
        }
        const next = drag.startWidth + (event.clientX - drag.startX);
        drag.pane.set(clamp(next, bounds.min, drag.max()));
      },
      "onPointerUp": end,
      "onPointerCancel": end,
    };
  };

  // Same fallback as the popover: without the translucent material the page
  // paints its own solid background (full-bleed here — the window is framed).
  const appClass = [`platform-${state.platform}`, !state.glassEnabled && "opaque"]
    .filter(Boolean)
    .join(" ");

  return (
    <div id="main-app" className={appClass} ref={rootRef}>
      <Sidebar
        categories={categories}
        selectedId={category.id}
        width={sidebar.width}
        minWidth={SIDEBAR.min}
        onSelect={setCategoryId}
      />
      <div
        {...dividerProps(sidebar, SIDEBAR, () => list.width)}
        aria-label="Resize sidebar"
      />
      <div className="main-content">
        <MainHeader
          title={category.label}
          subtitle={itemCount(items.length)}
          syncing={state.syncing}
          lastSyncAt={state.lastSyncAt}
          now={now}
          anyUnread={state.items.some((item) => !item.read)}
          onRefresh={actions.refresh}
          onMarkAllRead={actions.markAllRead}
        />
        <div className="main-body">
          <section
            className="list-pane"
            style={{ width: list.width, minWidth: LIST.min }}
            aria-label="Inbox"
          >
            <InboxList
              items={items}
              categoryId={category.id}
              anyConnected={state.accounts.some((account) => account.connected)}
              selectedId={selectedId}
              now={now}
              onSelect={setSelectedId}
            />
          </section>
          <div
            {...dividerProps(list, LIST, () => sidebar.width)}
            aria-label="Resize inbox list"
          />
          <section
            className="preview-pane"
            style={{ minWidth: MIN_PREVIEW_WIDTH }}
            aria-label="Preview"
          >
            <PreviewPane item={selected} now={now} onOpen={actions.openItem} />
          </section>
        </div>
      </div>
    </div>
  );
}

function itemCount(count: number): string {
  return count === 1 ? "1 item" : `${count} items`;
}
