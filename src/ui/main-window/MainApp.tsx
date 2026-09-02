// Main-window shell: a mail-style split view (inbox list, draggable divider,
// preview) over the same pushed AppState the popover renders. None of the
// popover's window effects (content-height reporting, visibility reset,
// focus scrubbing) belong here — this is a normal resizable window.

import type { PointerEvent as ReactPointerEvent } from "react";
import type { InboxItem } from "../../shared/types";
import { useRef, useState } from "react";
import { useAccent } from "../hooks/useAccent";
import { useAppState } from "../hooks/useAppState";
import { useNow } from "../hooks/useNow";
import { InboxList } from "./InboxList";
import { MainHeader } from "./MainHeader";
import { PreviewPane } from "./PreviewPane";

const MIN_LIST_WIDTH = 240;
const MAX_LIST_WIDTH = 520;
const DEFAULT_LIST_WIDTH = 320;

function itemTime(iso: string): number {
  const t = Date.parse(iso);
  return Number.isNaN(t) ? 0 : t;
}

export function MainApp() {
  const { state, actions } = useAppState();
  const now = useNow();
  useAccent(state.accentColor);

  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [listWidth, setListWidth] = useState(DEFAULT_LIST_WIDTH);
  const dragRef = useRef<{ pointerId: number; startX: number; startWidth: number } | null>(null);

  const items: InboxItem[] = [...state.items].sort(
    (a, b) => itemTime(b.updatedAt) - itemTime(a.updatedAt),
  );
  // Selection is by id, so it survives sync updates; an item that left the
  // inbox simply falls back to the empty preview.
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
      <MainHeader
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
  );
}
