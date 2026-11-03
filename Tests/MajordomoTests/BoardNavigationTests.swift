// The arrow keys on a board: through a column and on across lanes, over
// to the nearest card of the next column that holds one, the first card
// when nothing is selected, and a stop at every edge.

import Testing
@testable import Majordomo

private func lane(_ id: String, _ cells: [String]...) -> BoardGrid.Lane {
  BoardGrid.Lane(id: id, cells: cells)
}

@Suite("Board navigation")
struct BoardNavigationTests {
  /// One lane: a tall first column, an empty one, a short one, and Done.
  private let flat = BoardGrid(lanes: [
    lane("", ["a1", "a2", "a3", "a4"], [], ["c1", "c2"], ["d1"]),
  ], collapsed: [])

  /// Three lanes over two columns; the middle one leaves the first empty.
  private let laned = BoardGrid(lanes: [
    lane("acme/atlas", ["x1", "x2"], ["y1"]),
    lane("acme/beacon", [], ["y2", "y3"]),
    lane("acme/comet", ["x3"], ["y4"]),
  ], collapsed: [])

  @Test func nothingSelectedStartsTopLeft() {
    for move in [BoardMove.up, .down, .left, .right] {
      #expect(flat.step(move, from: nil) == BoardCursor(card: "a1", aim: 0))
    }
    // The first lane's first column with a card, not the first column.
    let leading = BoardGrid(lanes: [lane("", [], ["b1"]), lane("z", ["z1"], [])], collapsed: [])
    #expect(leading.step(.down, from: nil)?.card == "b1")
  }

  @Test func aCardNoLongerDrawnStartsOver() {
    #expect(flat.step(.down, from: "gone")?.card == "a1")
  }

  @Test func nothingToSelectGoesNowhere() {
    let empty = BoardGrid(lanes: [lane("", [], [])], collapsed: [])
    #expect(empty.step(.down, from: nil) == nil)
    #expect(BoardGrid(lanes: [], collapsed: []).step(.right, from: nil) == nil)
  }

  @Test func upAndDownRunThroughTheColumn() {
    #expect(flat.step(.down, from: "a1") == BoardCursor(card: "a2", aim: 1))
    #expect(flat.step(.up, from: "a3") == BoardCursor(card: "a2", aim: 1))
  }

  @Test func edgesStop() {
    #expect(flat.step(.up, from: "a1") == nil)
    #expect(flat.step(.down, from: "a4") == nil)
    #expect(flat.step(.left, from: "a2") == nil)
    #expect(flat.step(.right, from: "d1") == nil)
    #expect(laned.step(.down, from: "y4") == nil)
    #expect(laned.step(.up, from: "y1") == nil)
  }

  @Test func sidewaysSkipsEmptyColumns() {
    #expect(flat.step(.right, from: "a1")?.card == "c1")
    #expect(flat.step(.left, from: "c1")?.card == "a1")
  }

  @Test func sidewaysLandsOnTheNearestRow() {
    #expect(flat.step(.right, from: "a2") == BoardCursor(card: "c2", aim: 1))
    // Past the shorter column's end, its last card.
    #expect(flat.step(.right, from: "a4") == BoardCursor(card: "c2", aim: 3))
  }

  @Test func acrossAndBackReturnsWhereItBegan() {
    let over = flat.step(.right, from: "a4")
    let further = flat.step(.right, from: over?.card, aim: over?.aim)
    #expect(further == BoardCursor(card: "d1", aim: 3))
    let back = flat.step(.left, from: further?.card, aim: further?.aim)
    let home = flat.step(.left, from: back?.card, aim: back?.aim)
    #expect(home == BoardCursor(card: "a4", aim: 3))
  }

  @Test func aMoveUpOrDownResetsTheAim() {
    let over = flat.step(.right, from: "a4")
    let up = flat.step(.up, from: over?.card, aim: over?.aim)
    #expect(up == BoardCursor(card: "c1", aim: 0))
    #expect(flat.step(.left, from: up?.card, aim: up?.aim)?.card == "a1")
  }

  @Test func downContinuesIntoTheLaneBelow() {
    #expect(laned.step(.down, from: "y1") == BoardCursor(card: "y2", aim: 0))
    #expect(laned.step(.down, from: "y3") == BoardCursor(card: "y4", aim: 0))
  }

  @Test func upContinuesAtTheFootOfTheLaneAbove() {
    #expect(laned.step(.up, from: "y4") == BoardCursor(card: "y3", aim: 1))
  }

  @Test func lanesWithAnEmptyCellArePassedBy() {
    #expect(laned.step(.down, from: "x2") == BoardCursor(card: "x3", aim: 0))
    #expect(laned.step(.up, from: "x3") == BoardCursor(card: "x2", aim: 1))
  }

  @Test func sidewaysStaysInItsLane() {
    // The middle lane's first column is empty: left from it is an edge,
    // not a jump into another lane.
    #expect(laned.step(.left, from: "y2") == nil)
    #expect(laned.step(.right, from: "x2") == BoardCursor(card: "y1", aim: 1))
  }

  @Test func collapsedLanesArePassedBy() {
    let folded = BoardGrid(lanes: laned.lanes, collapsed: ["acme/beacon"])
    #expect(folded.step(.down, from: "y1")?.card == "y4")
    #expect(folded.step(.up, from: "y4")?.card == "y1")
  }

  @Test func aCardInACollapsedLaneStartsOver() {
    let folded = BoardGrid(lanes: laned.lanes, collapsed: ["acme/atlas"])
    #expect(folded.step(.down, from: "x1")?.card == "y2")
  }
}
