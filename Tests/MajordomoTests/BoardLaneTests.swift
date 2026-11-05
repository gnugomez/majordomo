// Which lane a card rides in: its repository's or its owner's, the one
// lane of a board without lanes, or the unread lane above them all while
// the board gathers the unread — whatever the board splits the rest by.

import Testing
@testable import Majordomo

@Suite("Board lanes")
struct BoardLaneTests {
  private func board(_ lanes: BoardLanes, unreadLane: Bool = false) -> Board {
    Board(id: "b", name: "Work", symbol: "eye", columns: [], lanes: lanes, unreadLane: unreadLane)
  }

  private func card(repo: String, read: Bool) -> BoardCard {
    MajordomoTests.card("t", items: [item("t:1", repo: repo, read: read)])
  }

  @Test func lanesSplitByRepositoryOrOwner() {
    let read = card(repo: "acme/infra/deploy", read: true)
    #expect(board(.none).lane(for: read) == "")
    #expect(board(.repository).lane(for: read) == "acme/infra/deploy")
    // A nested group owns the project.
    #expect(board(.owner).lane(for: read) == "acme/infra")
  }

  @Test func unreadGatherAboveEveryLaneSetting() {
    let unread = card(repo: "acme/app", read: false)
    let read = card(repo: "acme/app", read: true)
    for lanes in BoardLanes.allCases {
      #expect(board(lanes, unreadLane: true).lane(for: unread) == Board.unreadLaneId)
      // The read keep to the lanes the board splits them by.
      #expect(board(lanes, unreadLane: true).lane(for: read) == board(lanes).lane(for: read))
    }
    // Without the unread lane, unread cards ride with the rest.
    #expect(board(.repository).lane(for: unread) == "acme/app")
  }

  @Test func oneUnreadNotificationMakesTheCardUnread() {
    let mixed = MajordomoTests.card("t", items: [
      item("t:1", repo: "acme/app", read: true),
      item("t:2", repo: "acme/app", read: false),
    ])
    #expect(board(.repository, unreadLane: true).lane(for: mixed) == Board.unreadLaneId)
  }
}
