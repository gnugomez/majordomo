// Left column of the main window: the aggregated "All Inboxes" section on
// top (open by default), one collapsible section per connected account —
// headed by the provider's mark, its name, and the account's username — and
// the identity/settings row at the foot. Buckets and their wording come from
// each provider's spec.

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
    // The sidebar's foot: sync activity while it runs (the way Mail shows
    // "Downloading Messages"), and the account row — avatars + name, the way
    // into settings alongside ⌘, and the tray menu.
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

  @ViewBuilder
  private func categoryRows(account: AccountState?) -> some View {
    let items = account.map { scoped in model.items.filter { $0.accountId == scoped.id } } ?? model.items
    let specs = account.map { accountCategories(for: $0.provider) } ?? aggregatedCategories
    ForEach(categorize(items, into: specs).filter { !model.hiddenCategories.contains($0.id) }) { category in
      Label(category.label, systemImage: category.symbol)
        .badge(category.items.count { !$0.read })
        .tag(SidebarSelection(account: account?.id, category: category.id))
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
