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

  // MARK: Picking and clearing

  @Test func aPickAppliesAtOnce() {
    let model = freshModel()
    model.clearFilters()
    model.setFacet(.author, to: "mona")
    #expect(model.filterActive)
    #expect(model.filter == InboxFilter(picks: [.author: "mona"]))
  }

  @Test func theGlyphWithNothingPickedFiltersToUnread() {
    let model = freshModel()
    model.clearFilters()
    model.toggleFilter()
    #expect(model.filter == InboxFilter(unreadOnly: true))
  }

  @Test func theGlyphWithAnythingPickedClearsEverything() {
    let model = freshModel()
    model.setUnreadOnly(true)
    model.setActivityWindow(.week)
    model.setFacet(.repository, to: "acme/app")
    model.toggleFilter()
    #expect(model.filter.isEmpty)
    #expect(!model.filterActive)
  }

  @Test func aPickClearedFromTheGlyphNeverComesBackWithTheNext() {
    // An author picked, the glyph clicked, then a date picked: the date
    // alone narrows — nothing held aside returns with it.
    let model = freshModel()
    model.clearFilters()
    model.setFacet(.author, to: "mona")
    model.toggleFilter()
    model.setActivityWindow(.twoDays)
    #expect(model.filter == InboxFilter(window: .twoDays))
  }

  @Test func clearFiltersEmptiesTheSet() {
    let model = freshModel()
    model.setUnreadOnly(true)
    model.setActivityWindow(.twoDays)
    model.setFacet(.author, to: "mona")
    model.clearFilters()
    #expect(model.filter.isEmpty)
  }

  @Test func unreadAndTheDateOutliveALaunchAndThePicksDoNot() {
    let model = freshModel()
    model.setUnreadOnly(true)
    model.setActivityWindow(.week)
    model.setFacet(.author, to: "mona")

    let relaunched = freshModel()
    #expect(relaunched.filter == InboxFilter(unreadOnly: true, window: .week))
    #expect(relaunched.facetPicks.isEmpty)
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

    // Clearing lets go of them, and without Unread Only nothing is held.
    model.toggleFilter()
    #expect(model.keptReadIds.isEmpty)
    state.items[1].read = true
    state.revisions.bump(.items)
    model.apply(state)
    #expect(model.keptReadIds.isEmpty)
  }

  @Test func aBoardNarrowsByWhatIsPicked() {
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
    #expect(model.placement(of: board, filter: model.filter).allCards.map(\.id) == ["unread"])
    model.toggleFilter()
    #expect(model.placement(of: board, filter: model.filter).count == 2)
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

  // MARK: The facets on offer

  @Test func providerIsOfferedOnlyAcrossProvidersOrWhilePicked() {
    #expect(offeredFacets(providers: [.github, .gitlab], picks: [:]) == [.author, .provider, .repository])
    // Two accounts on one provider: Provider would narrow nothing.
    #expect(offeredFacets(providers: [.gitlab], picks: [:]) == [.author, .repository])
    // A pick left behind by a removed account stays clearable.
    #expect(offeredFacets(providers: [.gitlab], picks: [.provider: "github"]) == [.author, .provider, .repository])
  }
}
