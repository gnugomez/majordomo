// Bridge subscription plus optimistic action helpers. Every action applies
// its expected result locally first; the main process pushes authoritative
// state that overwrites the guess.

import { useEffect, useRef, useState } from "react";
import type { AccountConfig, AccountState, AppState, ProviderId } from "../../shared/types";
import type { MajordomoApi } from "../../shared/ipc";
import { debugInjector } from "../debug";

// The preload script installs this; guard so a standalone preview of the raw
// HTML degrades to the empty state instead of throwing.
const api: MajordomoApi | undefined = window.majordomo;

const EMPTY_STATE: AppState = {
  items: [],
  accounts: [],
  lastSyncAt: null,
  syncing: false,
  accentColor: null,
  launchAtLogin: false,
  platform: "darwin",
  glassEnabled: true,
};

export interface AppActions {
  refresh(): void;
  markAllRead(): void;
  openItem(id: string): void;
  connect(provider: ProviderId, config: AccountConfig): void;
  disconnect(provider: ProviderId): void;
  setLaunchAtLogin(next: boolean): void;
  setGlassEnabled(next: boolean): void;
}

export interface AppStateHook {
  state: AppState;
  connecting: Record<ProviderId, boolean>;
  actions: AppActions;
}

export function useAppState(): AppStateHook {
  const [state, setState] = useState<AppState>(EMPTY_STATE);
  const [connecting, setConnecting] = useState<Record<ProviderId, boolean>>({
    github: false,
    gitlab: false,
  });
  // Re-entrancy guard for connect(); state updates are async, a ref is not.
  const inFlight = useRef<Record<ProviderId, boolean>>({ github: false, gitlab: false });

  useEffect(() => {
    debugInjector.current = setState;
    if (!api) {
      console.error("window.majordomo is not available; rendering empty state");
      return () => {
        debugInjector.current = null;
      };
    }
    // Subscribe first so a push racing the initial getState() can't be lost;
    // if a push lands before getState() resolves, the push wins.
    let receivedPush = false;
    let cancelled = false;
    const unsubscribe = api.onStateUpdated((next) => {
      receivedPush = true;
      setState(next);
    });
    api
      .getState()
      .then((initial) => {
        if (!receivedPush && !cancelled) {
          setState(initial);
        }
      })
      .catch((err: unknown) => console.error("getState failed", err));
    return () => {
      cancelled = true;
      unsubscribe();
      debugInjector.current = null;
    };
  }, []);

  const mergeAccount = (next: AccountState): void => {
    setState((s) => ({
      ...s,
      accounts: [...s.accounts.filter((a) => a.provider !== next.provider), next],
    }));
  };

  const actions: AppActions = {
    refresh() {
      // Show the spinner immediately; the pushed state is authoritative.
      setState((s) => (s.syncing ? s : { ...s, syncing: true }));
      void api?.refresh();
    },
    markAllRead() {
      setState((s) => ({
        ...s,
        items: s.items.map((i) => (i.read ? i : { ...i, read: true })),
      }));
      void api?.markAllRead();
    },
    openItem(id) {
      // Optimistically mark read; the main process does the same and pushes.
      setState((s) => ({
        ...s,
        items: s.items.map((i) => (i.id === id && !i.read ? { ...i, read: true } : i)),
      }));
      void api?.openItem(id);
    },
    connect(provider, config) {
      if (!api || inFlight.current[provider]) {
        return;
      }
      inFlight.current[provider] = true;
      setConnecting((c) => ({ ...c, [provider]: true }));
      api
        .connectAccount(provider, config)
        .then(mergeAccount)
        .catch((err: unknown) => {
          mergeAccount({
            provider,
            connected: false,
            error: err instanceof Error ? err.message : String(err),
          });
        })
        .finally(() => {
          inFlight.current[provider] = false;
          setConnecting((c) => ({ ...c, [provider]: false }));
        });
    },
    disconnect(provider) {
      // Optimistic; the pushed state is authoritative.
      mergeAccount({ provider, connected: false });
      api?.disconnectAccount(provider).catch(() => {
        // A state push will correct us if the disconnect didn't take.
      });
    },
    setLaunchAtLogin(next) {
      // Optimistic flip; the pushed state is authoritative.
      setState((s) => ({ ...s, launchAtLogin: next }));
      void api?.setLaunchAtLogin(next);
    },
    setGlassEnabled(next) {
      // Optimistic flip; the pushed state is authoritative.
      setState((s) => ({ ...s, glassEnabled: next }));
      void api?.setGlassEnabled(next);
    },
  };

  return { state, connecting, actions };
}
