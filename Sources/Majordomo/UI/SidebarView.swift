// Left column of the main window: the inboxes on top (open by default),
// then the user's boards. Every inbox holds every account's notifications;
// the toolbar's filter narrows to one provider's, so the sidebar keeps no
// section per account. Buckets come from the providers' specs, merged by
// id; the user's label folders sit nested under one collapsible "Labels"
// node after them, in their own tints. The foot carries what needs saying
// and nothing else: an account in trouble, while it is, and sync activity
// while it runs. Settings have ⌘, the tray menu and the rows' own menus.

import SwiftUI

struct SidebarView: View {
  let model: AppModel
  @Binding var selection: SidebarSelection

  @AppStorage("sidebarAllExpanded") private var inboxesExpanded = true
  @AppStorage("sidebarBoardsExpanded") private var boardsExpanded = true

  var body: some View {
    List(selection: Binding<SidebarSelection?>(
      get: { selection },
      set: { selection = $0 ?? SidebarSelection(category: recentCategory.id) }
    )) {
      Section(isExpanded: $inboxesExpanded) {
        ForEach(model.sidebarRows) { row in
          SidebarRowView(row: row, model: model)
        }
        // What is put away, after the layout's rows: its badge counts the
        // threads waiting, not unread ones.
        Label(snoozedCategory.label, systemImage: snoozedCategory.symbol)
          .badge(model.snoozedThreadCount)
          .tag(SidebarSelection(category: snoozedInboxId))
      } header: {
        Text("Inboxes")
      }
      Section(isExpanded: $boardsExpanded) {
        boardRows
      } header: {
        Text("Boards")
      }
    }
    .listStyle(.sidebar)
    .safeAreaInset(edge: .bottom) {
      SidebarFoot(model: model)
    }
  }

  /// One row per board, badged with its cards that carry unread
  /// notifications — the board's version of an inbox's unread rows.
  @ViewBuilder
  private var boardRows: some View {
    // With every board deleted, the section offers a fresh one rather than
    // vanishing — nothing else in the window would.
    if model.boards.isEmpty {
      Button {
        model.editingBoard = model.newBoard()
      } label: {
        Label("New Board…", systemImage: "plus")
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .selectionDisabled()
    }
    ForEach(model.boards) { board in
      Label(board.name, systemImage: board.symbol)
        .badge(model.placement(of: board).unread)
        .tag(SidebarSelection(category: recentCategory.id, board: board.id))
        .contextMenu {
          Button("Edit Board…") {
            model.editingBoard = board
          }
          Button("New Board…") {
            model.editingBoard = model.newBoard()
          }
        }
    }
  }
}

/// The sidebar's foot: a row per account whose last sync or token check
/// failed, for as long as it stands, and sync activity while it runs. With
/// neither it is empty and leaves no furniture behind.
private struct SidebarFoot: View {
  let model: AppModel

  var body: some View {
    let troubled = model.accounts.filter { $0.error != nil }
    if !troubled.isEmpty || model.syncing {
      VStack(alignment: .leading, spacing: 8) {
        ForEach(troubled) { account in
          AccountTroubleRow(account: account, error: account.error ?? "") {
            model.openSettings?("Accounts")
          }
        }
        if model.syncing {
          VStack(spacing: 5) {
            ProgressView()
              .progressViewStyle(.linear)
              .controlSize(.small)
            Text("Syncing…")
              .font(.app(.caption))
              .foregroundStyle(.secondary)
          }
          .frame(maxWidth: .infinity)
        }
      }
      .padding(.horizontal, 14)
      .padding(.bottom, 10)
    }
  }
}

/// An account that can't sync, said quietly: a small orange triangle — the
/// one spot of color — then who the account is and the provider's own
/// words for what went wrong, in the foot's secondary text. A click opens
/// Settings on Accounts, where the error shows in full and the token is
/// replaced; the tooltip names the instance too. It stays until the account
/// works again: until then its notifications simply stop arriving.
private struct AccountTroubleRow: View {
  let account: AccountState
  let error: String
  let open: () -> Void

  var body: some View {
    Button(action: open) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.app(.caption))
          .foregroundStyle(.orange)
        VStack(alignment: .leading, spacing: 1) {
          Text(name)
            .font(.app(.caption, weight: .medium))
            .lineLimit(1)
          Text(error)
            .font(.app(.caption))
            .lineLimit(2)
        }
        .foregroundStyle(.secondary)
        Spacer(minLength: 0)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help("\(accountDescriptor(account))\n\(error)\nClick to open Settings → Accounts.")
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(accountDescriptor(account)) can't sync")
    .accessibilityValue(error)
    .accessibilityHint("Opens Settings on Accounts")
    .accessibilityAddTraits(.isButton)
  }

  /// `GitLab · @username`; the instance is left to the tooltip, which has
  /// the room.
  private var name: String {
    account.username.map { "\(account.provider.displayName) · @\($0)" } ?? account.provider.displayName
  }
}

/// One row of the layout: an inbox row, or a folder that draws its rows
/// inside a disclosure group — a struct, so the recursion has a type.
private struct SidebarRowView: View {
  let row: SidebarRow
  let model: AppModel

  /// An inactive window greys its source list out. A tint has to step
  /// aside for that: an explicit color knows nothing about the window's
  /// state, and a custom icon would stay lit while every built-in one next
  /// to it went quiet.
  @Environment(\.appearsActive) private var appearsActive

  var body: some View {
    switch row {
    case .inbox(let category):
      inboxRow(category)
    case .folder(let folder, let rows):
      SidebarFolderGroup(
        folder: folder,
        unreadCount: model.unreadThreads(in: folder.id),
        openSettings: { model.openSettings?("Inboxes") }
      ) {
        ForEach(rows) { child in
          SidebarRowView(row: child, model: model)
        }
      }
    }
  }

  private func inboxRow(_ category: Category) -> some View {
    Label {
      Text(category.label)
    } icon: {
      // A tinted label wears its tint while the window is active; the
      // accent (every built-in) is the sidebar's own glyph color and draws
      // like the catch-all. Dropping the tint is what greys it out — the
      // plain glyph follows the window the way the built-ins do.
      if let tint = category.spec.tint, appearsActive {
        Image(systemName: category.symbol)
          .foregroundStyle(tint.color)
      } else {
        Image(systemName: category.symbol)
      }
    }
    // Unread threads, not items — the badge matches the rows the list
    // will actually show.
    .badge(model.unreadThreads(in: category.id))
    .tag(SidebarSelection(category: category.id))
    .contextMenu {
      if category.spec.labelId != nil {
        Button("Edit Labels…") {
          model.openSettings?("Labels")
        }
      }
    }
  }
}

/// A folder of the layout: a disclosure group headed by the folder's own
/// glyph and name. Not an inbox — selection skips the header — but it
/// carries the unread count across what it holds. Expansion persists per
/// folder ("folderExpanded-all-<folderId>", "all" naming the inboxes'
/// section), open by default.
private struct SidebarFolderGroup<Rows: View>: View {
  let folder: SidebarFolder
  let unreadCount: Int
  let openSettings: () -> Void
  @ViewBuilder let rows: Rows

  @AppStorage private var expanded: Bool

  init(
    folder: SidebarFolder, unreadCount: Int, openSettings: @escaping () -> Void,
    @ViewBuilder rows: () -> Rows
  ) {
    self.folder = folder
    self.unreadCount = unreadCount
    self.openSettings = openSettings
    self.rows = rows()
    _expanded = AppStorage(wrappedValue: true, "folderExpanded-all-\(folder.id)")
  }

  var body: some View {
    DisclosureGroup(isExpanded: $expanded) {
      rows
    } label: {
      Label(folder.name, systemImage: folder.symbol)
        .badge(unreadCount)
        .contextMenu {
          Button("Edit Inboxes…") {
            openSettings()
          }
        }
        // Only the header row is unselectable — it is a group, not an
        // inbox. Placed on the label, not the group: on the group it would
        // cover the rows inside as well.
        .selectionDisabled()
    }
  }
}
