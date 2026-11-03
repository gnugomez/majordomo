// The main-actor side: a push is taken in slice by slice, by revision;
// the observation rules that makes worth it; and the preferences' one
// way in and out of their store.

import Foundation
import Observation
import Synchronization
import Testing
@testable import Majordomo

/// Preferences kept in memory, so nothing reaches the user's defaults.
private final class MemoryDefaults: PreferenceStore {
  private(set) var values: [String: Any] = [:]

  func object(forKey key: String) -> Any? {
    values[key]
  }

  func set(_ value: Any?, forKey key: String) {
    values[key] = value
  }
}

/// Whether reading `read` is told of what `write` does.
@MainActor
private func notifies(_ read: @escaping () -> Void, when write: () -> Void) -> Bool {
  let told = Mutex(false)
  withObservationTracking(read) {
    told.withLock { $0 = true }
  }
  write()
  return told.withLock { $0 }
}

@Suite("App model")
@MainActor
struct AppModelTests {
  private let defaults = MemoryDefaults()

  @Test func applyTakesOnlyMovedSlices() {
    let model = AppModel(preferences: Preferences(defaults: defaults))
    var state = AppState()
    state.items = [item("acct:1"), item("acct:2", read: true)]
    state.labels = [userLabel("work")]
    state.revisions.bump(.items)
    state.revisions.bump(.labels)
    model.apply(state)
    #expect(model.items.map(\.id) == ["acct:1", "acct:2"])
    #expect(model.unreadCount == 1)

    // Only the labels' revision moves: the items in the push are not
    // looked at, and no reader of the items is told anything.
    var next = state
    next.items = []
    next.labels = [userLabel("home")]
    next.revisions.bump(.labels)
    let itemsTold = notifies({ _ = model.items }, when: { model.apply(next) })
    #expect(!itemsTold)
    #expect(model.items.count == 2)
    #expect(model.labels.map(\.id) == ["home"])
  }

  @Test func echoedValueWakesNoReader() {
    let model = AppModel(preferences: Preferences(defaults: defaults))
    var state = AppState()
    state.labels = [userLabel("work")]
    state.revisions.bump(.labels)
    model.apply(state)
    // The engine's echo of an edit the model already holds: the revision
    // moved, the value didn't.
    state.revisions.bump(.labels)
    #expect(!notifies({ _ = model.labels }, when: { model.apply(state) }))
  }

  @Test func sidebarBadgesFollowThePushes() {
    let model = AppModel(preferences: Preferences(defaults: defaults))
    var state = AppState()
    state.items = [item("acct:1", title: "One"), item("acct:2", title: "Two")]
    state.sidebar = .standard(catchAll: catchAllInboxId, builtins: [], labels: [])
    state.revisions.bump(.items)
    state.revisions.bump(.sidebar)
    model.apply(state)
    #expect(model.sidebarRows(for: nil).map(\.id) == [catchAllInboxId])
    #expect(model.unreadThreads(in: catchAllInboxId, account: nil) == 2)
    state.items[0].read = true
    state.revisions.bump(.items)
    model.apply(state)
    #expect(model.unreadThreads(in: catchAllInboxId, account: nil) == 1)
  }

  @Test func preferencesRoundTrip() {
    let preferences = Preferences(defaults: defaults)
    #expect(preferences.sidebarShown)
    #expect(preferences.notifyScope == .mentions)
    preferences.sidebarShown = false
    preferences.notifyScope = .all
    preferences.activityWindow = .week
    preferences.sidebarSelection = SidebarSelection(account: "acct", category: "work", board: nil)
    // Under the keys they have always had.
    #expect(defaults.values["sidebarHidden"] as? Bool == true)
    #expect(defaults.values["notifyScope"] as? String == "all")
    let reread = Preferences(defaults: defaults)
    #expect(!reread.sidebarShown)
    #expect(reread.notifyScope == .all)
    #expect(reread.activityWindow == .week)
    #expect(reread.sidebarSelection == SidebarSelection(account: "acct", category: "work", board: nil))
    reread.activityWindow = nil
    #expect(defaults.values["activityWindow"] == nil)
  }
}

/// What AppModel.apply and the toolbar's flicker rationale rest on: an
/// @Observable property tells its readers about an assignment only when
/// the value changed, for Equatable types (and identical objects). An
/// in-place mutation, or a type that isn't Equatable, always tells.
@Suite("Observation")
@MainActor
struct ObservationTests {
  @Observable
  final class Holder {
    var items: [String] = ["a"]
    var pair: (Int, Int) = (1, 2)
  }

  @Test func equalAssignmentTellsNoOne() {
    let holder = Holder()
    #expect(!notifies({ _ = holder.items }, when: { holder.items = ["a"] }))
    #expect(notifies({ _ = holder.items }, when: { holder.items = ["b"] }))
  }

  @Test func inPlaceMutationAlwaysTells() {
    let holder = Holder()
    #expect(notifies({ _ = holder.items }, when: { holder.items[0] = "a" }))
  }

  @Test func nonEquatableAlwaysTells() {
    let holder = Holder()
    #expect(notifies({ _ = holder.pair }, when: { holder.pair = (1, 2) }))
  }
}
