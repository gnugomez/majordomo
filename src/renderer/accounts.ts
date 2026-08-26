// Accounts pane: one card per provider. The cards (including their inputs)
// are built exactly once so re-renders never clobber what the user is typing;
// update() only touches status text, visibility, and disabled flags.

import type { AccountConfig, AccountState, AppState, ProviderId } from "../shared/types";
import { ICONS, providerIcon } from "./icons";
import { el } from "./views";

export interface AccountsHandlers {
  onConnect(provider: ProviderId, config: AccountConfig): void;
  onDisconnect(provider: ProviderId): void;
  onClose(): void;
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
  statusDot: HTMLElement;
  statusText: HTMLElement;
  form: HTMLFormElement;
  urlInput: HTMLInputElement | null;
  tokenInput: HTMLInputElement;
  connectBtn: HTMLButtonElement;
  errorEl: HTMLElement;
  connectedRow: HTMLElement;
  connectedAs: HTMLElement;
  disconnectBtn: HTMLButtonElement;
  warnEl: HTMLElement;
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

export class AccountsPane {
  readonly root: HTMLElement;

  private readonly cards: Card[] = [];
  private readonly localError: Partial<Record<ProviderId, string>> = {};

  constructor(private readonly handlers: AccountsHandlers) {
    this.root = el("section", "pane");
    this.root.id = "accounts";
    this.root.setAttribute("aria-hidden", "true");

    const head = el("div", "pane-head");
    head.append(el("h2", "pane-title", "Accounts"));
    const done = el("button", "text-btn", "Done");
    done.type = "button";
    done.addEventListener("click", () => handlers.onClose());
    head.append(done);
    this.root.append(head);

    for (const def of PROVIDERS) {
      const card = this.buildCard(def);
      this.cards.push(card);
    }
  }

  /** Reflect app + in-flight state onto the cards without rebuilding inputs. */
  update(state: AppState, connecting: Record<ProviderId, boolean>): void {
    for (const card of this.cards) {
      const account: AccountState = state.accounts.find(
        (a) => a.provider === card.provider
      ) ?? { provider: card.provider, connected: false };
      const busy = connecting[card.provider];

      card.form.hidden = account.connected;
      card.connectedRow.hidden = !account.connected;

      if (account.connected) {
        delete this.localError[card.provider];
        card.connectedAs.replaceChildren(
          "Connected as ",
          el("strong", "", `@${account.username ?? "unknown"}`)
        );
        if (card.provider === "gitlab" && account.baseUrl) {
          const host = safeHost(account.baseUrl);
          if (host) {
            card.connectedAs.append(el("span", "connected-host", ` on ${host}`));
          }
        }
        card.statusText.textContent = account.error ? "Sync error" : "Connected";
        card.statusDot.className = account.error ? "status-dot warn" : "status-dot ok";
        card.warnEl.hidden = !account.error;
        if (account.error) {
          card.warnEl.innerHTML = ICONS.warning;
          card.warnEl.append(el("span", "", account.error));
        }
      } else {
        card.statusText.textContent = busy ? "Validating…" : "Not connected";
        card.statusDot.className = "status-dot";
        card.warnEl.hidden = true;
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
  }

  /** Called after a successful connect so the secret doesn't linger in the DOM. */
  clearToken(provider: ProviderId): void {
    const card = this.cards.find((c) => c.provider === provider);
    if (card) {
      card.tokenInput.value = "";
    }
  }

  private buildCard(def: ProviderDef): Card {
    const card = el("section", "card");

    const head = el("div", "card-head");
    const mark = el("span", "provider-mark");
    mark.innerHTML = providerIcon(def.id);
    const status = el("span", "card-status");
    const statusDot = el("span", "status-dot");
    const statusText = el("span", "", "Not connected");
    status.append(statusDot, statusText);
    head.append(mark, el("span", "card-name", def.name), status);

    const form = el("form", "connect-form");
    form.noValidate = true;
    let urlInput: HTMLInputElement | null = null;
    if (def.needsBaseUrl) {
      urlInput = textInput("text", "https://gitlab.example.com", `${def.name} base URL`);
      form.append(urlInput);
    }
    const tokenInput = textInput(
      "password",
      "Personal access token",
      `${def.name} personal access token`
    );
    const formRow = el("div", "form-row");
    const connectBtn = el("button", "primary-btn", "Connect");
    connectBtn.type = "submit";
    formRow.append(connectBtn);
    const errorEl = el("div", "form-error");
    errorEl.setAttribute("role", "alert");
    form.append(tokenInput, formRow, errorEl);

    const connectedRow = el("div", "connected-row");
    connectedRow.hidden = true;
    const connectedAs = el("span", "connected-as");
    const disconnectBtn = el("button", "secondary-btn", "Disconnect");
    disconnectBtn.type = "button";
    disconnectBtn.addEventListener("click", () => this.handlers.onDisconnect(def.id));
    connectedRow.append(connectedAs, disconnectBtn);

    const warnEl = el("div", "card-warning");
    warnEl.hidden = true;

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

    card.append(head, form, connectedRow, warnEl);
    this.root.append(card);

    return {
      provider: def.id,
      statusDot,
      statusText,
      form,
      urlInput,
      tokenInput,
      connectBtn,
      errorEl,
      connectedRow,
      connectedAs,
      disconnectBtn,
      warnEl,
    };
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
