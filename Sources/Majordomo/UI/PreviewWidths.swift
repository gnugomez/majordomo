// The widths the preview is left at, one for each place it stands in,
// kept in the defaults as the user drags them. Only the user's widths are
// kept: moving from one place to the other, the inspector holds the width
// it had there, and that width is the other place's, not this one's.

import CoreGraphics
import Foundation

@MainActor
final class PreviewWidths {
  private let store: any PreferenceStore

  init(store: any PreferenceStore = UserDefaults.standard) {
    self.store = store
  }

  /// The width the preview was last left at in `place`, kept within its
  /// range; the place's standard width while nothing is kept.
  func width(in place: PreviewPlace) -> CGFloat {
    guard let saved = store.object(forKey: place.widthKey) as? Double, saved > 0 else {
      return place.standardWidth
    }
    return min(max(saved, PreviewPlace.widths.lowerBound), PreviewPlace.widths.upperBound)
  }

  /// Keeps `width` as the width the preview is left at in `place`, unless
  /// it is no width at all or the other place's width.
  func note(_ width: CGFloat, in place: PreviewPlace) {
    guard width > 0, width != self.width(in: place.other) else {
      return
    }
    store.set(Double(width), forKey: place.widthKey)
  }
}
