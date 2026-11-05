// The board editor, a sheet over the main window: the board's name and
// icon, which cards it takes, how it splits into lanes, and its columns —
// each with the ways a card gets in, made of the same conditions as the
// Rules page plus the fields only a target has (assignee, review, checks…).
// Everything edits a draft; Save hands back the whole board.

import SwiftUI

struct BoardEditorSheet: View {
  let model: AppModel

  @Environment(\.dismiss) private var dismiss
  @State private var draft: Board
  @State private var pickingIcon = false
  @State private var confirmDelete = false

  init(model: AppModel, board: Board) {
    self.model = model
    _draft = State(initialValue: board)
  }

  private var isNew: Bool {
    !model.boards.contains { $0.id == draft.id }
  }

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          header
          scopeSection
          layoutSection
          columnsSection
        }
        .padding(20)
      }
      Divider()
      footer
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
    .frame(width: 660, height: 640)
    .sheet(isPresented: $pickingIcon) {
      IconPickerSheet(name: draft.name, symbol: draft.symbol, tint: nil) { symbol, _ in
        draft.symbol = symbol
      }
    }
    .confirmationDialog("Delete \u{201C}\(draft.name)\u{201D}?", isPresented: $confirmDelete) {
      Button("Delete Board", role: .destructive) {
        model.deleteBoard(draft.id)
        dismiss()
      }
    } message: {
      Text("The board and its hand placements go; the notifications stay in the inbox.")
    }
  }

  // MARK: Sections

  private var header: some View {
    HStack(spacing: 10) {
      Button {
        pickingIcon = true
      } label: {
        Image(systemName: draft.symbol)
          .font(.system(size: 18))
          .frame(width: 34, height: 34)
          .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
      }
      .buttonStyle(.plain)
      .help("Choose an icon")
      TextField("Board name", text: $draft.name)
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 15, weight: .medium))
    }
  }

  private var scopeSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      sectionTitle("Items", caption: "Which items the board takes. With no conditions it takes them all.")
      FilterEditor(
        filter: $draft.scope,
        accounts: model.accounts,
        fields: RuleField.cardFields,
        live: true,
        newCondition: RuleCondition(field: .repo),
        emptyText: "Every item",
        questionHint: questionHint(model, subject: "item")
      )
      .padding(8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .settingsCard()
    }
  }

  private var layoutSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      sectionTitle("Layout", caption: nil)
      HStack(spacing: 16) {
        Picker("Lanes", selection: $draft.lanes) {
          Text("None").tag(BoardLanes.none)
          Text("By repository").tag(BoardLanes.repository)
          Text("By owner").tag(BoardLanes.owner)
        }
        .fixedSize()
        Toggle("Unread lane", isOn: $draft.unreadLane)
          .help("Gathers unread items in a lane of their own, above the rest")
        Stepper(value: $draft.doneDays, in: 1 ... 90) {
          Text("Done keeps finished items for \(draft.doneDays) \(draft.doneDays == 1 ? "day" : "days")")
        }
      }
      .controlSize(.small)
      .font(.system(size: 12))
    }
  }

  private var columnsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      sectionTitle(
        "Columns",
        caption: "Read left to right: an item goes in the first column whose conditions hold. Open items no column takes show under Other, finished ones under Done."
      )
      ForEach($draft.columns) { $column in
        let index = draft.columns.firstIndex { $0.id == column.id } ?? 0
        ColumnEditor(
          column: $column,
          accounts: model.accounts,
          questionHint: questionHint(model, subject: "item"),
          canMoveLeft: index > 0,
          canMoveRight: index < draft.columns.count - 1,
          onMove: { offset in
            draft.columns.swapAt(index, index + offset)
          },
          onRemove: {
            draft.columns.removeAll { $0.id == column.id }
          }
        )
      }
      Button {
        draft.columns.append(BoardColumn(id: UUID().uuidString, name: "New Column"))
      } label: {
        Label("Add Column", systemImage: "plus")
      }
      .controlSize(.small)
    }
  }

  private var footer: some View {
    HStack {
      if !isNew {
        Button("Delete Board…", role: .destructive) {
          confirmDelete = true
        }
      }
      Spacer()
      Button("Cancel", role: .cancel) {
        dismiss()
      }
      .keyboardShortcut(.cancelAction)
      Button(isNew ? "Add Board" : "Save") {
        var board = draft
        let name = board.name.trimmingCharacters(in: .whitespacesAndNewlines)
        board.name = name.isEmpty ? "Board" : name
        model.saveBoard(board)
        dismiss()
      }
      .buttonStyle(.borderedProminent)
      .keyboardShortcut(.defaultAction)
    }
  }

  private func sectionTitle(_ title: String, caption: String?) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.system(size: 13, weight: .semibold))
      if let caption {
        Text(caption)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

/// One column: its name, its place among the others, and the filter that
/// fills it — its groups the ways a card gets in.
private struct ColumnEditor: View {
  @Binding var column: BoardColumn
  let accounts: [AccountState]
  let questionHint: String
  let canMoveLeft: Bool
  let canMoveRight: Bool
  let onMove: (Int) -> Void
  let onRemove: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        TextField("Column name", text: $column.name)
          .textFieldStyle(.roundedBorder)
          .font(.system(size: 13, weight: .medium))
          .frame(maxWidth: 240)
        Spacer()
        Button {
          onMove(-1)
        } label: {
          Image(systemName: "arrow.left")
        }
        .disabled(!canMoveLeft)
        .help("Move left: it is tried earlier")
        Button {
          onMove(1)
        } label: {
          Image(systemName: "arrow.right")
        }
        .disabled(!canMoveRight)
        .help("Move right: it is tried later")
        Button(action: onRemove) {
          Image(systemName: "trash")
        }
        .help("Remove this column")
      }
      .buttonStyle(.borderless)
      .controlSize(.small)

      FilterEditor(
        filter: $column.filter,
        accounts: accounts,
        fields: RuleField.cardFields,
        live: true,
        newCondition: RuleCondition(field: .assignee, op: .is, value: "@me"),
        emptyText: "Filled by hand: no conditions, so only the items you drag here.",
        questionHint: questionHint
      )
    }
    .padding(12)
    .settingsCard()
  }
}
