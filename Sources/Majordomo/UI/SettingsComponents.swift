// The pieces every settings page is built from: the rounded card a group
// sits in, a labeled row, a switch, the caption under a card, the +/− pair
// under a list, a list's note while it is empty, and an account named the
// way the Accounts list names it.

import SwiftUI

/// The rounded card every settings group sits in.
extension View {
  func settingsCard() -> some View {
    background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
  }

  /// A bordered list's note while it has no rows, centered over it.
  func emptyListNote(_ text: String, when empty: Bool) -> some View {
    overlay {
      if empty {
        Text(text)
          .font(.app(.callout))
          .foregroundStyle(.secondary)
      }
    }
  }
}

/// One labeled row inside a settings card: label left, control right, with
/// an optional leading glyph (tinted when the row stands for a label).
struct SettingsRow<Control: View>: View {
  var symbol: String?
  var tint: Color?
  let label: String
  @ViewBuilder var control: Control

  var body: some View {
    HStack(spacing: 8) {
      if let symbol {
        Image(systemName: symbol)
          .frame(width: 18)
          .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.secondary))
      }
      Text(label)
        .font(.app(.body))
      Spacer()
      control
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }
}

/// A settings switch: small, its label left to the row it sits in (and to
/// accessibility).
struct SettingsSwitch: View {
  let title: String
  @Binding var isOn: Bool

  init(_ title: String, isOn: Binding<Bool>) {
    self.title = title
    _isOn = isOn
  }

  var body: some View {
    Toggle(title, isOn: $isOn)
      .labelsHidden()
      .toggleStyle(.switch)
      .controlSize(.small)
  }
}

/// The explanatory caption under a settings card.
struct SettingsHint: View {
  let text: String

  var body: some View {
    Text(text)
      .font(.app(.caption))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 4)
  }
}

/// The +/− pair under a list: add, and remove what is selected.
struct AddRemoveButtons: View {
  let addHelp: String
  let removeHelp: String
  let canRemove: Bool
  let onAdd: () -> Void
  let onRemove: () -> Void

  var body: some View {
    ControlGroup {
      Button(action: onAdd) {
        Image(systemName: "plus")
      }
      .help(addHelp)
      Button(action: onRemove) {
        Image(systemName: "minus")
      }
      .disabled(!canRemove)
      .help(removeHelp)
    }
    .controlSize(.small)
    .fixedSize()
  }
}

/// An account as the settings name it: its face, its name, and a line
/// under it — who and where, or what went wrong, whole in its tooltip
/// where the line runs short.
struct AccountSummary: View {
  let account: AccountState
  let detail: String
  var detailStyle: AnyShapeStyle = AnyShapeStyle(.secondary)

  var body: some View {
    HStack(spacing: 10) {
      AccountAvatar(account: account, size: 26)
      VStack(alignment: .leading, spacing: 1) {
        Text(account.name ?? "@\(account.username ?? "unknown")")
          .font(.app(.body, weight: .medium))
        Text(detail)
          .font(.app(.caption))
          .foregroundStyle(detailStyle)
          .lineLimit(1)
          .help(detail)
      }
    }
  }
}
