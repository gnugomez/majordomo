// One card on a board: a target at a glance. The kind glyph in its current
// state, where it lives, its title, where review, checks, and merging stand
// (TargetBadges, the marks the inbox rows draw too), who it is assigned to,
// and what moved since the user last looked — the unread dot for
// notifications, "+N" for comments. Every mark of the target's tokens comes
// from the provider's spec; a card that has gone quiet fades rather than
// leaves.

import SwiftUI

/// An open card with no activity for this long draws faded.
private let quietAfter: TimeInterval = 14 * 24 * 60 * 60

/// Upstream labels a card shows at most; the preview has the rest.
private let visibleLabels = 2

/// Equatable over what it draws, so a board redrawn for another card's
/// sake leaves this one alone.
struct BoardCardView: View, Equatable {
  let card: BoardCard
  let now: Date
  let selected: Bool
  /// True when the user put the card in its column by hand.
  let pinned: Bool
  /// False when the lanes already name the repository.
  let showsRepo: Bool

  var body: some View {
    let providerSpec = spec(for: card.lead.provider)
    let item = card.presentedItem
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 5) {
        GlyphImage(glyph: providerSpec.glyph(for: item))
          .foregroundStyle(providerSpec.color(for: item))
        locationLine(providerSpec)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .lineLimit(1)
        Spacer(minLength: 4)
        if pinned {
          GlyphImage(glyph: Octicon.pin, size: 10)
            .foregroundStyle(.tertiary)
            .help("Placed here by hand")
        }
        if card.unread {
          Circle()
            .fill(Color.accentColor)
            .frame(width: 7, height: 7)
            .help("Unread notifications")
        }
      }

      Text(card.title)
        .font(.system(size: 13, weight: .medium))
        .lineLimit(3)
        .fixedSize(horizontal: false, vertical: true)

      badges

      HStack(spacing: 6) {
        assignees
        Spacer(minLength: 4)
        comments
        Text(relativeTime(card.activityAt, now: now))
          .font(.system(size: 11))
          .foregroundStyle(.tertiary)
          .monospacedDigit()
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Palette.card, in: RoundedRectangle(cornerRadius: 9))
    .overlay {
      RoundedRectangle(cornerRadius: 9)
        .strokeBorder(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.separator), lineWidth: selected ? 2 : 0.5)
    }
    .opacity(isQuiet ? 0.72 : 1)
    .help(isQuiet ? "No activity in over two weeks" : "")
  }

  /// "acme/atlas #12 · mona", trimmed of what the lanes already say. The
  /// number is what names the card, so squeezed for room the repository
  /// shortens first, then the author, and the number never.
  private func locationLine(_ providerSpec: any ProviderSpec) -> some View {
    let reference = providerSpec.shortReference(for: card.lead)
    let author = card.snapshot?.author ?? card.lead.author
    return HStack(spacing: 4) {
      if showsRepo {
        Text(card.lead.repo)
          .truncationMode(.middle)
          .layoutPriority(0)
      }
      if let reference {
        Text(reference)
          .fixedSize()
          .layoutPriority(2)
      }
      if let author {
        Text(showsRepo || reference != nil ? "· \(author)" : author)
          .truncationMode(.tail)
          .layoutPriority(1)
      }
    }
  }

  /// Where the target stands, then its milestone and labels, wrapping.
  @ViewBuilder
  private var badges: some View {
    let snapshot = card.snapshot
    let status = snapshot.map {
      TargetStatus(provider: card.lead.provider, snapshot: $0, ownLogins: card.ownLogins)
    }
    let marked = status.map { !$0.marks.isEmpty } ?? false
    let labels = Array((snapshot?.labels ?? card.lead.upstreamLabels).prefix(visibleLabels))
    let milestone = snapshot?.milestone
    if marked || !labels.isEmpty || milestone != nil {
      FlowLayout(spacing: 4, lineSpacing: 4) {
        if let status {
          TargetBadges(status: status, density: .regular)
        }
        if let milestone {
          Label {
            Text(milestone)
          } icon: {
            GlyphImage(glyph: Octicon.milestone, size: 10)
          }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        ForEach(labels, id: \.self) { label in
          CapsuleTag(text: label)
        }
      }
      .labelStyle(CompactLabelStyle())
    }
  }

  /// Up to three faces; more fold into a count.
  @ViewBuilder
  private var assignees: some View {
    let logins = card.snapshot?.assignees ?? []
    if !logins.isEmpty {
      HStack(spacing: -4) {
        ForEach(logins.prefix(3), id: \.self) { login in
          PersonAvatar(login: login, avatarUrl: nil, provider: card.lead.provider, size: 18)
            .overlay(Circle().strokeBorder(Palette.card, lineWidth: 1.5))
        }
        if logins.count > 3 {
          Text("+\(logins.count - 3)")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.leading, 6)
        }
      }
      .help("Assigned to " + logins.joined(separator: ", "))
    }
  }

  @ViewBuilder
  private var comments: some View {
    if let count = card.snapshot?.commentCount, count > 0 {
      HStack(spacing: 2) {
        GlyphImage(glyph: Octicon.comment, size: 10)
        Text("\(count)")
          .font(.system(size: 11))
          .monospacedDigit()
        if let new = card.newComments {
          Text("+\(new)")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .help("\(new) new since you last looked")
        }
      }
      .foregroundStyle(.secondary)
    }
  }

  private var isQuiet: Bool {
    !BoardEngine.isFinished(card) && now.timeIntervalSince(card.activityAt) > quietAfter
  }
}

/// Glyph and title close together, at the badges' small size.
private struct CompactLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: 2) {
      configuration.icon
      configuration.title
    }
  }
}
