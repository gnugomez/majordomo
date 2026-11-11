// The settings pages, split into the categories the tabbed
// settings window shows: Accounts (the account list with its add/remove
// pair and token update), General (launch at login, and the inbox-row
// editor next door), and Notifications. Inboxes, Labels, and Rules have
// files of their own; the pieces every page is built from are in
// SettingsComponents.

import AppKit
import SwiftUI

struct AccountsSettingsView: View {
  let model: AppModel

  @State private var selection: AccountId?
  @State private var addSheetShown = false
  /// The account whose token is being replaced, while its sheet is up.
  @State private var updating: AccountState?
  /// The account whose error is open in full, while its sheet is up.
  @State private var troubled: AccountState?
  @State private var confirmRemove = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      List(selection: $selection) {
        ForEach(model.accounts) { account in
          HStack(spacing: 10) {
            // An error takes the line; short of one, what the token
            // leaves out of reach, since nothing else would say.
            AccountSummary(
              account: account,
              detail: account.error ?? account.note ?? accountDescriptor(account),
              detailStyle: account.error == nil && account.note == nil
                ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange)
            )
            Spacer()
            // What the provider answered, in full, when the line can't
            // say what went wrong.
            if account.errorDetails != nil {
              Button("Details…") {
                troubled = account
              }
              .controlSize(.small)
              .help("What \(account.provider.displayName) answered")
            }
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
      .emptyListNote("No accounts connected", when: model.accounts.isEmpty)

      HStack(spacing: 8) {
        // The +/− pair: add opens the wizard sheet (any number of accounts
        // per provider), remove disconnects the selected account.
        AddRemoveButtons(
          addHelp: "Add an account",
          removeHelp: "Remove the selected account",
          canRemove: hasSelection,
          onAdd: { addSheetShown = true },
          onRemove: { confirmRemove = true }
        )
        // A new token for the selected account — the remedy when one expires
        // or is revoked — leaving its items and their read state alone.
        Button("Update Token…") {
          updating = model.accounts.first { $0.id == selection }
        }
        .controlSize(.small)
        .disabled(!hasSelection)
        .help("Replace the selected account's token")
      }
    }
    .padding(16)
    .sheet(isPresented: $addSheetShown) {
      AddAccountSheet(model: model)
    }
    .sheet(item: $updating) { account in
      AddAccountSheet(model: model, updating: account)
    }
    .sheet(item: $troubled) { account in
      if let trouble = account.trouble {
        AccountTroubleSheet(title: accountDescriptor(account), trouble: trouble)
      }
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
      Text("Its items leave the inbox and the token is forgotten. Add the same account back within 90 days and they return, read state and all.")
    }
  }

  private var hasSelection: Bool {
    selection != nil && model.accounts.contains { $0.id == selection }
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
    VStack(alignment: .leading, spacing: 12) {
      SettingsRow(label: "Launch at login") {
        SettingsSwitch(
          "Launch at login",
          isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })
        )
      }
      .settingsCard()

      RowLayoutEditor(model: model)
    }
    .padding(16)
  }
}
