// Where the preview stands, as far as its width goes: beside the inbox
// list, which leaves it room to read in, or over a board, where it covers
// lanes and so opens narrower. Every board shares one width.

import CoreGraphics
import Foundation

enum PreviewPlace: Equatable, Sendable {
  case inbox
  case board

  init(onBoard: Bool) {
    self = onBoard ? .board : .inbox
  }

  /// How wide the preview may stand: from the narrowest a conversation
  /// still reads at to the widest it is worth.
  static let widths: ClosedRange<CGFloat> = 360 ... 900

  /// The other place.
  var other: PreviewPlace {
    self == .inbox ? .board : .inbox
  }

  /// The defaults key the width is kept under. The inbox's is the one
  /// the preview has always used, so a width left there carries over.
  var widthKey: String {
    switch self {
    case .inbox: "previewWidth"
    case .board: "boardPreviewWidth"
    }
  }

  /// The width the preview opens at the first time. A board's sits just
  /// over the floor: in the window's default size it leaves a board
  /// about one and a half lanes beside it, where the inbox's width
  /// would leave one and a third.
  var standardWidth: CGFloat {
    switch self {
    case .inbox: 420
    case .board: 380
    }
  }
}
