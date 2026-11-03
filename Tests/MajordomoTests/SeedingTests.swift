import Foundation
import Testing

@testable import Majordomo

@Suite("Starter boards")
struct SeedingTests {
  private let first = Board(id: "first", name: "First", symbol: "eye", columns: [])
  private let later = Board(id: "later", name: "Later", symbol: "eye", columns: [])

  @Test func aNewStoreGetsEveryStarter() {
    let store = Store(fixture: StoreFile())
    store.seedBoards([first, later], firstSet: [first.id])
    #expect(store.boards().map(\.id) == ["first", "later"])
  }

  @Test func aStoreSeededAllAtOnceGetsOnlyTheStartersItLacks() {
    // Seeded before boards were tracked one by one, then the user deleted
    // the first set's board: it stays deleted, the later one arrives.
    var file = StoreFile()
    file.boardsSeeded = true
    let store = Store(fixture: file)
    store.seedBoards([first, later], firstSet: [first.id])
    #expect(store.boards().map(\.id) == ["later"])
  }

  @Test func aDeletedStarterStaysDeleted() {
    let store = Store(fixture: StoreFile())
    store.seedBoards([first, later], firstSet: [first.id])
    store.setBoards(store.boards().filter { $0.id != later.id })
    store.seedBoards([first, later], firstSet: [first.id])
    #expect(store.boards().map(\.id) == ["first"])
  }

  @Test func seedingTwiceAddsNothing() {
    let store = Store(fixture: StoreFile())
    store.seedBoards([first], firstSet: [first.id])
    store.seedBoards([first], firstSet: [first.id])
    #expect(store.boards().map(\.id) == ["first"])
  }

  @Test func theAppShipsTheReviewsBoard() {
    #expect(GitForgeBoards.starters.map(\.id).contains(GitForgeBoards.reviewsId))
    #expect(!GitForgeBoards.firstSet.contains(GitForgeBoards.reviewsId))
  }
}
