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

private let cardBackground = Color(nsColor: NSColor(name: nil) { appearance in
  appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    ? NSColor(white: 0.2, alpha: 1)
    : .white
})

struct BoardCardView: View {
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
    .background(cardBackground, in: RoundedRectangle(cornerRadius: 9))
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
          LoginAvatar(login: login, provider: card.lead.provider, size: 18)
            .overlay(Circle().strokeBorder(cardBackground, lineWidth: 1.5))
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

/// Lays its pieces out left to right, starting a new line when the next
/// one doesn't fit — a card's badges wrap rather than truncate.
private struct FlowLayout: Layout {
  var spacing: CGFloat
  var lineSpacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let lines = arrange(subviews, width: proposal.width ?? .infinity)
    let width = lines.map(\.width).max() ?? 0
    let height = lines.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, lines.count - 1))
    return CGSize(width: width, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var y = bounds.minY
    for line in arrange(subviews, width: bounds.width) {
      var x = bounds.minX
      for index in line.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(at: CGPoint(x: x, y: y + (line.height - size.height) / 2), proposal: .unspecified)
        x += size.width + spacing
      }
      y += line.height + lineSpacing
    }
  }

  private struct Line {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func arrange(_ subviews: Subviews, width: CGFloat) -> [Line] {
    var lines: [Line] = []
    var line = Line()
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      let needed = line.indices.isEmpty ? size.width : line.width + spacing + size.width
      if needed > width, !line.indices.isEmpty {
        lines.append(line)
        line = Line()
      }
      line.width = line.indices.isEmpty ? size.width : line.width + spacing + size.width
      line.height = max(line.height, size.height)
      line.indices.append(index)
    }
    if !line.indices.isEmpty {
      lines.append(line)
    }
    return lines
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

/// A login's face: the provider's avatar where one can be derived from the
/// login alone, its initial in a steady color otherwise — and always in
/// demo mode, whose logins are made up. Faces come from AvatarImages, so a
/// card scrolled back into view doesn't fetch and decode its faces again.
struct LoginAvatar: View {
  let login: String
  let provider: ProviderId
  var size: CGFloat = 18

  @State private var loaded: NSImage?

  private var url: URL? {
    isDemo ? nil : spec(for: provider).fallbackAvatarURL(username: login)
  }

  var body: some View {
    Group {
      if let image = loaded ?? url.flatMap(AvatarImages.shared.cached) {
        Image(nsImage: image)
          .resizable()
          .scaledToFill()
      } else {
        Circle()
          .fill(tint)
          .overlay {
            Text(login.prefix(1).uppercased())
              .font(.system(size: size * 0.5, weight: .semibold))
              .foregroundStyle(.white)
          }
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .task(id: url) {
      if let url, AvatarImages.shared.cached(url) == nil {
        loaded = await AvatarImages.shared.load(url)
      }
    }
  }

  /// One color per login, the same on every launch (String's own hash is
  /// seeded per run).
  private var tint: Color {
    let palette: [LabelTint] = [.red, .orange, .green, .teal, .blue, .indigo, .purple, .pink, .brown]
    let sum = login.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    return palette[sum % palette.count].color.opacity(0.85)
  }
}

/// Avatars fetched once per run and held in memory, with one fetch in
/// flight per address however many cards show the same face.
@MainActor
final class AvatarImages {
  static let shared = AvatarImages()

  private let images = NSCache<NSURL, NSImage>()
  private var inFlight: [URL: Task<NSImage?, Never>] = [:]

  func cached(_ url: URL) -> NSImage? {
    images.object(forKey: url as NSURL)
  }

  func load(_ url: URL) async -> NSImage? {
    if let image = cached(url) {
      return image
    }
    if let running = inFlight[url] {
      return await running.value
    }
    let task = Task<NSImage?, Never> {
      guard let (data, _) = try? await providerSession.data(from: url) else {
        return nil
      }
      return NSImage(data: data)
    }
    inFlight[url] = task
    let image = await task.value
    inFlight[url] = nil
    if let image {
      images.setObject(image, forKey: url as NSURL)
    }
    return image
  }
}
