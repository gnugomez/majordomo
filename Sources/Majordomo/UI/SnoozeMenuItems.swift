// The Snooze menu's items, the same wherever a thread's menu offers them:
// a preset each, and Unsnooze for what is put away. The preview's button,
// a row's menu, and a card's menu all carry it.

import SwiftUI

struct SnoozeMenuItems: View {
  let model: AppModel
  let threads: [InboxThread]

  var body: some View {
    ForEach(SnoozePreset.allCases) { preset in
      Button(preset.label) {
        model.snooze(ids, for: preset)
      }
    }
    if threads.contains(where: \.snoozed) {
      Divider()
      Button("Unsnooze") {
        model.unsnooze(ids)
      }
    }
  }

  private var ids: Set<String> {
    Set(threads.flatMap(\.itemIds))
  }
}
