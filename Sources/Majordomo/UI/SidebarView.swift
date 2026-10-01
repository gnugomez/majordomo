// Left column of the main window: the aggregated "All Inboxes" section on
// top (open by default), one collapsible section per connected account —
// headed by the provider's mark, its name, and the account's username.
// Nothing sits at the foot but sync activity while it runs: a permanent
// account row says nothing the sections above don't, and settings have
// ⌘, the tray menu and the rows' own menus. Buckets and their wording come from
// each provider's spec; the user's label folders sit nested under one
// collapsible "Labels" node after them in every section, in their own
// tints.

import SwiftUI

struct SidebarView: View {
  let model: AppModel
  @Binding var selection: SidebarSelection

  @AppStorage("sidebarAllExpanded") private var allExpanded = true
  /// Account sections the user expanded (collapsed by default), as a CSV of
  /// account ids.
  @AppStorage("expandedAccountSections") private var expandedCSV = ""

  var body: some View {
    List(selection: Binding<SidebarSelection?>(
      get: { selection },
      set: { selection = $0 ?? SidebarSelection(account: nil, category: recentCategory.id) }
    )) {
      Section(isExpanded: $allExpanded) {
        categoryRows(account: nil)
      } header: {
        Text("All Inboxes")
      }
      ForEach(model.accounts) { account in
        Section(isExpanded: expansion(for: account.id)) {
          categoryRows(account: account)
        } header: {
          accountHeader(account)
        }
      }
    }
    .listStyle(.sidebar)
    // The sidebar's foot carries sync activity and nothing else: it shows
    // while a sync runs and leaves no furniture behind when it doesn't.
    // Settings open from ⌘, the tray menu, and the rows' own menus.
    .safeAreaInset(edge: .bottom) {
      if model.syncing {
        VStack(spacing: 5) {
          ProgressView()
            .progressViewStyle(.linear)
            .controlSize(.small)
          Text("Syncing…")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
      }
    }
  }

  /// `[mark] GitHub · @username`
  private func accountHeader(_ account: AccountState) -> some View {
    HStack(spacing: 5) {
      ProviderMark(provider: account.provider)
        .frame(width: 11, height: 11)
      Text("\(account.provider.displayName) · @\(account.username ?? "…")")
        .lineLimit(1)
    }
  }

  /// One section's rows, drawn from the sidebar layout: inboxes and
  /// folders in the user's order, hidden ones skipped.
  @ViewBuilder
  private func categoryRows(account: AccountState?) -> some View {
    let items = account.map { scoped in model.items.filter { $0.accountId == scoped.id } } ?? model.items
    let labels = model.catalog.sectionLabels(for: account?.provider)
    let rows = sidebarRows(layout: model.sidebarLayout, categories: categorize(items, into: categories(for: labels)))
    ForEach(rows) { row in
      SidebarRowView(row: row, sectionKey: account?.id ?? "all", account: account, model: model)
    }
  }

  private func expansion(for id: AccountId) -> Binding<Bool> {
    Binding(
      get: { expandedCSV.split(separator: ",").map(String.init).contains(id) },
      set: { expanded in
        var ids = Set(expandedCSV.split(separator: ",").map(String.init))
        if expanded {
          ids.insert(id)
        } else {
          ids.remove(id)
        }
        expandedCSV = ids.sorted().joined(separator: ",")
      }
    )
  }

  /// The primary identity's full name (username as fallback); the stacked
  /// avatars carry the rest.
}

/// One row of the layout: an inbox row, or a folder that draws its rows
/// inside a disclosure group — a struct, so the recursion has a type.
private struct SidebarRowView: View {
  let row: SidebarRow
  let sectionKey: String
  let account: AccountState?
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
        sectionKey: sectionKey,
        unreadCount: unreadThreadCount(in: rows),
        openSettings: { model.openSettings?() }
      ) {
        ForEach(rows) { child in
          SidebarRowView(row: child, sectionKey: sectionKey, account: account, model: model)
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
    .badge(groupIntoThreads(category.items).count { !$0.read })
    .tag(SidebarSelection(account: account?.id, category: category.id))
    .contextMenu {
      if category.spec.labelId != nil {
        Button("Edit Labels…") {
          model.openSettings?()
        }
      }
    }
  }
}

/// A folder of the layout: a disclosure group headed by the folder's own
/// glyph and name. Not an inbox — selection skips the header — but it
/// carries the unread count across what it holds. Expansion persists per
/// section and folder ("folderExpanded-<sectionKey>-<folderId>"), open by
/// default.
private struct SidebarFolderGroup<Rows: View>: View {
  let folder: SidebarFolder
  let unreadCount: Int
  let openSettings: () -> Void
  @ViewBuilder let rows: Rows

  @AppStorage private var expanded: Bool

  init(
    folder: SidebarFolder, sectionKey: String, unreadCount: Int, openSettings: @escaping () -> Void,
    @ViewBuilder rows: () -> Rows
  ) {
    self.folder = folder
    self.unreadCount = unreadCount
    self.openSettings = openSettings
    self.rows = rows()
    _expanded = AppStorage(wrappedValue: true, "folderExpanded-\(sectionKey)-\(folder.id)")
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
