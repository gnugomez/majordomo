// A due day read in the user's calendar: the words that place it against
// today, and what doesn't parse.

import Foundation
import Testing
@testable import Majordomo

@Suite("Due days")
struct DueDateTests {
  @Test func wordsPlaceTheDayAgainstNow() {
    let now = referenceDate
    #expect(DueDate.words(for: isoDay(0, from: now), now: now).contains("today"))
    #expect(DueDate.words(for: isoDay(1, from: now), now: now).contains("tomorrow"))
    #expect(DueDate.words(for: isoDay(-1, from: now), now: now).contains("overdue"))
    #expect(!DueDate.words(for: isoDay(0, from: now), now: now).contains("overdue"))
    #expect(!DueDate.words(for: isoDay(2, from: now), now: now).contains("overdue"))
    #expect(DueDate.words(for: isoDay(0, from: now), now: now).contains("this_week"))
    #expect(!DueDate.words(for: isoDay(14, from: now), now: now).contains("this_week"))
  }

  @Test func aReferenceNamesADayInFullOrAgainstToday() {
    #expect(DueDate.reference("today") == .relative(0))
    #expect(DueDate.reference("Tomorrow ") == .relative(1))
    #expect(DueDate.reference("yesterday") == .relative(-1))
    #expect(DueDate.reference("in 7 days") == .relative(7))
    #expect(DueDate.reference("7 days") == .relative(7))
    #expect(DueDate.reference("1 day") == .relative(1))
    #expect(DueDate.reference("2 weeks") == .relative(14))
    #expect(DueDate.reference("3 days ago") == .relative(-3))
    #expect(DueDate.reference("1 week ago") == .relative(-7))
    #expect(DueDate.reference("2026-11-12") == DueDate.parse("2026-11-12").map(DayReference.on))
    #expect(DueDate.reference("soon") == nil)
    #expect(DueDate.reference("") == nil)
  }

  @Test func onlyACalendarDayParses() {
    #expect(DueDate.parse("2026-11-12") != nil)
    #expect(DueDate.parse("soon") == nil)
    #expect(DueDate.parse("2026-11-12T10:00:00Z") == nil)
    #expect(DueDate.words(for: "soon", now: referenceDate).isEmpty)
  }
}
