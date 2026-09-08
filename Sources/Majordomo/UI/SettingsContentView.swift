// The settings pages, split Mail-style into the categories the tabbed
// settings window shows: Accounts (the account list with its add/remove
// pair), General, Inboxes, and Notifications.

import AppKit
import SwiftUI

/// The rounded card every settings group sits in.
extension View {
  func settingsCard() -> some View {
    background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
  }
}

/// One labeled row inside a settings card: label left, control right, with
/// an optional leading glyph.
struct SettingsRow<Control: View>: View {
  var symbol: String?
  let label: String
  @ViewBuilder var control: Control

  var body: some View {
    HStack(spacing: 8) {
      if let symbol {
        Image(systemName: symbol)
          .frame(width: 18)
          .foregroundStyle(.secondary)
      }
      Text(label)
        .font(.system(size: 13))
      Spacer()
      control
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }
}

/// The explanatory caption under a settings card.
struct SettingsHint: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.system(size: 11))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 4)
  }
}

struct AccountsSettingsView: View {
  let model: AppModel

  @State private var selection: AccountId?
  @State private var addSheetShown = false
  @State private var confirmRemove = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      List(selection: $selection) {
        ForEach(model.accounts) { account in
          HStack(spacing: 10) {
            AccountAvatar(account: account, size: 26)
            VStack(alignment: .leading, spacing: 1) {
              Text(account.name ?? "@\(account.username ?? "unknown")")
                .font(.system(size: 13, weight: .medium))
              Text(subtitle(account))
                .font(.system(size: 11))
                .foregroundStyle(account.error == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                .lineLimit(1)
            }
            Spacer()
            Circle()
              .fill(account.error == nil ? Color.green : Color.orange)
              .frame(width: 7, height: 7)
              .help(account.error == nil ? "Connected" : "Sync error")
          }
          .padding(.vertical, 2)
          .tag(account.id)
        }
      }
      .listStyle(.bordered)
      .frame(height: 168)
      .overlay {
        if model.accounts.isEmpty {
          Text("No accounts connected")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
      }

      // Mail's +/− pair: add opens the wizard sheet (any number of accounts
      // per provider), remove disconnects the selected account.
      ControlGroup {
        Button {
          addSheetShown = true
        } label: {
          Image(systemName: "plus")
        }
        .help("Add an account")
        Button {
          confirmRemove = true
        } label: {
          Image(systemName: "minus")
        }
        .disabled(selection == nil || !model.accounts.contains { $0.id == selection })
        .help("Remove the selected account")
      }
      .controlSize(.small)
      .fixedSize()
    }
    .padding(16)
    .sheet(isPresented: $addSheetShown) {
      AddAccountSheet(model: model)
    }
    .confirmationDialog(
      "Remove this account?",
      isPresented: $confirmRemove
    ) {
      Button("Remove", role: .destructive) {
        if let selection {
          model.disconnect(selection)
          self.selection = nil
        }
      }
    } message: {
      Text("Its items leave the inbox and the token is forgotten.")
    }
  }

  private func subtitle(_ account: AccountState) -> String {
    if let error = account.error {
      return error
    }
    var parts = [account.provider.displayName]
    if let username = account.username {
      parts.append("@\(username)")
    }
    if let baseUrl = account.baseUrl, let host = URL(string: baseUrl)?.host() {
      parts.append(host)
    }
    return parts.joined(separator: " · ")
  }
}

struct InboxesSettingsView: View {
  let model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      VStack(spacing: 0) {
        // The aggregated bucket list — every provider's categories merged.
        ForEach(Array(aggregatedCategories.enumerated()), id: \.element.id) { index, category in
          if index > 0 {
            Divider().padding(.leading, 40)
          }
          SettingsRow(symbol: category.symbol, label: category.label) {
            Toggle(
              category.label,
              isOn: Binding(
                get: { !model.hiddenCategories.contains(category.id) },
                set: { model.setCategoryHidden(category.id, !$0) }
              )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .disabled(category.id == recentCategory.id)
          }
        }
      }
      .settingsCard()
      SettingsHint(text: "Hidden inboxes leave the sidebar — in All Inboxes and in every account section. Recent is the catch-all and always stays.")
    }
    .padding(16)
  }
}

/// The classic macOS alert tones, all present in /System/Library/Sounds.
private let alertTones = [
  "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero",
  "Morse", "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink",
]

struct NotificationsSettingsView: View {
  let model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      VStack(spacing: 0) {
        SettingsRow(label: "Notify about") {
          Picker(
            "Notify about",
            selection: Binding(
              get: { model.notifyScope },
              set: { model.setNotifyScope($0) }
            )
          ) {
            Text("Mentions and review requests").tag(NotifyScope.mentions)
            Text("Everything new").tag(NotifyScope.all)
            Text("Nothing").tag(NotifyScope.none)
          }
          .labelsHidden()
          .fixedSize()
        }

        Divider().padding(.leading, 12)

        SettingsRow(label: "Sound") {
          Picker(
            "Sound",
            selection: Binding(
              get: { model.notificationSound },
              set: { sound in
                model.setNotificationSound(sound)
                // Preview the tone the way System Settings does.
                if alertTones.contains(sound) {
                  NSSound(named: sound)?.play()
                }
              }
            )
          ) {
            Text("Default").tag("default")
            Text("None").tag("none")
            Divider()
            ForEach(alertTones, id: \.self) { tone in
              Text(tone).tag(tone)
            }
          }
          .labelsHidden()
          .fixedSize()
        }
      }
      .settingsCard()

      SettingsHint(text: "macOS also has to allow Majordomo's notifications — banners, badges, and whether sounds actually play live in System Settings.")
      Button("Open System Settings…") {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
          NSWorkspace.shared.open(url)
        }
      }
      .controlSize(.small)
      .padding(.horizontal, 4)
    }
    .padding(16)
  }
}

struct GeneralSettingsView: View {
  let model: AppModel

  var body: some View {
    SettingsRow(label: "Launch at login") {
      Toggle(
        "Launch at login",
        isOn: Binding(
          get: { model.launchAtLogin },
          set: { model.setLaunchAtLogin($0) }
        )
      )
      .labelsHidden()
      .toggleStyle(.switch)
      .controlSize(.small)
    }
    .settingsCard()
    .padding(16)
  }
}
