// What an inbox row shows, and in what order. The fields name structural
// parts of a row — where an item is, who wrote it, when it moved, its
// badges, its text — never a provider's vocabulary, so the arrangement
// stays generic. The user makes it in Settings → General; it is remembered
// in UserDefaults like the rest of the view state.

import Foundation

/// One piece of an inbox row the user can switch off and drag around.
enum RowField: String, Codable, CaseIterable, Sendable, Identifiable {
  /// The project the item belongs to.
  case repo
  /// Whoever wrote it.
  case author
  /// How long ago it last moved — "3h".
  case time
  /// The mark of the provider it came from.
  case provider
  /// The labels the row carries.
  case labels
  /// The state-or-reason capsule.
  case status
  /// A couple of lines of the item's text.
  case excerpt

  var id: String { rawValue }

  /// The settings page's wording.
  var title: String {
    switch self {
    case .repo: "Repository"
    case .author: "Author"
    case .time: "Time"
    case .provider: "Provider mark"
    case .labels: "Labels"
    case .status: "Status"
    case .excerpt: "Excerpt"
    }
  }

  /// What it is, in the settings row's trailing column.
  var detail: String {
    switch self {
    case .repo: "The project it belongs to"
    case .author: "Who wrote it"
    case .time: "How long ago it moved"
    case .provider: "Where it came from"
    case .labels: "The labels it carries"
    case .status: "Its state or reason"
    case .excerpt: "A couple of lines of its text"
    }
  }

  /// Badges ride the trailing end of the meta line, behind the flexible
  /// gap; the rest reads inline from the left.
  var isBadge: Bool {
    switch self {
    case .labels, .status: true
    case .repo, .author, .time, .provider, .excerpt: false
    }
  }
}

/// The fields an inbox row shows, in the order it shows them.
struct RowLayout: Codable, Equatable, Sendable {
  /// Every field in display order, switched-off ones included — turning
  /// one back on restores it where it was.
  var order: [RowField]
  var hidden: Set<RowField>

  /// The row as it reads out of the box: where and who, then when, then
  /// the badges. The excerpt is off — it is the one field that costs a
  /// line of height.
  static let `default` = RowLayout(order: RowField.allCases, hidden: [.excerpt])

  func shows(_ field: RowField) -> Bool {
    !hidden.contains(field)
  }

  /// The fields to render, in order.
  var visible: [RowField] {
    order.filter(shows)
  }

  func setting(_ field: RowField, shown: Bool) -> RowLayout {
    var layout = self
    if shown {
      layout.hidden.remove(field)
    } else {
      layout.hidden.insert(field)
    }
    return layout
  }

  func moving(fromOffsets source: IndexSet, toOffset destination: Int) -> RowLayout {
    var layout = self
    layout.order.move(fromOffsets: source, toOffset: destination)
    return layout
  }
}

extension RowLayout {
  /// A stored layout, normalized: fields the app no longer has are
  /// dropped, and fields it has gained since drop in at the end — an
  /// older arrangement still opens, rather than losing a row's parts.
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let stored = try container.decodeIfPresent([String].self, forKey: .order) ?? []
    let storedHidden = try container.decodeIfPresent([String].self, forKey: .hidden) ?? []
    var fields = stored.compactMap(RowField.init(rawValue:))
    fields.append(contentsOf: RowField.allCases.filter { !fields.contains($0) })
    order = fields
    hidden = Set(storedHidden.compactMap(RowField.init(rawValue:)))
  }
}
