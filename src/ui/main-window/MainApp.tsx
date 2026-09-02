// Main-window shell: a mail-style three-column view (frosted source list,
// inbox, preview) over the same pushed AppState the popover renders. None of
// the popover's window effects (content-height reporting, visibility reset,
// focus scrubbing) belong here — this is a normal resizable window.

import type { PointerEvent as ReactPointerEvent } from "react";
import type { CategoryId } from "../inbox/categories";
import { useRef, useState } from "react";
import { useAccent } from "../hooks/useAccent";
import { useAppState } from "../hooks/useAppState";
import { useNow } from "../hooks/useNow";
import { byNewest, categorize } from "../inbox/categories";
import { InboxList } from "./InboxList";
import { MainHeader } from "./MainHeader";
import { PreviewPane } from "./PreviewPane";
import { Sidebar } from "./Sidebar";

const MIN_LIST_WIDTH = 240;
const MAX_LIST_WIDTH = 520;
const DEFAULT_LIST_WIDTH = 320;

export function MainApp() {
  const { state, actions } = useAppState();
  const now = useNow();
  useAccent(state.accentColor);

  const [categoryId, setCategoryId] = useState<CategoryId>("recent");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [listWidth, setListWidth] = useState(DEFAULT_LIST_WIDTH);
  const dragRef = useRef<{ pointerId: number; startX: number; startWidth: number } | null>(null);

  const categories = categorize(byNewest(state.items));
  const category = categories.find((c) => c.id === categoryId) ?? categories[0];
  const items = category.items;
  // Selection is by id, so it survives sync updates; an item that left the
  // inbox (or the current category) falls back to the empty preview.
  const selected = items.find((item) => item.id === selectedId) ?? null;

  // Divider drag: pointer capture keeps the events flowing to the divider
  // even when the pointer outruns its 1px track.
  const onDividerPointerDown = (event: ReactPointerEvent<HTMLDivElement>): void => {
    dragRef.current = {
      pointerId: event.pointerId,
      startX: event.clientX,
      startWidth: listWidth,
    };
    event.currentTarget.setPointerCapture(event.pointerId);
  };
  const onDividerPointerMove = (event: ReactPointerEvent<HTMLDivElement>): void => {
    const drag = dragRef.current;
    if (!drag || drag.pointerId !== event.pointerId) {
      return;
    }
    const width = drag.startWidth + (event.clientX - drag.startX);
    setListWidth(Math.min(MAX_LIST_WIDTH, Math.max(MIN_LIST_WIDTH, width)));
  };
  const onDividerPointerEnd = (event: ReactPointerEvent<HTMLDivElement>): void => {
    if (dragRef.current?.pointerId === event.pointerId) {
      dragRef.current = null;
    }
  };

  // Same fallback as the popover: without the translucent material the page
  // paints its own solid background (full-bleed here — the window is framed).
  const appClass = [`platform-${state.platform}`, !state.glassEnabled && "opaque"]
    .filter(Boolean)
    .join(" ");

  return (
    <div id="main-app" className={appClass}>
      <Sidebar categories={categories} selectedId={category.id} onSelect={setCategoryId} />
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
          <section className="list-pane" style={{ width: listWidth }} aria-label="Inbox">
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
            className="pane-divider"
            role="separator"
            aria-orientation="vertical"
            aria-label="Resize inbox list"
            onPointerDown={onDividerPointerDown}
            onPointerMove={onDividerPointerMove}
            onPointerUp={onDividerPointerEnd}
            onPointerCancel={onDividerPointerEnd}
          />
          <section className="preview-pane" aria-label="Preview">
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
