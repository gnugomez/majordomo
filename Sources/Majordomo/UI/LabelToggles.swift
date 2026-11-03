// Labeling by hand. The user's labels as a menu's toggles, applied to
// every item given at once — the inbox's context menu and the preview's
// label menu offer the same choice — and the labels a set of items carries,
// picked the same way wherever a row or the preview shows them. Tags only:
// an inbox is never applied by hand.

import SwiftUI

/// The labels any of these items carries, in the order `labels` gives them.
func carriedLabels(_ labels: [InboxLabel], on items: [InboxItem]) -> [InboxLabel] {
  labels.filter { label in items.contains { $0.labels.contains(label.id) } }
}

/// One toggle per user label, checked when every item carries it; turning
/// one on or off sets it on every item. A menu adds its own items after.
struct LabelToggles: View {
  let model: AppModel
  let items: [InboxItem]

  var body: some View {
    ForEach(model.userLabels) { label in
      Toggle(isOn: Binding(
        get: { !items.isEmpty && items.allSatisfy { $0.labels.contains(label.id) } },
        set: { wanted in
          for item in items {
            model.setItemLabel(item.id, label.id, on: wanted)
          }
        }
      )) {
        Label(label.name, systemImage: label.symbol)
      }
    }
    if model.userLabels.isEmpty {
      Text("No labels yet")
    }
  }
}
