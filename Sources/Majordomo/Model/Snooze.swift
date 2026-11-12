// Quieting a thread for a while: the presets the Snooze menu offers, when
// each ends, and how a snooze reads on a row. A snoozed thread stays in
// its inboxes, marked with a clock in place of its unread dot, but out of
// every count and banner until its time — or until its target moves,
// which is sooner — and then comes back unread with a banner: the
// reminder the snooze was for. The sidebar lists what is snoozed under
// Snoozed as well, and any menu's Unsnooze cuts one short.

import Foundation

/// The sidebar's inbox of what is snoozed, drawn after the layout's rows.
let snoozedInboxId = "snoozed"

/// The hour a morning snooze ends at.
private let morningHour = 9

/// How long a thread is put away for.
enum SnoozePreset: String, CaseIterable, Identifiable, Sendable {
  case hour
  case threeHours
  case tomorrow
  case nextWeek

  var id: String { rawValue }

  var label: String {
    switch self {
    case .hour: "1 hour"
    case .threeHours: "3 hours"
    case .tomorrow: "Tomorrow morning"
    case .nextWeek: "Next Monday"
    }
  }

  /// When a snooze taken at `now` ends: so many hours on, or nine the next
  /// morning — tomorrow's, or the coming Monday's.
  func wakeDate(from now: Date, calendar: Calendar = .current) -> Date {
    switch self {
    case .hour:
      now.addingTimeInterval(60 * 60)
    case .threeHours:
      now.addingTimeInterval(3 * 60 * 60)
    case .tomorrow:
      morning(daysOn: 1, from: now, calendar: calendar)
    case .nextWeek:
      morning(daysOn: daysToNextMonday(from: now, calendar: calendar), from: now, calendar: calendar)
    }
  }
}

private func morning(daysOn days: Int, from now: Date, calendar: Calendar) -> Date {
  let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now)) ?? now
  return calendar.date(bySettingHour: morningHour, minute: 0, second: 0, of: day) ?? day
}

/// Days to the Monday after `now`: a week from a Monday.
private func daysToNextMonday(from now: Date, calendar: Calendar) -> Int {
  let monday = 2
  let days = (monday - calendar.component(.weekday, from: now) + 7) % 7
  return days == 0 ? 7 : days
}

/// A snooze's end as a row or the preview says it: the time today,
/// tomorrow's, a weekday's within the week, or a date's.
func snoozeWording(until: Date, now: Date, calendar: Calendar = .current) -> String {
  let style = Date.FormatStyle(locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone)
  let time = until.formatted(style.hour().minute())
  if calendar.isDate(until, inSameDayAs: now) {
    return "until \(time)"
  }
  if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(until, inSameDayAs: tomorrow) {
    return "until tomorrow \(time)"
  }
  if let week = calendar.date(byAdding: .day, value: 6, to: now), until < week {
    return "until \(until.formatted(style.weekday(.abbreviated))) \(time)"
  }
  return "until \(until.formatted(style.day().month(.abbreviated))) \(time)"
}
