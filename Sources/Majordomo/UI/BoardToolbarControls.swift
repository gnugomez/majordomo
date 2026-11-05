// The board's own toolbar control, its menu, in views of its own that read
// as little as they can: which board is up and its lanes. A toolbar item
// redraws with a fade, so one that read the cards or the selection would
// flicker on every click and every push; given only what decides how it
// looks, the menu redraws when that changes and not otherwise. The label
// and tooltip hold still for the same reason.

import SwiftUI

struct BoardToolbarControls: View {
  let model: AppModel

  var body: some View {
    if let board = model.selectedBoard {
      BoardMenu(model: model, boardId: board.id, lanes: board.lanes, unreadLane: board.unreadLane)
    }
  }
}

/// The board's own menu: lanes, the unread lane, and editing the board.
private struct BoardMenu: View {
  let model: AppModel
  let boardId: BoardId
  let lanes: BoardLanes
  let unreadLane: Bool

  var body: some View {
    Menu {
      Picker(
        "Lanes",
        selection: Binding(
          get: { lanes },
          set: { lanes in
            model.updateBoard(boardId) { $0.lanes = lanes }
          }
        )
      ) {
        Text("No Lanes").tag(BoardLanes.none)
        Text("Lanes by Repository").tag(BoardLanes.repository)
        Text("Lanes by Owner").tag(BoardLanes.owner)
      }
      .pickerStyle(.inline)
      Toggle(
        "Unread Lane",
        isOn: Binding(
          get: { unreadLane },
          set: { on in
            model.updateBoard(boardId) { $0.unreadLane = on }
          }
        )
      )
      Divider()
      Button("Edit Board…") {
        model.editingBoard = model.boards.first { $0.id == boardId }
      }
      Button("New Board…") {
        model.editingBoard = model.newBoard()
      }
    } label: {
      Label("Board", systemImage: "rectangle.split.3x1")
    }
    .menuIndicator(.hidden)
    .help("Lanes and board settings")
    // The toolbar builds the menu once and keeps it, its ticks where they
    // were; keyed by the lanes, a pick makes a fresh one.
    .id("\(lanes.rawValue) \(unreadLane)")
  }
}
