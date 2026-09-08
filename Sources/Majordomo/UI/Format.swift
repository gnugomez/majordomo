// Small formatting helpers for the views, ported from src/ui/format.ts.

import Foundation

private let sameYearFormatter: DateFormatter = {
  let f = DateFormatter()
  f.setLocalizedDateFormatFromTemplate("MMM d")
  return f
}()

private let otherYearFormatter: DateFormatter = {
  let f = DateFormatter()
  f.setLocalizedDateFormatFromTemplate("MMM d y")
  return f
}()

private let absoluteFormatter: DateFormatter = {
  let f = DateFormatter()
  f.dateStyle = .medium
  f.timeStyle = .short
  return f
}()

/// Compact relative time: "now", "5m", "3h", "2d", then a short date
/// ("Aug 12", with the year appended once it differs from the current one).
func relativeTime(_ date: Date, now: Date) -> String {
  let seconds = Int(max(0, now.timeIntervalSince(date)))
  if seconds < 60 {
    return "now"
  }
  let minutes = seconds / 60
  if minutes < 60 {
    return "\(minutes)m"
  }
  let hours = minutes / 60
  if hours < 24 {
    return "\(hours)h"
  }
  let days = hours / 24
  if days < 7 {
    return "\(days)d"
  }
  let calendar = Calendar.current
  let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
  return (sameYear ? sameYearFormatter : otherYearFormatter).string(from: date)
}

/// "Sep 2, 2026, 10:41" in the user's locale, for the preview pane.
func absoluteTime(_ date: Date) -> String {
  absoluteFormatter.string(from: date)
}

/// An item's meta line — "repo · author · 1h", skipping missing parts —
/// shared by the list rows and the tray-menu rows.
func metaLine(for item: InboxItem, now: Date) -> String {
  var parts: [String] = []
  if !item.repo.isEmpty {
    parts.append(item.repo)
  }
  if let author = item.author {
    parts.append(author)
  }
  parts.append(relativeTime(item.updatedAt, now: now))
  return parts.joined(separator: " · ")
}
