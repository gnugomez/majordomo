import Foundation
import Testing

@testable import Majordomo

@Suite("Board filter")
struct BoardFilterTests {
  @Test func theDateWindowKeepsCardsActiveSinceItsCutoff() {
    let fresh = card("fresh", updatedAt: referenceDate.addingTimeInterval(-days(1)))
    let stale = card("stale", updatedAt: referenceDate.addingTimeInterval(-days(10)))
    let cutoff = ActivityWindow.week.cutoff(from: referenceDate)
    #expect(matchingWindow([fresh, stale], since: cutoff).map(\.id) == ["fresh"])
    #expect(matchingWindow([fresh, stale], since: nil).map(\.id) == ["fresh", "stale"])
  }

  @Test func aNotificationNewerThanTheTargetCountsAsActivity() {
    // The target last moved long ago, but a notification on it is recent.
    let recent = item("quiet:1", updatedAt: referenceDate.addingTimeInterval(-days(1)))
    let quiet = card("quiet", items: [recent], updatedAt: referenceDate.addingTimeInterval(-days(40)))
    let cutoff = ActivityWindow.twoDays.cutoff(from: referenceDate)
    #expect(matchingWindow([quiet], since: cutoff).map(\.id) == ["quiet"])
  }

  @Test func unreadOnlyKeepsUnreadCardsAndTheOnesReadUnderIt() {
    let unread = card("unread", items: [item("unread:1", read: false)])
    let read = card("read", items: [item("read:1", read: true)])
    let justRead = card("just-read", items: [item("just-read:1", read: true)])
    let kept = matchingUnread([unread, read, justRead], kept: ["just-read:1"])
    #expect(kept.map(\.id) == ["unread", "just-read"])
  }
}
