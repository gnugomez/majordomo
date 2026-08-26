// Settings pane, styled as native grouped lists (the System Settings
// "Known Networks" pattern): a caption above a single rounded container per
// section, hairline-separated rows inside. Each provider is one row; its
// connect form expands inline beneath the row as extra rows in the same
// container. All rows and inputs are built exactly once so re-renders never
// clobber what the user is typing; update() only touches text, visibility,
// and disabled flags.

import type { AccountConfig, AccountState, AppState, ProviderId } from "../shared/types";
import { ICONS, providerIcon } from "./icons";
import { el } from "./views";

export interface SettingsHandlers {
  onConnect(provider: ProviderId, config: AccountConfig): void;
  onDisconnect(provider: ProviderId): void;
  onToggleLaunchAtLogin(next: boolean): void;
}

interface ProviderDef {
  id: ProviderId;
  name: string;
  needsBaseUrl: boolean;
}

const PROVIDERS: ProviderDef[] = [
  { id: "github", name: "GitHub", needsBaseUrl: false },
  { id: "gitlab", name: "GitLab", needsBaseUrl: true },
];

interface Card {
  provider: ProviderId;
  name: string;
  /** Local UI state: whether the inline connect form is open. */
  expanded: boolean;
  sub: HTMLElement;
  connectedSide: HTMLElement;
  userEl: HTMLElement;
  statusDot: HTMLElement;
  expandBtn: HTMLButtonElement;
  /** The form's rows plus the warning row live inside the group container. */
  formRows: HTMLElement[];
  urlInput: HTMLInputElement | null;
  tokenInput: HTMLInputElement;
  connectBtn: HTMLButtonElement;
  errorEl: HTMLElement;
  warnRow: HTMLElement;
}

function textInput(type: string, placeholder: string, label: string): HTMLInputElement {
  const input = el("input");
  input.type = type;
  input.placeholder = placeholder;
  input.autocomplete = "off";
  input.spellcheck = false;
  input.setAttribute("autocapitalize", "off");
  input.setAttribute("autocorrect", "off");
  input.setAttribute("aria-label", label);
  return input;
}

function safeHost(baseUrl: string): string {
  try {
    return new URL(baseUrl).host;
  } catch {
    return "";
  }
}

export class SettingsPane {
  readonly root: HTMLElement;

  private readonly cards: Card[] = [];
  private readonly localError: Partial<Record<ProviderId, string>> = {};
  private readonly launchToggle: HTMLButtonElement;
  private lastState: AppState | null = null;
  private lastConnecting: Record<ProviderId, boolean> = { github: false, gitlab: false };

  constructor(private readonly handlers: SettingsHandlers) {
    this.root = el("section", "pane");
    this.root.id = "settings";
    this.root.setAttribute("aria-hidden", "true");

    this.root.append(el("h3", "settings-caption", "Accounts"));
    const accounts = el("section", "settings-group has-glyphs");
    for (const def of PROVIDERS) {
      this.cards.push(this.buildProvider(def, accounts));
    }
    this.root.append(accounts);

    this.root.append(el("h3", "settings-caption", "General"));
    const general = el("section", "settings-group");
    const row = el("div", "group-row");
    row.append(el("span", "settings-label", "Launch at login"));
    this.launchToggle = el("button", "toggle");
    this.launchToggle.type = "button";
    this.launchToggle.setAttribute("role", "switch");
    this.launchToggle.setAttribute("aria-checked", "false");
    this.launchToggle.setAttribute("aria-label", "Launch at login");
    this.launchToggle.append(el("span", "toggle-knob"));
    this.launchToggle.addEventListener("click", () => {
      const next = this.launchToggle.getAttribute("aria-checked") !== "true";
      handlers.onToggleLaunchAtLogin(next);
    });
    row.append(this.launchToggle);
    general.append(row);
    this.root.append(general);
  }

  /** Reflect app + in-flight state onto the pane without rebuilding inputs. */
  update(state: AppState, connecting: Record<ProviderId, boolean>): void {
    this.lastState = state;
    this.lastConnecting = connecting;
    this.refresh();
  }

  /** Called after a successful connect so the secret doesn't linger in the DOM. */
  clearToken(provider: ProviderId): void {
    const card = this.cards.find((c) => c.provider === provider);
    if (card) {
      card.tokenInput.value = "";
    }
  }

  private refresh(): void {
    const state = this.lastState;
    if (!state) {
      return;
    }
    this.launchToggle.setAttribute("aria-checked", state.launchAtLogin ? "true" : "false");
    for (const card of this.cards) {
      const account: AccountState = state.accounts.find(
        (a) => a.provider === card.provider
      ) ?? { provider: card.provider, connected: false };
      this.updateCard(card, account, this.lastConnecting[card.provider]);
    }
  }

  private updateCard(card: Card, account: AccountState, busy: boolean): void {
    if (account.connected) {
      // Collapse the inline form once a connect lands.
      card.expanded = false;
      delete this.localError[card.provider];
    }

    const showForm = !account.connected && card.expanded;
    for (const row of card.formRows) {
      row.hidden = !showForm;
    }
    card.connectedSide.hidden = !account.connected;
    card.expandBtn.hidden = account.connected;

    if (account.connected) {
      card.userEl.textContent = `@${account.username ?? "unknown"}`;
      const host =
        card.provider === "gitlab" && account.baseUrl ? safeHost(account.baseUrl) : "";
      card.sub.textContent = host;
      card.sub.hidden = !host;
      const warn = Boolean(account.error);
      card.statusDot.className = warn ? "status-dot warn" : "status-dot ok";
      card.statusDot.title = warn ? "Sync error" : "Connected";
      card.warnRow.hidden = !warn;
      if (account.error) {
        card.warnRow.innerHTML = ICONS.warning;
        card.warnRow.append(el("span", "", account.error));
      }
    } else {
      card.sub.hidden = true;
      card.warnRow.hidden = true;
      card.expandBtn.disabled = busy;
      card.expandBtn.textContent = card.expanded ? "Cancel" : "Connect…";
      card.expandBtn.setAttribute("aria-expanded", card.expanded ? "true" : "false");
      card.expandBtn.setAttribute(
        "aria-label",
        card.expanded ? `Cancel connecting ${card.name}` : `Connect ${card.name}`
      );
      card.errorEl.textContent = busy
        ? ""
        : this.localError[card.provider] ?? account.error ?? "";
      card.tokenInput.disabled = busy;
      if (card.urlInput) {
        card.urlInput.disabled = busy;
      }
      card.connectBtn.disabled = busy;
      card.connectBtn.textContent = busy ? "Validating…" : "Connect";
    }
  }

  private buildProvider(def: ProviderDef, group: HTMLElement): Card {
    // Provider row: glyph + name left; connection status / actions right.
    const row = el("div", "group-row provider-row");
    const mark = el("span", "provider-mark");
    mark.innerHTML = providerIcon(def.id);
    const label = el("span", "provider-label");
    const sub = el("span", "provider-sub");
    sub.hidden = true;
    label.append(el("span", "provider-name", def.name), sub);

    const connectedSide = el("span", "connected-side");
    connectedSide.hidden = true;
    const userEl = el("span", "acct-user");
    const statusDot = el("span", "status-dot ok");
    const disconnectBtn = el("button", "row-btn", "Disconnect");
    disconnectBtn.type = "button";
    disconnectBtn.setAttribute("aria-label", `Disconnect ${def.name}`);
    disconnectBtn.addEventListener("click", () => this.handlers.onDisconnect(def.id));
    connectedSide.append(userEl, statusDot, disconnectBtn);

    const expandBtn = el("button", "row-btn", "Connect…");
    expandBtn.type = "button";
    expandBtn.setAttribute("aria-expanded", "false");
    expandBtn.setAttribute("aria-label", `Connect ${def.name}`);

    row.append(mark, label, connectedSide, expandBtn);

    // Inline connect form: display:contents, so its rows sit in the group
    // container and pick up the same inset hairlines.
    const form = el("form", "connect-form");
    form.noValidate = true;
    const formRows: HTMLElement[] = [];
    let urlInput: HTMLInputElement | null = null;
    if (def.needsBaseUrl) {
      urlInput = textInput("text", "https://gitlab.example.com", `${def.name} base URL`);
      const urlRow = el("div", "group-row field-row");
      urlRow.append(urlInput);
      formRows.push(urlRow);
      form.append(urlRow);
    }
    const tokenInput = textInput(
      "password",
      "Personal access token",
      `${def.name} personal access token`
    );
    const tokenRow = el("div", "group-row field-row");
    tokenRow.append(tokenInput);
    const actionRow = el("div", "group-row action-row");
    const connectBtn = el("button", "primary-btn", "Connect");
    connectBtn.type = "submit";
    actionRow.append(connectBtn);
    const errorEl = el("div", "group-row error-row");
    errorEl.setAttribute("role", "alert");
    formRows.push(tokenRow, actionRow, errorEl);
    form.append(tokenRow, actionRow, errorEl);
    for (const r of formRows) {
      r.hidden = true;
    }

    const warnRow = el("div", "group-row warn-row");
    warnRow.hidden = true;

    group.append(row, form, warnRow);

    const card: Card = {
      provider: def.id,
      name: def.name,
      expanded: false,
      sub,
      connectedSide,
      userEl,
      statusDot,
      expandBtn,
      formRows,
      urlInput,
      tokenInput,
      connectBtn,
      errorEl,
      warnRow,
    };

    expandBtn.addEventListener("click", () => {
      if (this.lastConnecting[def.id]) {
        return;
      }
      card.expanded = !card.expanded;
      if (card.expanded) {
        // Only one form open at a time; the collapsed form keeps its typed
        // values (rows are built once and never clobbered).
        for (const other of this.cards) {
          if (other !== card) {
            other.expanded = false;
          }
        }
      }
      this.refresh();
      if (card.expanded) {
        (urlInput ?? tokenInput).focus();
      }
    });

    form.addEventListener("submit", (event) => {
      event.preventDefault();
      const token = tokenInput.value.trim();
      let baseUrl: string | undefined;
      if (urlInput) {
        baseUrl = urlInput.value.trim().replace(/\/+$/, "");
        if (!this.validBaseUrl(baseUrl)) {
          this.showLocalError(
            def.id,
            errorEl,
            "Enter your GitLab instance URL, e.g. https://gitlab.example.com"
          );
          return;
        }
      }
      if (!token) {
        this.showLocalError(def.id, errorEl, "Enter a personal access token.");
        return;
      }
      delete this.localError[def.id];
      errorEl.textContent = "";
      this.handlers.onConnect(def.id, baseUrl !== undefined ? { token, baseUrl } : { token });
    });

    return card;
  }

  private validBaseUrl(value: string): boolean {
    if (!value) {
      return false;
    }
    try {
      const url = new URL(value);
      return url.protocol === "http:" || url.protocol === "https:";
    } catch {
      return false;
    }
  }

  private showLocalError(provider: ProviderId, errorEl: HTMLElement, message: string): void {
    this.localError[provider] = message;
    errorEl.textContent = message;
  }
}
