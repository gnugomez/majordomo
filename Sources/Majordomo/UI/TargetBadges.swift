// Where a target stands, drawn the same way wherever it shows: the
// provider's review, checks, and merge marks, led by one of the app's own
// when the target waits on the user's review. An inbox row draws them
// compact — a glyph each with its words in a tooltip, no taller than a
// line of the row's text, and only what needs doing once the row runs
// short of room. A board card and the preview draw them regular: glyph
// and word, each its own piece of the caller's flow so they wrap rather
// than truncate.

import SwiftUI

/// The facts a target's marks are drawn from, and nothing else: a view
/// handed one redraws when these change and at no other time.
struct TargetStatus: Equatable, Sendable {
  let provider: ProviderId
  /// The target's current state — newer than the one its notifications
  /// carried when they came.
  var state: String?
  var review: String?
  var checks: String?
  var merge: String?
  /// Whether one of the reviewers it still waits on is the user; never
  /// for a target that is done with.
  var awaitsYou: Bool

  /// `ownLogins` are the user's logins on the target's provider — the
  /// accounts its notifications came through.
  init(provider: ProviderId, snapshot: TargetSnapshot, ownLogins: [String]) {
    self.provider = provider
    state = snapshot.state
    review = snapshot.review
    checks = snapshot.checks
    merge = snapshot.merge
    let finished = snapshot.state.map(spec(for: provider).isFinished(state:)) ?? false
    awaitsYou = !finished && snapshot.reviewers.contains { reviewer in
      ownLogins.contains { reviewer.caseInsensitiveCompare($0) == .orderedSame }
    }
  }

  /// Whether the target is done with — merged, closed — by its provider's
  /// reckoning.
  var isFinished: Bool {
    state.map(spec(for: provider).isFinished(state:)) ?? false
  }

  /// The marks in reading order: the user's own review first, then where
  /// review, checks, and merging stand, as the provider draws them. While
  /// the target waits on the user, the review mark shows only when it asks
  /// for something of its own (changes requested): a plain "review
  /// required" beside "awaiting your review" says the same thing twice.
  var marks: [StatusMark] {
    let providerSpec = spec(for: provider)
    var marks: [StatusMark] = []
    if awaitsYou {
      marks.append(StatusMark(id: "you", badge: awaitingYourReview))
    }
    if let badge = review.flatMap(providerSpec.reviewBadge), !awaitsYou || badge.needsAction {
      marks.append(StatusMark(id: "review", badge: badge))
    }
    if let badge = checks.flatMap(providerSpec.checksBadge) {
      marks.append(StatusMark(id: "checks", badge: badge))
    }
    if let badge = merge.flatMap(providerSpec.mergeBadge) {
      marks.append(StatusMark(id: "merge", badge: badge))
    }
    return marks
  }

  /// The marks a row shows: none for a finished target — its state
  /// capsule says it all, and what its review or checks came to is
  /// history.
  var rowMarks: [StatusMark] {
    isFinished ? [] : marks
  }

  /// An item as its provider's presentation should read it now: the
  /// target's current state in place of the one the notification carried,
  /// so a pull request merged since reads merged.
  func presenting(_ item: InboxItem) -> InboxItem {
    guard let state else {
      return item
    }
    var item = item
    item.state = state
    return item
  }
}

/// The app's own mark, not a provider's: a review the user was asked for
/// and hasn't given. Reviewers and logins are the same plain names on
/// every provider, so nothing about it is a provider's to say.
private let awaitingYourReview = CardBadge(
  glyph: Octicon.codeReview, label: "Awaiting your review", color: .accentColor, needsAction: true
)

/// One mark, ready to draw.
struct StatusMark: Identifiable {
  /// What it speaks to: "you", "review", "checks", or "merge".
  let id: String
  let badge: CardBadge
}

/// How much room the marks take.
enum StatusDensity {
  /// Glyphs alone, their words in tooltips: an inbox row.
  case compact
  /// Glyph and word: a board card, the preview.
  case regular
}

struct TargetBadges: View {
  let status: TargetStatus
  var density: StatusDensity = .compact
  /// On a selected row the marks take the row's own style (RowStyle).
  var selected = false

  var body: some View {
    switch density {
    case .compact:
      compact
    case .regular:
      // Pieces of the caller's layout, one per mark, so its flow wraps
      // between them.
      ForEach(status.marks) { mark in
        wordMark(mark.badge)
      }
    }
  }

  /// A row's glyphs, fewer as the room shrinks: every mark, then only the
  /// marks that ask for something to be done, then the first of those.
  @ViewBuilder
  private var compact: some View {
    let marks = status.rowMarks
    let needed = marks.filter(\.badge.needsAction)
    ViewThatFits(in: .horizontal) {
      glyphs(marks)
      if needed.count < marks.count {
        glyphs(needed)
      }
      if needed.count > 1 {
        glyphs(Array(needed.prefix(1)))
      }
    }
  }

  private func glyphs(_ marks: [StatusMark]) -> some View {
    HStack(spacing: 4) {
      ForEach(marks) { mark in
        GlyphImage(glyph: mark.badge.glyph, size: 11)
          .foregroundStyle(mark.badge.color.onRow(selected: selected))
          .help(mark.badge.label)
          .accessibilityLabel(mark.badge.label)
      }
    }
    .fixedSize()
  }

  private func wordMark(_ badge: CardBadge) -> some View {
    HStack(spacing: 2) {
      GlyphImage(glyph: badge.glyph, size: 10)
      Text(badge.label)
    }
    .font(.app(.badge, weight: .medium))
    .foregroundStyle(badge.color)
    .lineLimit(1)
    .fixedSize()
  }
}
