// One row of a rule's targets: the chosen inboxes and labels as pills,
// and a menu to toggle them, grouped the way the sidebar groups them. The
// rule editor draws this twice — once for what a rule applies, once for
// what a moving rule hides from — and the two must never offer the same
// target, so each passes the other's choices as unavailable.

import SwiftUI

struct RuleTargetRow: View {
  /// The targets currently chosen, in the order they should read.
  let pills: [InboxLabel]
  /// Shown when nothing is chosen; drawn as a neutral pill when
  /// `placeholderIsPill`, since "Everywhere else" is a real state rather
  /// than an empty one.
  let placeholder: String
  var placeholderIsPill = false
  let inboxes: [InboxLabel]
  let labels: [InboxLabel]
  /// Targets the other row has taken; listed but not choosable here.
  var unavailable: Set<LabelId> = []
  let help: String
  var enabled = true
  let binding: (LabelId) -> Binding<Bool>

  var body: some View {
    HStack(spacing: 6) {
      if pills.isEmpty {
        if placeholderIsPill {
          Text(placeholder)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .fixedSize()
        } else {
          Text(placeholder)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
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
      .disabled(!enabled || (inboxes.isEmpty && labels.isEmpty))
      .help(help)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .settingsCard()
    .opacity(enabled ? 1 : 0.5)
  }

  @ViewBuilder
  private func section(_ title: String, _ choices: [InboxLabel]) -> some View {
    if !choices.isEmpty {
      Section(title) {
        ForEach(choices) { choice in
          Toggle(isOn: binding(choice.id)) {
            Label(choice.name, systemImage: choice.symbol)
          }
          .disabled(unavailable.contains(choice.id))
        }
      }
    }
  }
}
