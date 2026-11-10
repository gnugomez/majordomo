// The calendar day a target is due, as both providers give it —
// "2026-11-12", no time of day. The core reads it in the user's own
// calendar: a rule tests the day itself, or a word that places it against
// today, so a column can hold what is due or overdue.

import Foundation

/// A day a subject holds for a field: when, at its start in the user's
/// calendar, and how far it stands from the day the subject was made, in
/// days — what "today" and "in 7 days" in a condition count from.
struct FieldDay: Equatable, Sendable {
  let date: Date
  let offset: Int
}

/// The day a condition sets a field's day against: one in full, or one
/// so many days from today.
enum DayReference: Equatable, Sendable {
  case on(Date)
  case relative(Int)
}

enum DueDate {
  /// The words a rule can test a due day by: "today"; "tomorrow";
  /// "this_week", any day of the current week, gone or to come; and
  /// "overdue", a day gone by.
  static let vocabulary = ["today", "tomorrow", "this_week", "overdue"]

  /// Days worth offering to set a due day against, in the forms
  /// `reference` reads.
  static let references = ["today", "tomorrow", "yesterday", "in 7 days", "in 30 days", "7 days ago"]

  /// The day a condition names: one in full ("2026-11-12"); "today",
  /// "tomorrow", or "yesterday"; or so many days or weeks from today —
  /// "in 7 days", "2 weeks", "3 days ago". nil for anything else.
  static func reference(_ value: String, calendar: Calendar = .current) -> DayReference? {
    let text = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if let date = parse(text, calendar: calendar) {
      return .on(date)
    }
    switch text {
    case "today": return .relative(0)
    case "tomorrow": return .relative(1)
    case "yesterday": return .relative(-1)
    default: break
    }
    guard let match = text.wholeMatch(of: #/(?:in\s+)?(\d+)\s+(days?|weeks?)(?:\s+(ago))?/#), let count = Int(match.1) else {
      return nil
    }
    let days = match.2.hasPrefix("week") ? count * 7 : count
    return .relative(match.3 == nil ? days : -days)
  }

  /// A due day as a subject holds it, set against `now`; nil for a day
  /// that doesn't parse.
  static func fieldDay(_ day: String, now: Date, calendar: Calendar = .current) -> FieldDay? {
    guard let date = parse(day, calendar: calendar) else {
      return nil
    }
    let offset = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: date).day ?? 0
    return FieldDay(date: date, offset: offset)
  }

  /// How a subject's day stands to the day named: negative when earlier,
  /// zero when the same, positive when later, in days.
  static func distance(of day: FieldDay, from reference: DayReference, calendar: Calendar = .current) -> Int {
    switch reference {
    case .on(let date): calendar.dateComponents([.day], from: date, to: day.date).day ?? 0
    case .relative(let days): day.offset - days
    }
  }

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
