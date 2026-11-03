// Where an arrow key takes the selection on a board. The board as drawn —
// lanes top to bottom, each a row of cells, one per column — reduced to
// card ids, so the walk is plain arithmetic: up and down run through a
// column, on into the same column of the lane above or below; left and
// right cross to the nearest card in the next column of the lane that
// holds one. Edges stop; nothing wraps.

import Foundation

/// One arrow key's way across a board.
enum BoardMove: Sendable {
  case up
  case down
  case left
  case right
}

/// Where the keys left the selection: the card, and the row it aims for in
/// a column. A sideways move keeps the aim rather than taking the row it
/// lands on, so crossing to a shorter column and back returns to the card
/// it started from.
struct BoardCursor: Equatable, Sendable {
  let card: String
  let aim: Int
}

/// The cards of a board as drawn, by id, for the arrow keys to walk.
struct BoardGrid: Sendable {
  /// One lane: its cells, one per column, left to right, each holding the
  /// cards it draws, top to bottom. A board without lanes is one lane.
  struct Lane: Sendable {
    let id: String
    let cells: [[String]]
  }

  let lanes: [Lane]
  /// Lanes folded away: they draw no cards, so the keys pass them by.
  let collapsed: Set<String>

  /// Where one card sits among the lanes the keys can reach.
  private struct Spot {
    let lane: Int
    let column: Int
    let row: Int
  }

  /// Where `move` takes the selection from `card`, aiming for `aim` (the
  /// card's own row when nil) on a sideways move. With no card, or one the
  /// board no longer draws, any move lands on the first card, top left.
  /// nil at an edge, or on a board with nothing to select.
  func step(_ move: BoardMove, from card: String?, aim: Int? = nil) -> BoardCursor? {
    let rows = lanes.filter { !collapsed.contains($0.id) }.map(\.cells)
    guard let card, let spot = spot(of: card, in: rows) else {
      return first(in: rows)
    }
    switch move {
    case .up:
      return vertical(from: spot, in: rows, lanes: stride(from: spot.lane - 1, through: 0, by: -1), forward: false)
    case .down:
      return vertical(from: spot, in: rows, lanes: stride(from: spot.lane + 1, to: rows.count, by: 1), forward: true)
    case .left:
      return sideways(from: spot, in: rows, columns: stride(from: spot.column - 1, through: 0, by: -1), aim: aim)
    case .right:
      let count = rows[spot.lane].count
      return sideways(from: spot, in: rows, columns: stride(from: spot.column + 1, to: count, by: 1), aim: aim)
    }
  }

  /// The next card up or down the column: within the cell while it lasts,
  /// then the nearest end of the same column's cell in the next lane that
  /// draws one.
  private func vertical(
    from spot: Spot,
    in rows: [[[String]]],
    lanes: some Sequence<Int>,
    forward: Bool
  ) -> BoardCursor? {
    let here = cell(rows, spot.lane, spot.column)
    let next = spot.row + (forward ? 1 : -1)
    if here.indices.contains(next) {
      return BoardCursor(card: here[next], aim: next)
    }
    for lane in lanes {
      let cell = cell(rows, lane, spot.column)
      if !cell.isEmpty {
        let row = forward ? 0 : cell.count - 1
        return BoardCursor(card: cell[row], aim: row)
      }
    }
    return nil
  }

  /// The card nearest the aimed-for row in the next column of this lane
  /// that holds any.
  private func sideways(
    from spot: Spot,
    in rows: [[[String]]],
    columns: some Sequence<Int>,
    aim: Int?
  ) -> BoardCursor? {
    let aim = aim ?? spot.row
    for column in columns {
      let cell = cell(rows, spot.lane, column)
      if !cell.isEmpty {
        return BoardCursor(card: cell[min(aim, cell.count - 1)], aim: aim)
      }
    }
    return nil
  }

  private func first(in rows: [[[String]]]) -> BoardCursor? {
    for lane in rows {
      if let card = lane.first(where: { !$0.isEmpty })?.first {
        return BoardCursor(card: card, aim: 0)
      }
    }
    return nil
  }

  private func spot(of card: String, in rows: [[[String]]]) -> Spot? {
    for (lane, cells) in rows.enumerated() {
      for (column, cell) in cells.enumerated() {
        if let row = cell.firstIndex(of: card) {
          return Spot(lane: lane, column: column, row: row)
        }
      }
    }
    return nil
  }

  /// A lane's cell, or none past the lane's last column.
  private func cell(_ rows: [[[String]]], _ lane: Int, _ column: Int) -> [String] {
    rows[lane].indices.contains(column) ? rows[lane][column] : []
  }
}
