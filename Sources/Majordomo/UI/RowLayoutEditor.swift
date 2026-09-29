// The inbox-row editor on the General settings page: which parts of a row
// show, and in what order. Each field carries a switch that keeps it out of
// sight without losing its place, and the list is dragged into the order
// the rows read in. A thread from the user's own inbox rides above it as a
// live sample, so an arrangement is judged on real notifications instead of
// described in words.

import SwiftUI

struct RowLayoutEditor: View {
  let model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Inbox rows")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)

      if let sample {
        ItemRowView(
          thread: sample,
          now: model.now,
          labels: labels(on: sample),
          layout: model.rowLayout
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 2)
        .settingsCard()
      }

      List {
        ForEach(model.rowLayout.order) { field in
          RowFieldRow(field: field, shown: model.rowLayout.shows(field)) { shown in
            model.setRowLayout(model.rowLayout.setting(field, shown: shown))
          }
        }
        .onMove { source, destination in
          model.setRowLayout(model.rowLayout.moving(fromOffsets: source, toOffset: destination))
        }
      }
      .listStyle(.bordered)
      .frame(height: 212)

      SettingsHint(text: "Drag to arrange what each row shows; switch off whatever you'd rather not see. Labels and the status capsule ride the right end of the line, so a field dragged behind them lands there too. The excerpt is a line of its own under the rest.")
    }
  }

  /// A thread to try the arrangement on — one with text to excerpt when
  /// the inbox holds one. Nothing to show before the first sync.
  private var sample: InboxThread? {
    let threads = groupIntoThreads(model.items)
    return threads.first { $0.lead.body != nil } ?? threads.first
  }

  /// The sample's labels, picked the way the list picks a row's.
  private func labels(on thread: InboxThread) -> [InboxLabel] {
    model.userLabels.filter { label in thread.items.contains { $0.labels.contains(label.id) } }
  }
}

/// One field's row: its switch and name, with what it stands for trailing.
private struct RowFieldRow: View {
  let field: RowField
  let shown: Bool
  let onChange: (Bool) -> Void

  var body: some View {
    HStack(spacing: 8) {
      Toggle(isOn: Binding(get: { shown }, set: { onChange($0) })) {
        Text(field.title)
          .font(.system(size: 13))
      }
      .toggleStyle(.checkbox)
      Spacer()
      Text(field.detail)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
    }
    .padding(.vertical, 2)
  }
}
