// The main-actor side: a push is taken in slice by slice, by revision;
// the observation rules that makes worth it; and the preferences' one
// way in and out of their store.

import Foundation
import Observation
import Synchronization
import Testing
@testable import Majordomo

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

  @Test func snoozedItemsStayOutOfTheCounts() {
    let model = AppModel(preferences: Preferences(defaults: defaults))
    var state = AppState()
    var away = item("acct:2", mention: true)
    away.snoozedUntil = Date().addingTimeInterval(3600)
    state.items = [item("acct:1"), away]
    state.revisions.bump(.items)
    model.apply(state)
    #expect(model.unreadCount == 1)
    #expect(!model.unreadMentionDot)
    #expect(model.snoozedThreadCount == 1)
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
    #expect(model.sidebarRows.map(\.id) == [catchAllInboxId])
    #expect(model.unreadThreads(in: catchAllInboxId) == 2)
    state.items[0].read = true
    state.revisions.bump(.items)
    model.apply(state)
    #expect(model.unreadThreads(in: catchAllInboxId) == 1)
  }

  @Test func sidebarInboxesHoldEveryAccount() {
    let model = AppModel(preferences: Preferences(defaults: defaults))
    let builtins = model.catalog.builtinLabels.map(\.id)
    var fromGitHub = item("acct:1", reason: "mentioned", mention: true)
    fromGitHub.labels = ["mentions"]
    var fromGitLab = InboxItem(
      id: "lab:1", accountId: "lab", provider: .gitlab, kind: "merge", title: "Ship it", repo: "acme/api",
      url: "https://gitlab.example.com/acme/api/-/merge_requests/1", reason: "mentioned", isMention: true,
      updatedAt: referenceDate, read: false
    )
    fromGitLab.labels = ["mentions"]
    var state = AppState()
    state.items = [fromGitHub, fromGitLab]
    state.sidebar = .standard(catchAll: catchAllInboxId, builtins: builtins, labels: [])
    state.revisions.bump(.items)
    state.revisions.bump(.sidebar)
    model.apply(state)
    // One set of inboxes, the built-ins merged by id — no section per
    // account, and each inbox counts every account's threads.
    #expect(model.sidebarRows.map(\.id) == [catchAllInboxId] + builtins)
    #expect(model.unreadThreads(in: "mentions") == 2)
    #expect(model.unreadThreads(in: catchAllInboxId) == 2)
  }

  @Test func preferencesRoundTrip() {
    let preferences = Preferences(defaults: defaults)
    #expect(preferences.sidebarShown)
    #expect(preferences.notifyScope == .mentions)
    #expect(preferences.boardPreviewPlacement == .trailing)
    preferences.sidebarShown = false
    preferences.notifyScope = .all
    preferences.activityWindow = .week
    preferences.sidebarSelection = SidebarSelection(category: "work", board: "board-1")
    preferences.boardPreviewPlacement = .bottom
    // Under the keys they have always had.
    #expect(defaults.values["sidebarHidden"] as? Bool == true)
    #expect(defaults.values["notifyScope"] as? String == "all")
    #expect(defaults.values["sidebarCategory"] as? String == "work")
    #expect(defaults.values["sidebarBoard"] as? String == "board-1")
    #expect(defaults.values["boardPreviewPlacement"] as? String == "bottom")
    let reread = Preferences(defaults: defaults)
    #expect(!reread.sidebarShown)
    #expect(reread.notifyScope == .all)
    #expect(reread.activityWindow == .week)
    #expect(reread.sidebarSelection == SidebarSelection(category: "work", board: "board-1"))
    #expect(reread.boardPreviewPlacement == .bottom)
    reread.activityWindow = nil
    #expect(defaults.values["activityWindow"] == nil)
  }

  @Test func storedAccountSelectionOpensTheInboxAcrossAccounts() {
    // An inbox selected with an account stored beside it opens that same
    // inbox, holding every account's items.
    defaults.set("acct", forKey: "sidebarAccount")
    defaults.set("mentions", forKey: "sidebarCategory")
    let preferences = Preferences(defaults: defaults)
    #expect(preferences.sidebarSelection == SidebarSelection(category: "mentions"))
    let model = AppModel(preferences: preferences)
    var state = AppState()
    state.items = [item("acct:1")]
    state.accounts = [AccountState(id: "other", provider: .github)]
    state.revisions.bump(.items)
    state.revisions.bump(.accounts)
    model.apply(state)
    #expect(model.sidebarSelection == SidebarSelection(category: "mentions"))
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
