// One row of a rule's targets: the inboxes and labels it applies, as
// pills, with a menu to toggle them grouped the way the sidebar groups
// them.

import SwiftUI

struct RuleTargetRow: View {
  /// The targets currently chosen, in the order they should read.
  let pills: [InboxLabel]
  /// Shown when nothing is chosen.
  let placeholder: String
  let inboxes: [InboxLabel]
  let labels: [InboxLabel]
  let help: String
  let binding: (LabelId) -> Binding<Bool>

  var body: some View {
    HStack(spacing: 6) {
      if pills.isEmpty {
        Text(placeholder)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      } else {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 4) {
            ForEach(pills) { label in
              LabelCapsule(label: label)
            }
          }
        }
      }
      Spacer(minLength: 0)
      Menu {
        section("Inboxes", inboxes)
        section("Labels", labels)
      } label: {
        Image(systemName: "plus")
      }
      .menuIndicator(.hidden)
      .controlSize(.small)
      .fixedSize()
      .disabled(inboxes.isEmpty && labels.isEmpty)
      .help(help)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .settingsCard()
  }

  @ViewBuilder
  private func section(_ title: String, _ choices: [InboxLabel]) -> some View {
    if !choices.isEmpty {
      Section(title) {
        ForEach(choices) { choice in
          Toggle(isOn: binding(choice.id)) {
            Label(choice.name, systemImage: choice.symbol)
          }
        }
      }
    }
  }
}
