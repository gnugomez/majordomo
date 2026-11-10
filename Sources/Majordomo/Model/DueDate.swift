// The calendar day a target is due, as both providers give it —
// "2026-11-12", no time of day. The core reads it in the user's own
// calendar: a rule tests the day itself, or a word that places it against
// today, so a column can hold what is due or overdue.

import Foundation

enum DueDate {
  /// The words a rule can test a due day by: "today"; "tomorrow";
  /// "this_week", any day of the current week, gone or to come; and
  /// "overdue", a day gone by.
  static let vocabulary = ["today", "tomorrow", "this_week", "overdue"]

  /// The day, at its start in `calendar`; nil for anything but
  /// "yyyy-MM-dd".
  static func parse(_ day: String, calendar: Calendar = .current) -> Date? {
    let parts = day.split(separator: "-")
    guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let dayOfMonth = Int(parts[2]) else {
      return nil
    }
    return calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth))
  }

  /// How the day stands against `now`: each word of the vocabulary that
  /// holds; none for a day that doesn't parse.
  static func words(for day: String, now: Date, calendar: Calendar = .current) -> [String] {
    guard let due = parse(day, calendar: calendar) else {
      return []
    }
    var holding: [String] = []
    if calendar.isDate(due, inSameDayAs: now) {
      holding.append("today")
    } else if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(due, inSameDayAs: tomorrow) {
      holding.append("tomorrow")
    } else if due < calendar.startOfDay(for: now) {
      holding.append("overdue")
    }
    if calendar.isDate(due, equalTo: now, toGranularity: .weekOfYear) {
      holding.append("this_week")
    }
    return holding
  }
}
