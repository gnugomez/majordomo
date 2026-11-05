// The user's choices that outlive a launch, in UserDefaults under the keys
// they have always had. One mechanism reads and writes them all: a
// PreferenceKey names the key, the value it reads as when unset or
// unreadable, and how the value goes in and out; Preferences holds the
// live values, observable like any model state, and writes each back as it
// changes. A new preference is a key and a property.

import Foundation
import Observation

/// Which new unread items post a notification.
enum NotifyScope: String, CaseIterable, Sendable {
  /// The "needs you" tier — mentions and review requests (the default).
  case mentions
  /// Every item that enters the inbox unread.
  case all
  /// No notifications at all.
  case none
}

/// Where a board's preview stands.
enum PreviewPlacement: String, CaseIterable, Sendable {
  /// At the trailing edge, as the inbox's does (the default).
  case trailing
  /// Under the board, for its whole width: the facts beside what the
  /// notifications say and the conversation.
  case bottom
}

/// One value kept in UserDefaults.
struct PreferenceKey<Value> {
  let name: String
  /// What it reads as when unset or unreadable.
  let fallback: Value
  /// From what UserDefaults holds; nil when it can't be read as a value.
  let decode: (Any) -> Value?
  /// Into what UserDefaults holds; nil removes the key.
  let encode: (Value) -> Any?
}

extension PreferenceKey {
  /// A value UserDefaults holds as it is: a Bool, a String.
  static func plain(_ name: String, default fallback: Value) -> PreferenceKey {
    PreferenceKey(name: name, fallback: fallback, decode: { $0 as? Value }, encode: { $0 })
  }

  /// An optional value UserDefaults holds as it is; nil is no key.
  static func optional<Wrapped>(_ name: String) -> PreferenceKey<Wrapped?> {
    PreferenceKey<Wrapped?>(name: name, fallback: nil, decode: { $0 as? Wrapped }, encode: { $0 })
  }

  /// An enum kept by its raw value.
  static func raw(_ name: String, default fallback: Value) -> PreferenceKey
  where Value: RawRepresentable {
    PreferenceKey(
      name: name, fallback: fallback,
      decode: { ($0 as? Value.RawValue).flatMap(Value.init(rawValue:)) },
      encode: { $0.rawValue }
    )
  }

  /// An optional enum kept by its raw value; nil is no key.
  static func optionalRaw<Wrapped: RawRepresentable>(_ name: String) -> PreferenceKey<Wrapped?> {
    PreferenceKey<Wrapped?>(
      name: name, fallback: nil,
      decode: { ($0 as? Wrapped.RawValue).flatMap(Wrapped.init(rawValue:)) },
      encode: { $0?.rawValue }
    )
  }

  /// A value kept as JSON.
  static func json(_ name: String, default fallback: Value) -> PreferenceKey where Value: Codable {
    PreferenceKey(
      name: name, fallback: fallback,
      decode: { ($0 as? Data).flatMap { try? JSONDecoder().decode(Value.self, from: $0) } },
      encode: { try? JSONEncoder().encode($0) }
    )
  }
}

extension PreferenceKey where Value == Bool {
  /// A switch kept as its opposite — "shown" under a key that says
  /// "hidden", so an unset key reads as shown.
  static func inverted(_ name: String) -> PreferenceKey {
    PreferenceKey(name: name, fallback: true, decode: { ($0 as? Bool).map(!) }, encode: { !$0 })
  }
}

/// Where preferences are kept: UserDefaults, or a dictionary in the tests.
protocol PreferenceStore: AnyObject {
  func object(forKey key: String) -> Any?
  func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: PreferenceStore {}

extension PreferenceStore {
  subscript<Value>(key: PreferenceKey<Value>) -> Value {
    get {
      object(forKey: key.name).flatMap(key.decode) ?? key.fallback
    }
    set {
      set(key.encode(newValue), forKey: key.name)
    }
  }
}

/// Every preference's key.
private enum Keys {
  static var intelligenceEnabled: PreferenceKey<Bool> { .plain("intelligenceEnabled", default: true) }
  static var suggestionsEnabled: PreferenceKey<Bool> { .plain("suggestionsEnabled", default: true) }
  static var summariesEnabled: PreferenceKey<Bool> { .plain("summariesEnabled", default: true) }
  static var sidebarCategory: PreferenceKey<String> { .plain("sidebarCategory", default: recentCategory.id) }
  static var sidebarBoard: PreferenceKey<BoardId?> { PreferenceKey<BoardId?>.optional("sidebarBoard") }
  static var activityWindow: PreferenceKey<ActivityWindow?> {
    PreferenceKey<ActivityWindow?>.optionalRaw("activityWindow")
  }
  static var unreadOnly: PreferenceKey<Bool> { .plain("unreadOnly", default: false) }
  static var notifyScope: PreferenceKey<NotifyScope> { .raw("notifyScope", default: .mentions) }
  static var notificationSound: PreferenceKey<String> { .plain("notificationSound", default: "default") }
  static var rowLayout: PreferenceKey<RowLayout> { .json("rowLayout", default: .default) }
  static var sidebarShown: PreferenceKey<Bool> { .inverted("sidebarHidden") }
  static var inboxPreviewShown: PreferenceKey<Bool> { .inverted("previewHidden") }
  static var boardPreviewPlacement: PreferenceKey<PreviewPlacement> {
    .raw("boardPreviewPlacement", default: .trailing)
  }
}

@MainActor
@Observable
final class Preferences {
  @ObservationIgnored private let defaults: any PreferenceStore

  /// The master switch over every on-device feature.
  var intelligenceEnabled: Bool {
    didSet { defaults[Keys.intelligenceEnabled] = intelligenceEnabled }
  }
  var suggestionsEnabled: Bool {
    didSet { defaults[Keys.suggestionsEnabled] = suggestionsEnabled }
  }
  var summariesEnabled: Bool {
    didSet { defaults[Keys.summariesEnabled] = summariesEnabled }
  }
  /// Which inbox or board the main window shows. An inbox spans every
  /// account, so a `sidebarAccount` key left in the defaults is never
  /// read: the category it scoped opens across them all.
  var sidebarSelection: SidebarSelection {
    didSet {
      defaults[Keys.sidebarCategory] = sidebarSelection.category
      defaults[Keys.sidebarBoard] = sidebarSelection.board
    }
  }
  /// The toolbar's date filter; nil is any time.
  var activityWindow: ActivityWindow? {
    didSet { defaults[Keys.activityWindow] = activityWindow }
  }
  var unreadOnly: Bool {
    didSet { defaults[Keys.unreadOnly] = unreadOnly }
  }
  var notifyScope: NotifyScope {
    didSet { defaults[Keys.notifyScope] = notifyScope }
  }
  /// "default", "none", or a system alert sound name ("Ping").
  var notificationSound: String {
    didSet { defaults[Keys.notificationSound] = notificationSound }
  }
  var rowLayout: RowLayout {
    didSet { defaults[Keys.rowLayout] = rowLayout }
  }
  var sidebarShown: Bool {
    didSet { defaults[Keys.sidebarShown] = sidebarShown }
  }
  var inboxPreviewShown: Bool {
    didSet { defaults[Keys.inboxPreviewShown] = inboxPreviewShown }
  }
  var boardPreviewPlacement: PreviewPlacement {
    didSet { defaults[Keys.boardPreviewPlacement] = boardPreviewPlacement }
  }

  init(defaults: any PreferenceStore = UserDefaults.standard) {
    self.defaults = defaults
    intelligenceEnabled = defaults[Keys.intelligenceEnabled]
    suggestionsEnabled = defaults[Keys.suggestionsEnabled]
    summariesEnabled = defaults[Keys.summariesEnabled]
    sidebarSelection = SidebarSelection(
      category: defaults[Keys.sidebarCategory],
      board: defaults[Keys.sidebarBoard]
    )
    activityWindow = defaults[Keys.activityWindow]
    unreadOnly = defaults[Keys.unreadOnly]
    notifyScope = defaults[Keys.notifyScope]
    notificationSound = defaults[Keys.notificationSound]
    rowLayout = defaults[Keys.rowLayout]
    sidebarShown = defaults[Keys.sidebarShown]
    inboxPreviewShown = defaults[Keys.inboxPreviewShown]
    boardPreviewPlacement = defaults[Keys.boardPreviewPlacement]
  }
}
