// The Labels settings page: the user's labels (tags, not inboxes) as an
// editable list — glyph, name, notification policy, and whether the label
// shows as an inbox in the sidebar — with add/remove and the icon sheet.
// Where a label sits in the sidebar is the Inboxes page's business; the
// user's own inboxes and the providers' built-in ones live there. Every edit commits
// the whole list through the model (which re-sweeps items and rewrites the
// store), so names commit on submit or blur, never per keystroke.

import SwiftUI

/// The notification policy in the words the settings use.
func notifyPolicyLabel(_ policy: LabelNotifyPolicy) -> String {
  switch policy {
  case .follow: "Follow settings"
  case .always: "Always notify"
  case .urgent: "Urgent (time-sensitive)"
  case .never: "Never notify"
  }
}

/// A label's notification policy as a pop-up — a label's or a user
/// inbox's; a pick hands the label back changed.
struct NotifyPolicyPicker: View {
  let label: InboxLabel
  let onChange: (InboxLabel) -> Void

  var body: some View {
    Picker(
      "Notify",
      selection: Binding(
        get: { label.notify },
        set: { policy in
          var updated = label
          updated.notify = policy
          onChange(updated)
        }
      )
    ) {
      ForEach(LabelNotifyPolicy.allCases, id: \.self) { policy in
        Text(notifyPolicyLabel(policy)).tag(policy)
      }
    }
    .labelsHidden()
    .fixedSize()
  }
}

struct LabelsSettingsView: View {
  let model: AppModel

  @State private var selection: LabelId?
  /// The label whose icon sheet is up.
  @State private var iconEditing: InboxLabel?
  @State private var confirmRemove = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      List(selection: $selection) {
        ForEach(model.userLabels) { label in
          LabelSettingsRow(
            label: label,
            shownAsInbox: model.sidebarLayout.isVisible(label.id),
            onChange: { updated in replace(updated) },
            onShowAsInbox: { shown in
              model.updateSidebar { $0.setHidden(label.id, !shown) }
            }
          )
          .tag(label.id)
        }
      }
      .listStyle(.bordered)
      .frame(height: 260)
      .emptyListNote("No labels yet", when: model.userLabels.isEmpty)

      HStack(spacing: 8) {
        AddRemoveButtons(
          addHelp: "Add a label",
          removeHelp: "Remove the selected label",
          canRemove: selected != nil,
          onAdd: add,
          onRemove: { confirmRemove = true }
        )
        Button("Change Icon…") {
          iconEditing = selected
        }
        .controlSize(.small)
        .disabled(selected == nil)
      }
      SettingsHint(text: "A label shown as an inbox is a folder in the sidebar, holding the items that carry it; arrange it among the other inboxes on the Inboxes page. Its notification policy decides how those items reach Notification Center — when an item has several labels, the strongest policy wins.")
    }
    .padding(16)
    .sheet(item: $iconEditing) { label in
      IconPickerSheet(label: label) { updated in
        replace(updated)
      }
    }
    .confirmationDialog(
      "Remove “\(selected?.name ?? "")”?",
      isPresented: $confirmRemove
    ) {
      Button("Remove", role: .destructive) {
        remove()
      }
    } message: {
      Text("It leaves every item that carries it and every rule that applies it.")
    }
  }

  private var selected: InboxLabel? {
    selection.flatMap { id in model.userLabels.first { $0.id == id } }
  }

  private func replace(_ updated: InboxLabel) {
    model.setLabels(model.labels.map { $0.id == updated.id ? updated : $0 })
  }

  /// A new label joins the end of the list; the engine puts it in the
  /// sidebar's Labels folder.
  private func add() {
    let label = InboxLabel(
      id: UUID().uuidString, name: "New Label", symbol: "tag", tint: .blue, notify: .follow,
      order: model.labels.count
    )
    model.setLabels(model.labels + [label])
    selection = label.id
  }

  private func remove() {
    guard let selection else {
      return
    }
    model.setLabels(model.labels.filter { $0.id != selection })
    self.selection = nil
  }
}

/// One label row: glyph, name, notification policy, and the show-as-inbox
/// switch.
private struct LabelSettingsRow: View {
  let label: InboxLabel
  let shownAsInbox: Bool
  let onChange: (InboxLabel) -> Void
  let onShowAsInbox: (Bool) -> Void

  var body: some View {
    HStack(spacing: 10) {
      LabelGlyph(symbol: label.symbol, tint: label.tint)
      CommitTextField("Name", text: label.name) { name in
        var updated = label
        updated.name = name.isEmpty ? "Untitled" : name
        onChange(updated)
      }
      .textFieldStyle(.plain)
      .font(.app(.body, weight: .medium))
      Spacer()
      NotifyPolicyPicker(label: label, onChange: onChange)
        .controlSize(.small)
      SettingsSwitch("Show as inbox", isOn: Binding(get: { shownAsInbox }, set: { onShowAsInbox($0) }))
        .help("Show as an inbox in the sidebar")
    }
    .padding(.vertical, 2)
  }
}
