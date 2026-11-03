// The images a body shows. A picture fits the column at most, keeps its
// shape, and stays at the width the body asks for when that is smaller; a
// gray box holds its place while it loads, and a compact line naming it
// with a way to the browser stands in when it can't be had. A click opens
// it in the browser. Status badges sit in a row at text height. Pictures
// come through the environment's BodyImageSource; without one, every
// image is that line.

import SwiftUI

/// A body's images standing together: badges in a wrapping row, pictures
/// one under another.
struct MarkdownImageGroup: View {
  let images: [MarkdownImage]

  var body: some View {
    let badges = images.filter(\.isBadge)
    let pictures = images.filter { !$0.isBadge }
    VStack(alignment: .leading, spacing: 8) {
      if !badges.isEmpty {
        WrappingRow(spacing: 4) {
          ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
            MarkdownBadge(image: badge)
          }
        }
      }
      ForEach(Array(pictures.enumerated()), id: \.offset) { _, picture in
        MarkdownImageView(image: picture)
      }
    }
  }
}

/// The step widths are asked for in, so a pane resized a point at a time
/// doesn't ask again at every step.
private let pixelStep: CGFloat = 256

struct MarkdownImageView: View {
  let image: MarkdownImage

  @Environment(\.bodyImages) private var source
  @Environment(\.displayScale) private var displayScale
  @Environment(\.openURL) private var openURL
  /// The column's width, once laid out.
  @State private var columnWidth: CGFloat = 0
  @State private var loaded: BodyImage?
  @State private var failed = false

  private struct LoadKey: Equatable {
    let url: URL?
    let steps: Int
  }

  var body: some View {
    let url = source?.resolve(image.source)
    let pixels = wantedPixels
    content(url: url, shown: loaded ?? url.flatMap { source?.cachedImage(at: $0, pixelWidth: pixels) })
      .frame(maxWidth: .infinity, alignment: .leading)
      .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { columnWidth = $0 }
      .task(id: LoadKey(url: url, steps: Int((pixels / pixelStep).rounded(.up)))) {
        await load(url)
      }
  }

  /// The width it is drawn at, in pixels: the column, or less when the
  /// body asks for less.
  private var wantedPixels: CGFloat {
    min(columnWidth, image.width ?? .infinity) * displayScale
  }

  @ViewBuilder
  private func content(url: URL?, shown: BodyImage?) -> some View {
    if let shown {
      picture(shown, url: url)
    } else if failed || url == nil || source == nil {
      MarkdownImageFallback(image: image, url: url)
    } else {
      placeholder
    }
  }

  private func picture(_ shown: BodyImage, url: URL?) -> some View {
    let natural = shown.naturalSize
    return Image(nsImage: shown.image)
      .resizable()
      .interpolation(.high)
      .aspectRatio(natural.width / natural.height, contentMode: .fit)
      .frame(maxWidth: image.width ?? natural.width)
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator, lineWidth: 0.5))
      .contentShape(Rectangle())
      .onTapGesture {
        if let url {
          openURL(url)
        }
      }
      .pointerStyle(.link)
      .help(image.alt.isEmpty ? "Open the image in the browser" : image.alt)
      .accessibilityLabel(image.alt.isEmpty ? "Image" : image.alt)
      .contextMenu {
        if let url {
          Button("Open Image in Browser") {
            openURL(url)
          }
          Button("Copy Image Address") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
          }
        }
      }
  }

  /// A box of the image's size when the body gives it, a modest one
  /// otherwise.
  private var placeholder: some View {
    let width = min(image.width ?? .infinity, columnWidth > 0 ? columnWidth : .infinity)
    var height: CGFloat = 120
    if let asked = image.width, let tall = image.height, width.isFinite {
      height = width * tall / asked
    }
    return RoundedRectangle(cornerRadius: 6)
      .fill(ConversationShades.code)
      .frame(maxWidth: image.width ?? .infinity)
      .frame(height: height)
      .overlay {
        ProgressView()
          .controlSize(.small)
      }
  }

  private func load(_ url: URL?) async {
    guard let source, let url else {
      failed = true
      return
    }
    guard columnWidth > 0 else {
      return
    }
    let pixels = wantedPixels
    if let loaded, loaded.covers(Int(pixels)) {
      return
    }
    if let picture = await source.image(at: url, pixelWidth: pixels) {
      loaded = picture
      failed = false
    } else if loaded == nil, !Task.isCancelled {
      failed = true
    }
  }
}

/// A status badge, at text height.
private struct MarkdownBadge: View {
  let image: MarkdownImage

  @Environment(\.bodyImages) private var source
  @Environment(\.displayScale) private var displayScale
  @State private var loaded: BodyImage?
  @State private var failed = false

  private let height: CGFloat = 20

  var body: some View {
    let url = source?.resolve(image.source)
    Group {
      if let loaded {
        Image(nsImage: loaded.image)
          .resizable()
          .interpolation(.high)
          .aspectRatio(loaded.naturalSize.width / loaded.naturalSize.height, contentMode: .fit)
          .frame(height: height)
          .help(image.alt)
          .accessibilityLabel(image.alt)
      } else if failed || url == nil {
        CapsuleTag(text: image.alt.isEmpty ? "badge" : image.alt)
      } else {
        Capsule()
          .fill(ConversationShades.code)
          .frame(width: 60, height: height)
      }
    }
    .task(id: url) {
      guard let source, let url else {
        failed = true
        return
      }
      loaded = await source.image(at: url, pixelWidth: 240 * displayScale)
      failed = loaded == nil
    }
  }
}

/// What stands in for an image that can't be shown: its name, and the
/// browser.
private struct MarkdownImageFallback: View {
  let image: MarkdownImage
  let url: URL?

  @Environment(\.openURL) private var openURL

  var body: some View {
    HStack(spacing: 6) {
      Group {
        Image(systemName: "photo")
        Text(image.alt.isEmpty ? "Image" : image.alt)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .foregroundStyle(.secondary)
      if let url {
        Text("·")
          .foregroundStyle(.tertiary)
        Button("Open in Browser") {
          openURL(url)
        }
        .buttonStyle(.link)
        .help(url.absoluteString)
      }
    }
    .font(.system(size: 12))
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(ConversationShades.code, in: RoundedRectangle(cornerRadius: 6))
  }
}

/// Lays its pieces out left to right, starting a new line when the next
/// one doesn't fit.
private struct WrappingRow: Layout {
  var spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let lines = arrange(subviews, width: proposal.width ?? .infinity)
    let width = lines.map(\.width).max() ?? 0
    let height = lines.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, lines.count - 1))
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
      y += line.height + spacing
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
