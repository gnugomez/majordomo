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
      Text("The board and the cards you placed by hand go; the notifications stay in the inbox.")
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
      sectionTitle("Cards", caption: "Which issues and pull requests the board takes. With no conditions it takes them all.")
      RuleBox(rule: $draft.scope, accounts: model.accounts, emptyText: "Every card")
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
        Stepper(value: $draft.doneDays, in: 1 ... 90) {
          Text("Done keeps finished cards for \(draft.doneDays) \(draft.doneDays == 1 ? "day" : "days")")
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
        caption: "Read left to right: a card goes in the first column with a way in that holds. Open cards no column takes show under Other, finished ones under Done."
      )
      ForEach(Array(draft.columns.enumerated()), id: \.element.id) { index, column in
        ColumnEditor(
          column: column,
          accounts: model.accounts,
          canMoveLeft: index > 0,
          canMoveRight: index < draft.columns.count - 1,
          onChange: { draft.columns[index] = $0 },
          onMove: { offset in
            draft.columns.swapAt(index, index + offset)
          },
          onRemove: {
            draft.columns.remove(at: index)
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

/// One column: its name, its place among the others, and its ways in.
private struct ColumnEditor: View {
  let column: BoardColumn
  let accounts: [AccountState]
  let canMoveLeft: Bool
  let canMoveRight: Bool
  let onChange: (BoardColumn) -> Void
  let onMove: (Int) -> Void
  let onRemove: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        TextField("Column name", text: Binding(
          get: { column.name },
          set: { name in
            var updated = column
            updated.name = name
            onChange(updated)
          }
        ))
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
        Button {
          onRemove()
        } label: {
          Image(systemName: "trash")
        }
        .help("Remove this column")
      }
      .buttonStyle(.borderless)
      .controlSize(.small)

      if column.rules.isEmpty {
        Text("Filled by hand: no way in, so only the cards you drag here.")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }
      ForEach(Array(column.rules.enumerated()), id: \.offset) { index, rule in
        HStack(alignment: .top, spacing: 6) {
          if index > 0 {
            Text("or")
              .font(.system(size: 11, weight: .medium))
              .foregroundStyle(.secondary)
              .frame(width: 18)
              .padding(.top, 9)
          }
          RuleBox(
            rule: Binding(
              get: { rule },
              set: { changed in
                var updated = column
                updated.rules[index] = changed
                onChange(updated)
              }
            ),
            accounts: accounts,
            emptyText: "No conditions: matches nothing yet",
            onRemove: {
              var updated = column
              updated.rules.remove(at: index)
              onChange(updated)
            }
          )
        }
      }
      Button {
        var updated = column
        updated.rules.append(BoardRule(conditions: [RuleCondition(field: .assignee, op: .is, value: "@me")]))
        onChange(updated)
      } label: {
        Label(column.rules.isEmpty ? "Add a Way In" : "Add Another Way In", systemImage: "plus")
      }
      .buttonStyle(.borderless)
      .controlSize(.small)
    }
    .padding(12)
    .settingsCard()
  }
}

/// A set of conditions with its all-or-any switch, as a box of rows.
private struct RuleBox: View {
  @Binding var rule: BoardRule
  let accounts: [AccountState]
  let emptyText: String
  var onRemove: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Text("When")
        Picker("Match", selection: $rule.match) {
          Text("all").tag(RuleMatch.all)
          Text("any").tag(RuleMatch.any)
        }
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        Text("of these hold")
        Spacer()
        if let onRemove {
          Button {
            onRemove()
          } label: {
            Image(systemName: "xmark")
          }
          .buttonStyle(.borderless)
          .help("Remove this way in")
        }
      }
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(.secondary)
      ForEach(Array(rule.conditions.enumerated()), id: \.offset) { index, condition in
        ConditionRow(
          condition: condition,
          accounts: accounts,
          fields: RuleField.allCases,
          live: true,
          onChange: { rule.conditions[index] = $0 },
          onRemove: { rule.conditions.remove(at: index) }
        )
      }
      if rule.conditions.isEmpty {
        Text(emptyText)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
      Button {
        rule.conditions.append(RuleCondition(field: .repo))
      } label: {
        Label("Add Condition", systemImage: "plus")
      }
      .buttonStyle(.borderless)
      .controlSize(.small)
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
  }
}
