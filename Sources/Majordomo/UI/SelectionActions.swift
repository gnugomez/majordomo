// What can be done with a selection where it is shown: open it in the
// browser, which marks it read too, or only mark it read — offered only
// while something in it is still unread. The preview carries it for one
// thread or a message picked in it, the pane of a multiple selection for
// several; ⌘O and ⇧⌘U reach it while either shows.

import SwiftUI

struct SelectionActions: View {
  let model: AppModel
  let threads: [InboxThread]

  var body: some View {
    HStack(spacing: 8) {
      Button(openLabel, systemImage: "arrow.up.forward") {
        for thread in threads {
          model.openThread(thread.itemIds)
        }
      }
      .keyboardShortcut("o")
      .help("Opens in your browser and marks read")
      if threads.contains(where: { !$0.read }) {
        Button(markLabel, systemImage: "envelope.open") {
          model.markRead(Set(threads.flatMap(\.itemIds)))
        }
        .keyboardShortcut("u", modifiers: [.shift, .command])
      }
    }
  }

  private var openLabel: String {
    threads.count == 1 ? "Open in \(threads[0].lead.provider.displayName)" : "Open \(threads.count) in Browser"
  }

  private var markLabel: String {
    threads.count == 1 ? "Mark as Read" : "Mark \(threads.count) as Read"
  }
}
