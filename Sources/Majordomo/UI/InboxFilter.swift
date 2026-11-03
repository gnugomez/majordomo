// What the toolbar's filter narrows the inbox and the boards by: unread,
// a date window, and one pick per facet. The filter keeps its set while it
// is switched off; what applies is `AppModel.narrowing`, the set while the
// filter is on and nothing while it is off.

import Foundation

struct InboxFilter: Hashable, Sendable {
  var unreadOnly = false
  /// nil is any time.
  var window: ActivityWindow?
  var picks: [Facet: String] = [:]

  /// Whether nothing is set, so the filter narrows nothing.
  var isEmpty: Bool {
    !unreadOnly && window == nil && picks.isEmpty
  }

  /// The set in words, for the window's subtitle and VoiceOver: the picks
  /// in the menu's order, then Unread, then the date window —
  /// "@mona, GitHub, Unread, Last week". Empty when nothing is set.
  var summary: String {
    var parts = Facet.allCases.compactMap { facet in
      picks[facet].map(facet.display)
    }
    if unreadOnly {
      parts.append("Unread")
    }
    if let window {
      parts.append(window.label)
    }
    return parts.joined(separator: ", ")
  }
}
