// Putting a thread away: when each preset ends, how a snooze reads, which
// bucket a snoozed item is in, and how the store brings one back — at its
// time, by hand, or when its target moves.

import Foundation
import Testing
@testable import Majordomo

@Suite("Snoozes")
struct SnoozeTests {
  /// London, where the clock reads plainly.
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_GB")
    return calendar
  }

  private func utc(_ text: String) -> Date {
    try! Date.ISO8601FormatStyle().parse(text)
  }

  @Test func presetsEndInHoursOrAtNineTheNextMorning() {
    // A Wednesday afternoon.
    let now = utc("2026-11-11T15:00:00Z")
    #expect(SnoozePreset.hour.wakeDate(from: now, calendar: calendar) == utc("2026-11-11T16:00:00Z"))
    #expect(SnoozePreset.threeHours.wakeDate(from: now, calendar: calendar) == utc("2026-11-11T18:00:00Z"))
    #expect(SnoozePreset.tomorrow.wakeDate(from: now, calendar: calendar) == utc("2026-11-12T09:00:00Z"))
    #expect(SnoozePreset.nextWeek.wakeDate(from: now, calendar: calendar) == utc("2026-11-16T09:00:00Z"))
    // From a Monday, next Monday is a week on, not the morning that passed.
    let monday = utc("2026-11-16T10:00:00Z")
    #expect(SnoozePreset.nextWeek.wakeDate(from: monday, calendar: calendar) == utc("2026-11-23T09:00:00Z"))
  }

  @Test func aSnoozeReadsByHowFarOffItEnds() {
    let now = utc("2026-11-11T15:00:00Z")
    #expect(snoozeWording(until: utc("2026-11-11T16:30:00Z"), now: now, calendar: calendar) == "until 16:30")
    #expect(snoozeWording(until: utc("2026-11-12T09:00:00Z"), now: now, calendar: calendar) == "until tomorrow 09:00")
    #expect(snoozeWording(until: utc("2026-11-16T09:00:00Z"), now: now, calendar: calendar) == "until Mon 09:00")
    #expect(snoozeWording(until: utc("2026-12-01T09:00:00Z"), now: now, calendar: calendar) == "until 1 Dec 09:00")
  }

  @Test func aSnoozedItemStaysInItsBucketsButQuiet() {
    var away = item("acct:2", title: "Rate-limit the search endpoint")
    away.snoozedUntil = Date().addingTimeInterval(3600)
    let buckets = categorize([item("acct:1"), away], into: categories(for: []))
    #expect(buckets.first { $0.id == catchAllInboxId }?.items.map(\.id) == ["acct:1", "acct:2"])
    #expect(buckets.first { $0.id == snoozedInboxId }?.items.map(\.id) == ["acct:2"])
    #expect(!away.pending)
    #expect(item("acct:1").pending)
    let thread = InboxThread(id: "t", items: [away])
    #expect(thread.snoozed)
    #expect(!thread.pending)
    #expect(thread.snoozedUntil == away.snoozedUntil)
    #expect(!InboxThread(id: "t", items: [item("acct:1"), away]).snoozed)
    // The unread filter and the badges count it quiet, unless it was read
    // in place.
    let threads = groupIntoThreads([item("acct:1"), away])
    #expect(matchingUnread(threads, kept: []).map(\.id) == [threads[0].id])
    #expect(matchingUnread(threads, kept: ["acct:2"]).count == 2)
    #expect(unreadThreadCount(in: [.inbox(buckets[0])]) == 1)
  }

  @Test func theStoreBringsAnItemBackAtItsTimeUnreadOrByHandAsItWas() {
    let store = fixtureStore(items: [storedItem(1, read: true), storedItem(2, read: true)])
    let now = Date()
    store.snooze(["acct:1"], until: now.addingTimeInterval(-1))
    store.snooze(["acct:2"], until: now.addingTimeInterval(3600))
    #expect(store.wakeSnoozes(now: now) == ["acct:1"])
    let woken = store.getItems().first { $0.id == "acct:1" }
    #expect(woken?.snoozedUntil == nil)
    #expect(woken?.read == false)
    store.unsnooze(["acct:2"])
    let back = store.getItems().first { $0.id == "acct:2" }
    #expect(back?.snoozedUntil == nil)
    #expect(back?.read == true)
  }

  @Test func activityOnTheTargetEndsASnooze() {
    var stored = storedItem(1, read: true, updatedAt: Date().addingTimeInterval(-3600))
    stored.snoozedUntil = Date().addingTimeInterval(3600)
    let store = fixtureStore(items: [stored])
    // The same activity keeps the snooze.
    let same = store.upsertItems([fetched(stored)], accountId: fixtureAccount, provider: .github)
    #expect(same.wokenIds.isEmpty)
    #expect(store.getItems().first?.snoozedUntil != nil)
    // Newer activity ends it, and the item comes back unread.
    var moved = stored
    moved.updatedAt = Date()
    let adopted = store.upsertItems([fetched(moved)], accountId: fixtureAccount, provider: .github)
    #expect(adopted.wokenIds == ["acct:1"])
    #expect(store.getItems().first?.snoozedUntil == nil)
    #expect(store.getItems().first?.read == false)
  }

  @Test func aNewNotificationOnTheThreadWakesIt() {
    var stored = storedItem(1, read: true)
    stored.snoozedUntil = Date().addingTimeInterval(3600)
    let store = fixtureStore(items: [stored])
    // Another notification on the same target: a thread member to be.
    var member = storedItem(2)
    member.url = stored.url + "#issuecomment-9"
    let adopted = store.upsertItems([fetched(member)], accountId: fixtureAccount, provider: .github)
    #expect(adopted.newIds == ["acct:2"])
    #expect(adopted.wokenIds == ["acct:1"])
    #expect(store.getItems().allSatisfy { $0.snoozedUntil == nil })
  }

  @Test func aSnoozeSurvivesTheStore() throws {
    var stored = storedItem(1)
    stored.snoozedUntil = Date(timeIntervalSince1970: 1_800_000_000)
    let data = try JSONEncoder().encode(stored)
    let back = try JSONDecoder().decode(StoredItem.self, from: data)
    #expect(back.snoozedUntil == stored.snoozedUntil)
    // An item stored before snoozes existed is in play.
    let older = try JSONDecoder().decode(StoredItem.self, from: JSONEncoder().encode(storedItem(2)))
    #expect(older.snoozedUntil == nil)
  }
}
