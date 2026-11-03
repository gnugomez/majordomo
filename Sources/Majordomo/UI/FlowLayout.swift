// Lays its pieces out left to right, starting a new line when the next one
// doesn't fit — a card's badges and a body's status badges wrap rather than
// truncate. Each piece takes its own ideal size; a line is as tall as its
// tallest piece, the others centered on it.

import SwiftUI

struct FlowLayout: Layout {
  /// Between two pieces on a line.
  var spacing: CGFloat
  /// Between two lines.
  var lineSpacing: CGFloat

  init(spacing: CGFloat, lineSpacing: CGFloat? = nil) {
    self.spacing = spacing
    self.lineSpacing = lineSpacing ?? spacing
  }

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
