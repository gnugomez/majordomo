// Draws a provider's Glyph — SVG path data on a 16×16 grid — filled with
// the current foreground style, so it tints like a symbol. Each glyph is
// parsed once per run: a board draws the same handful on every card.

import SwiftUI
import Synchronization

private let parsedGlyphs = Mutex<[String: Path]>([:])

private func path(for glyph: Glyph) -> Path {
  parsedGlyphs.withLock { cache in
    if let held = cache[glyph.svg] {
      return held
    }
    let path = Path(SVGPath.parse(glyph.svg))
    cache[glyph.svg] = path
    return path
  }
}

struct GlyphImage: View {
  let glyph: Glyph
  /// The side of the square it is drawn in, in points.
  var size: CGFloat = 12

  var body: some View {
    GridShape(source: path(for: glyph))
      .fill(.foreground)
      .frame(width: size, height: size)
      // On a text baseline it sits the way a symbol does, its foot just
      // below the line.
      .alignmentGuide(.firstTextBaseline) { $0.height * 0.85 }
      .alignmentGuide(.lastTextBaseline) { $0.height * 0.85 }
  }
}
