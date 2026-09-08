// Renders a provider's brand mark from the SVG path its spec declares —
// the glyphs SF Symbols can't stand in for. 16×16 viewBox, filled with the
// current foreground style.

import CoreGraphics
import SwiftUI

/// Parsed once per provider at startup, into SwiftUI's Sendable Path value.
private let markPaths: [ProviderId: Path] = Dictionary(
  uniqueKeysWithValues: providerSpecs.map { ($0.id, Path(SVGPath.parse($0.markSVGPath))) }
)

private struct SVGShape: Shape {
  let source: Path

  func path(in rect: CGRect) -> Path {
    let scale = min(rect.width, rect.height) / 16
    let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
      .scaledBy(x: scale, y: scale)
    return source.applying(transform)
  }
}

struct ProviderMark: View {
  let provider: ProviderId

  var body: some View {
    SVGShape(source: markPaths[provider] ?? Path())
      .fill(.foreground, style: FillStyle(eoFill: false))
      .aspectRatio(1, contentMode: .fit)
  }
}
