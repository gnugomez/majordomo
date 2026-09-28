// The Inboxes settings page: the sidebar's layout as a tree you arrange by
// dragging — inboxes and folders, in any order, at any depth — with a
// switch per inbox to keep it out of the sidebar without losing its place.
// Folders and the user's own inboxes (rule-fed buckets) are made and
// edited here, in the inspector under the tree; labels themselves live on
// the Labels page.

import SwiftUI

struct InboxesSettingsView: View {
  let model: AppModel

  @State private var selection: String?
  /// The folder just created, whose row name field takes focus.
  @State private var newFolder: String?
  /// The inbox just created, whose inspector name field takes focus.
  @State private var newInbox: String?
  /// The folder whose icon sheet is up.
  @State private var folderIconEditing: SidebarFolder?
  /// The inbox whose icon sheet is up.
  @State private var inboxIconEditing: InboxLabel?
  @State private var confirmRemoveInbox = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      SidebarOutlineView(
        entries: entries(for: model.sidebarLayout.nodes),
        selection: $selection,
        editingFolder: newFolder,
        onMove: { id, parent, index in
          model.updateSidebar { $0.move(node: id, toFolder: parent, at: index) }
        },
        onRename: { id, name in
          model.updateSidebar { $0.rename(folder: id, to: name) }
        },
        onSetVisible: { id, visible in
          model.updateSidebar { $0.setHidden(id, !visible) }
        }
      )
      .frame(height: 340)

      HStack(spacing: 8) {
        Button("New Folder") {
          addFolder()
        }
        Button("New Inbox") {
          addInbox()
        }
        .help("An inbox of your own, filled by rules — set them up on the Rules page")
      }
      .controlSize(.small)

      inspector
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .settingsCard()

      SettingsHint(text: "Drag to arrange the sidebar: reorder, move into or out of folders, nest folders. Switched-off inboxes keep their place and come back where they were. Recent is the catch-all and always stays first. The same layout serves All Inboxes and every account section.")
    }
    .padding(16)
    .sheet(item: $folderIconEditing) { folder in
      IconPickerSheet(name: folder.name, symbol: folder.symbol, tint: nil) { symbol, _ in
        model.updateSidebar { $0.setSymbol(folder: folder.id, symbol) }
      }
    }
    .sheet(item: $inboxIconEditing) { inbox in
      IconPickerSheet(label: inbox) { updated in
        replace(updated)
      }
    }
    .confirmationDialog(
      "Remove “\(selectedInbox?.name ?? "")”?",
      isPresented: $confirmRemoveInbox
    ) {
      Button("Remove", role: .destructive) {
        if let inbox = selectedInbox {
          model.setLabels(model.labels.filter { $0.id != inbox.id })
          selection = nil
        }
      }
    } message: {
      Text("It leaves the sidebar and every rule that fills it.")
    }
  }

  // MARK: Inspector

  /// What the selected row is, with the edits it allows: a folder's name
  /// and icon; a user inbox's name, icon, and notification policy; a label
  /// or a built-in only by name, with where it is edited.
  @ViewBuilder
  private var inspector: some View {
    if let folder = selectedFolder {
      FolderInspector(
        folder: folder,
        onRename: { name in model.updateSidebar { $0.rename(folder: folder.id, to: name) } },
        onChangeIcon: { folderIconEditing = folder },
        onRemove: {
          model.updateSidebar { $0.dissolve(folder: folder.id) }
          selection = nil
        }
      )
    } else if let inbox = selectedInbox {
      InboxInspector(
        inbox: inbox,
        startsEditing: newInbox == inbox.id,
        onChange: { updated in replace(updated) },
        onChangeIcon: { inboxIconEditing = inbox },
        onRemove: { confirmRemoveInbox = true }
      )
    } else if let selection, let label = model.label(selection) {
      HStack(spacing: 8) {
        LabelGlyph(symbol: label.symbol, tint: label.tint, size: 20)
        Text(label.name)
          .font(.system(size: 13, weight: .medium))
        Spacer()
        Text(label.isBuiltin ? "Built in" : "Edit it on the Labels page")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }
    } else if selection == catchAllInboxId {
      HStack(spacing: 8) {
        Image(systemName: recentCategory.symbol)
          .frame(width: 20)
        Text(recentCategory.label)
          .font(.system(size: 13, weight: .medium))
        Spacer()
        Text("Built in")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }
    } else {
      Text("Select a row to edit it")
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }
  }

  private var selectedFolder: SidebarFolder? {
    guard let selection, case .folder(let folder)? = model.sidebarLayout.node(selection) else {
      return nil
    }
    return folder
  }

  private var selectedInbox: InboxLabel? {
    selection.flatMap { id in model.userInboxes.first { $0.id == id } }
  }

  private func replace(_ updated: InboxLabel) {
    model.setLabels(model.labels.map { $0.id == updated.id ? updated : $0 })
  }

  private func addFolder() {
    let folder = SidebarFolder(id: UUID().uuidString, name: "New Folder")
    model.updateSidebar { $0.addFolder(folder) }
    selection = folder.id
    newFolder = folder.id
  }

  /// A new inbox joins the user's targets; the engine puts it at the top
  /// level of the sidebar.
  private func addInbox() {
    let inbox = InboxLabel(
      id: UUID().uuidString, name: "New Inbox", symbol: "tray", tint: .accent, notify: .follow,
      order: model.labels.count, kind: .inbox
    )
    model.setLabels(model.labels + [inbox])
    selection = inbox.id
    newInbox = inbox.id
  }

  /// The layout's nodes with each inbox's presentation looked up: the
  /// catch-all and the labels, as the aggregated sidebar names them.
  private func entries(for nodes: [SidebarNode]) -> [SidebarOutlineEntry] {
    let specs = Dictionary(
      uniqueKeysWithValues: categories(for: aggregatedLabels(user: model.labels)).map { ($0.id, $0) }
    )
    let layout = model.sidebarLayout
    return nodes.compactMap { node in
      switch node {
      case .inbox(let id):
        guard let spec = specs[id] else {
          return nil
        }
        return SidebarOutlineEntry(
          id: id, kind: .inbox, name: spec.label, symbol: spec.symbol,
          tint: spec.tint ?? .accent, hidden: !layout.isVisible(id), isCatchAll: id == catchAllInboxId
        )
      case .folder(let folder):
        return SidebarOutlineEntry(
          id: folder.id, kind: .folder, name: folder.name, symbol: folder.symbol,
          tint: .accent, hidden: false, isCatchAll: false, children: entries(for: folder.children)
        )
      }
    }
  }
}

/// A folder's edits: name, icon, and dissolving it (its contents move up).
private struct FolderInspector: View {
  let folder: SidebarFolder
  let onRename: (String) -> Void
  let onChangeIcon: () -> Void
  let onRemove: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: folder.symbol)
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
        .frame(width: 20)
      CommitTextField("Folder name", text: folder.name) { name in
        onRename(name.isEmpty ? "Folder" : name)
      }
      .textFieldStyle(.roundedBorder)
      Button("Change Icon…", action: onChangeIcon)
      Button("Remove Folder", action: onRemove)
        .help("Removes the folder; what it holds moves up a level")
    }
    .controlSize(.small)
  }
}

/// A user inbox's edits: name, icon and tint, notification policy, and
/// removal.
private struct InboxInspector: View {
  let inbox: InboxLabel
  let startsEditing: Bool
  let onChange: (InboxLabel) -> Void
  let onChangeIcon: () -> Void
  let onRemove: () -> Void

  @FocusState private var editingName: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        LabelGlyph(symbol: inbox.symbol, tint: inbox.tint, size: 20)
        CommitTextField("Inbox name", text: inbox.name) { name in
          var updated = inbox
          updated.name = name.isEmpty ? "Untitled" : name
          onChange(updated)
        }
        .textFieldStyle(.roundedBorder)
        .focused($editingName)
        Button("Change Icon…", action: onChangeIcon)
      }
      HStack(spacing: 8) {
        Text("Notify")
          .font(.system(size: 12))
        Picker(
          "Notify",
          selection: Binding(
            get: { inbox.notify },
            set: { policy in
              var updated = inbox
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
        Spacer()
        Button("Remove Inbox…", action: onRemove)
      }
    }
    .controlSize(.small)
    .onAppear {
      if startsEditing {
        editingName = true
      }
    }
  }
}
