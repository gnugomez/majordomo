// An account's failure in full: the message its row shows, when it was
// met, and the exchange behind it — the status, headers, and body the
// provider answered with, or what the system said when nothing did — laid
// out to read or copy, for the cases where the message alone doesn't say
// what to fix. Opened from the Accounts pane's Details button, and from
// the add-account sheet when a token is turned down.

import AppKit
import SwiftUI

struct AccountTroubleSheet: View {
  /// Whose trouble: the account as the Accounts pane names it, or the
  /// provider a token was offered to.
  let title: String
  let trouble: AccountTrouble

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.app(.heading, weight: .semibold))
        Text("Failed \(trouble.at, format: .dateTime.day().month(.abbreviated).hour().minute())")
          .font(.app(.caption))
          .foregroundStyle(.secondary)
      }
      Text(trouble.message)
        .font(.app(.body))
        .foregroundStyle(.orange)
        .fixedSize(horizontal: false, vertical: true)
      ScrollView {
        Text(trouble.details ?? "The provider's answer wasn't kept.")
          .font(.app(.callout, design: .monospaced))
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(10)
      }
      .background(Palette.code, in: RoundedRectangle(cornerRadius: 6))
      HStack {
        Button("Copy") {
          copy()
        }
        .help("Copy the message and the exchange")
        Spacer()
        Button("Done") {
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(16)
    .frame(width: 640, height: 480)
  }

  private func copy() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(
      ([title, trouble.message] + [trouble.details].compactMap { $0 }).joined(separator: "\n\n"), forType: .string
    )
  }
}
