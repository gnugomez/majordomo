// The user's hand on items: reading them, opening them, and forcing a
// label on or off.

import AppKit
import Foundation

extension SyncEngine {
  /// The user's hand on one item's label: forced on, forced off, or (nil)
  /// back to whatever the rules say.
  func setLabelOverride(itemId: String, labelId: LabelId, on: Bool?) {
    store.setLabelOverride(itemId: itemId, labelId: labelId, on: on)
    record(.labelOverrides)
  }

  /// Opens the item in the browser and marks it read.
  func openItem(id: String) async {
    await openThread(ids: [id])
  }

  /// Opens the first item in the browser and marks the whole set read — a
  /// thread's members are one target, so opening it handles all of them.
  func openThread(ids: [String]) async {
    guard let first = ids.first, let item = store.item(first) else {
      return
    }
    if let url = URL(string: item.url) {
      await MainActor.run {
        _ = NSWorkspaceOpener.open(url)
      }
    }
    markRead(ids: ids)
  }

  func markRead(ids: [String]) {
    store.markRead(ids)
    record(.readState)
  }

  func markAllRead() {
    store.markAllRead()
    record(.readState)
  }
}

// AppKit is only touched here, isolated so the engine stays testable.
@MainActor
private enum NSWorkspaceOpener {
  static func open(_ url: URL) -> Bool {
    NSWorkspace.shared.open(url)
  }
}
