// Left column of the main window: the aggregated "All Inboxes" section on
// top (open by default), one collapsible section per connected account —
// headed by the provider's mark, its name, and the account's username — and
// the identity/settings row at the foot. Buckets and their wording come from
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
    // The sidebar's foot: sync activity while it runs, and the account row
    // — avatars + name, the way into settings alongside ⌘, and the tray
    // menu.
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 0) {
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
          .padding(.bottom, 6)
        }
        Button {
          model.openSettings?()
        } label: {
          HStack(spacing: 8) {
            if model.accounts.isEmpty {
              Image(systemName: "person.crop.circle")
                .font(.system(size: 19, weight: .light))
                .foregroundStyle(.secondary)
              Text("Connect an account")
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            } else {
              // The connected faces, stacked; a thin ring keeps overlapping
              // avatars legible against each other.
              HStack(spacing: -7) {
                ForEach(model.accounts) { account in
                  AccountAvatar(account: account, size: 22)
                    .overlay {
                      Circle().strokeBorder(.background, lineWidth: 1.5)
                    }
                }
              }
              Text(accountLabel)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            }
            Spacer(minLength: 0)
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .help(accountsHelp)
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
    let labels = account.map { accountLabels(for: $0.provider, user: model.labels) }
      ?? aggregatedLabels(user: model.labels)
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
  private var accountLabel: String {
    guard let first = model.accounts.first else {
      return ""
    }
    return first.name ?? first.username ?? first.provider.displayName
  }

  private var accountsHelp: String {
    let names = model.accounts.compactMap(\.username).map { "@\($0)" }
    return names.isEmpty ? "Settings" : "\(names.joined(separator: ", ")) — Settings"
  }
}


/// One row of the layout: an inbox row, or a folder that draws its rows
/// inside a disclosure group — a struct, so the recursion has a type.
private struct SidebarRowView: View {
  let row: SidebarRow
  let sectionKey: String
  let account: AccountState?
  let model: AppModel

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
      // A tinted label wears its tint; the accent (every built-in) is
      // the sidebar's own glyph color and draws like the catch-all.
      if let tint = category.spec.tint {
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
