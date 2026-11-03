// The toolbar's filter: what its set reads as, how switching it off and on
// decides what narrows — the inbox's set, a board's cards, the reads kept
// in place — and the counts its facet menus offer.

import Foundation
import Testing
@testable import Majordomo

@Suite("Toolbar filter")
@MainActor
struct InboxFilterTests {
  private let defaults = MemoryDefaults()

  private func freshModel() -> AppModel {
    AppModel(preferences: Preferences(defaults: defaults))
  }

  // MARK: The set in words

  @Test func summaryNamesThePicksThenUnreadThenTheWindow() {
    let filter = InboxFilter(
      unreadOnly: true, window: .week,
      picks: [.repository: "acme/app", .author: "mona", .provider: "github"]
    )
    #expect(filter.summary == "@mona, GitHub, acme/app, Unread, Last week")
    #expect(InboxFilter(unreadOnly: true).summary == "Unread")
  }

  @Test func anEmptySetSaysNothingAndNarrowsNothing() {
    #expect(InboxFilter().isEmpty)
    #expect(InboxFilter().summary.isEmpty)
    #expect(!InboxFilter(window: .month).isEmpty)
    #expect(!InboxFilter(picks: [.author: "mona"]).isEmpty)
  }

  // MARK: On and off

  @Test func anEditTurnsTheFilterOnAndSwitchingOffKeepsTheSet() {
    let model = freshModel()
    model.clearFilters()
    #expect(!model.filterEnabled)
    model.setFacet(.author, to: "mona")
    #expect(model.filterActive)
    #expect(model.narrowing.picks == [.author: "mona"])

    model.toggleFilter()
    #expect(!model.filterActive)
    #expect(model.narrowing.isEmpty)
    #expect(model.filter.picks == [.author: "mona"])

    model.toggleFilter()
    #expect(model.narrowing.picks == [.author: "mona"])
  }

  @Test func whileOffNothingOfTheSetNarrows() {
    let model = freshModel()
    model.setUnreadOnly(true)
    model.setActivityWindow(.week)
    model.setFacet(.repository, to: "acme/app")
    model.toggleFilter()
    #expect(model.narrowing == InboxFilter())
    #expect(model.filter == InboxFilter(unreadOnly: true, window: .week, picks: [.repository: "acme/app"]))
  }

  @Test func switchingOnWithNothingSetStartsWithUnreadOnly() {
    let model = freshModel()
    model.clearFilters()
    model.toggleFilter()
    #expect(model.filterActive)
    #expect(model.narrowing == InboxFilter(unreadOnly: true))
  }

  @Test func clearFiltersEmptiesTheSetAndSwitchesItOff() {
    let model = freshModel()
    model.setUnreadOnly(true)
    model.setActivityWindow(.twoDays)
    model.setFacet(.author, to: "mona")
    model.clearFilters()
    #expect(model.filter.isEmpty)
    #expect(!model.filterEnabled)
  }

  @Test func theSwitchOutlivesALaunchAndThePicksDoNot() {
    let model = freshModel()
    model.setUnreadOnly(true)
    model.setFacet(.author, to: "mona")
    model.toggleFilter()
    #expect(defaults.values["filterEnabled"] as? Bool == false)

    let relaunched = freshModel()
    #expect(!relaunched.filterEnabled)
    #expect(relaunched.unreadOnly)
    #expect(relaunched.facetPicks.isEmpty)
  }

  @Test func unsetTheSwitchReadsOnSoARememberedFilterKeepsNarrowing() {
    defaults.set(true, forKey: "unreadOnly")
    let model = freshModel()
    #expect(model.filterActive)
    #expect(model.narrowing.unreadOnly)
  }

  @Test func readsAreKeptInPlaceOnlyWhileTheFilterNarrowsToUnread() {
    let model = freshModel()
    model.setUnreadOnly(true)
    var state = AppState()
    state.items = [item("acct:1"), item("acct:2", title: "Another")]
    state.revisions.bump(.items)
    model.apply(state)

    state.items[0].read = true
    state.revisions.bump(.items)
    model.apply(state)
    #expect(model.keptReadIds == ["acct:1"])

    // Switching lets go of them, and while off nothing is held.
    model.toggleFilter()
    #expect(model.keptReadIds.isEmpty)
    state.items[1].read = true
    state.revisions.bump(.items)
    model.apply(state)
    #expect(model.keptReadIds.isEmpty)
  }

  @Test func aBoardNarrowsOnlyWhileTheFilterIsOn() {
    let model = freshModel()
    let board = Board(id: "b", name: "Work", symbol: "eye", columns: [])
    let unread = card("unread", items: [item("unread:1", read: false)])
    let read = card("read", items: [item("read:1", read: true)])
    var placed = BoardPlacement()
    placed.other = [unread, read]
    placed.record(unread)
    placed.record(read)
    var state = AppState()
    state.boards = [board]
    state.placements = ["b": placed]
    state.revisions.bump(.boards)
    state.revisions.bump(.placements)
    model.apply(state)

    model.setUnreadOnly(true)
    #expect(model.placement(of: board, filter: model.narrowing).allCards.map(\.id) == ["unread"])
    model.toggleFilter()
    #expect(model.placement(of: board, filter: model.narrowing).count == 2)
  }

  // MARK: The facet menus' counts

  @Test func facetValuesCountTheThreadsCarryingEach() {
    let threads = groupIntoThreads([
      item("acct:1", title: "One", author: "mona"),
      item("acct:2", title: "One", author: "kim"),
      item("acct:3", title: "Two", author: "mona"),
    ])
    #expect(facetValues(.author, in: threads, picked: nil) == [
      FacetValue(value: "kim", count: 1),
      FacetValue(value: "mona", count: 2),
    ])
  }

  @Test func facetValuesKeepAPickNothingCarriesAtNoRows() {
    let cards = [card("one", items: [item("one:1", author: "mona")])]
    #expect(facetValues(.author, in: cards, picked: "lin") == [
      FacetValue(value: "lin", count: 0),
      FacetValue(value: "mona", count: 1),
    ])
  }
}
