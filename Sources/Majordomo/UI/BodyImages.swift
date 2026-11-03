// How a preview's bodies reach the images they show. The preview puts a
// BodyImageSource for the item it shows in the environment — where a
// source written in a body points, and a fetch through the account the
// item came through (AppModel.bodyImages) — so MarkdownBody and the
// avatars need nothing of the app model. Fetched bytes stay in ImageCache;
// decoded pictures stay in memory here, downsampled off the main actor to
// the width they are drawn at.

import AppKit
import ImageIO
import SwiftUI

struct BodyImageSource: Equatable, Sendable {
  /// What the source serves: equal keys resolve and fetch alike, so a
  /// redraw handing down a fresh copy changes nothing beneath it.
  let key: String
  /// A source as a body writes it, as the address it names; nil when it
  /// names nothing on the web.
  let resolve: @Sendable (String) -> URL?
  /// The bytes at an address; nil when they can't be had.
  let fetch: @Sendable (URL) async -> Data?

  static func == (lhs: BodyImageSource, rhs: BodyImageSource) -> Bool {
    lhs.key == rhs.key
  }

  /// The picture at an address, at least `pixelWidth` wide where the image
  /// is that large.
  @MainActor
  func image(at url: URL, pixelWidth: CGFloat) async -> BodyImage? {
    await BodyImageLoader.shared.image(at: url, pixelWidth: pixelWidth, fetch: fetch)
  }

  /// The picture when it is in memory already, so a view drawn again
  /// shows it at once.
  @MainActor
  func cachedImage(at url: URL, pixelWidth: CGFloat) -> BodyImage? {
    BodyImageLoader.shared.cached(url, pixelWidth: pixelWidth)
  }
}

extension EnvironmentValues {
  /// Where the bodies below get their images; nil leaves every image a
  /// link.
  @Entry var bodyImages: BodyImageSource? = nil
}

/// A decoded picture and the size the image has at full resolution, in
/// points — its own width is the widest it is drawn. Made and drawn on the
/// main actor only.
@MainActor
final class BodyImage {
  let image: NSImage
  let naturalSize: CGSize
  /// The width it was decoded at, in pixels; nil when it is the whole
  /// image (a vector image draws sharp at any size).
  let decodedWidth: Int?

  init(image: NSImage, naturalSize: CGSize, decodedWidth: Int?) {
    self.image = image
    self.naturalSize = naturalSize
    self.decodedWidth = decodedWidth
  }

  /// Whether it draws sharp `pixelWidth` wide.
  func covers(_ pixelWidth: Int) -> Bool {
    guard let decodedWidth else {
      return true
    }
    return decodedWidth >= min(pixelWidth, Int(naturalSize.width))
  }

  /// Roughly what it holds in memory, for the cache's budget.
  var cost: Int {
    Int(image.size.width * image.size.height) * 4
  }
}

/// Decoded pictures by address, one decode in flight per address and
/// width however many views show it, and recent failures, so a broken
/// image isn't fetched again on every look.
@MainActor
final class BodyImageLoader {
  static let shared = BodyImageLoader()

  private let decoded: NSCache<NSURL, BodyImage> = {
    let cache = NSCache<NSURL, BodyImage>()
    cache.totalCostLimit = 128 * 1024 * 1024
    return cache
  }()
  private var inFlight: [String: Task<BodyImage?, Never>] = [:]
  private var failedAt: [URL: Date] = [:]

  func cached(_ url: URL, pixelWidth: CGFloat) -> BodyImage? {
    guard let held = decoded.object(forKey: url as NSURL), held.covers(widthBucket(pixelWidth)) else {
      return nil
    }
    return held
  }

  func image(at url: URL, pixelWidth: CGFloat, fetch: @escaping @Sendable (URL) async -> Data?) async -> BodyImage? {
    let wanted = widthBucket(pixelWidth)
    if let held = decoded.object(forKey: url as NSURL), held.covers(wanted) {
      return held
    }
    if let failed = failedAt[url], Date().timeIntervalSince(failed) < 5 * 60 {
      return nil
    }
    let key = "\(wanted) \(url.absoluteString)"
    if let running = inFlight[key] {
      return await running.value
    }
    let task = Task<BodyImage?, Never> {
      let data: Data
      if let stored = await ImageCache.shared.data(for: url) {
        data = stored
      } else {
        guard let fetched = await fetch(url) else {
          return nil
        }
        await ImageCache.shared.store(fetched, for: url)
        data = fetched
      }
      return await decode(data, maxPixelWidth: wanted)
    }
    inFlight[key] = task
    let image = await task.value
    inFlight[key] = nil
    if let image {
      decoded.setObject(image, forKey: url as NSURL, cost: image.cost)
    } else {
      failedAt[url] = Date()
    }
    return image
  }

  /// Widths in steps, so a pane resized a point at a time doesn't decode
  /// again at every step.
  private func widthBucket(_ pixelWidth: CGFloat) -> Int {
    let step = 256
    let steps = Int((max(pixelWidth, 1) / CGFloat(step)).rounded(.up))
    return min(steps * step, 4096)
  }

  /// Bitmaps decode off the main actor, downsampled; a vector image
  /// (an SVG badge) ImageIO can't read draws through NSImage instead.
  private func decode(_ data: Data, maxPixelWidth: Int) async -> BodyImage? {
    let bitmap = await Task.detached(priority: .userInitiated) {
      DecodedBitmap(data: data, maxPixelWidth: maxPixelWidth)
    }.value
    if let bitmap {
      let image = NSImage(
        cgImage: bitmap.image, size: NSSize(width: bitmap.image.width, height: bitmap.image.height)
      )
      return BodyImage(
        image: image, naturalSize: bitmap.naturalSize,
        decodedWidth: bitmap.isWhole ? nil : bitmap.image.width
      )
    }
    guard let image = NSImage(data: data), image.isValid, image.size.width > 0, image.size.height > 0 else {
      return nil
    }
    return BodyImage(image: image, naturalSize: image.size, decodedWidth: nil)
  }
}

/// A bitmap decoded at most `maxPixelWidth` wide, turned upright. CGImage
/// is immutable, so handing one across actors is safe.
private struct DecodedBitmap: @unchecked Sendable {
  let image: CGImage
  /// The upright image's full size, in pixels, taken as points the way a
  /// web page draws an image.
  let naturalSize: CGSize
  /// Whether nothing was scaled away.
  let isWhole: Bool

  init?(data: Data, maxPixelWidth: Int) {
    guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
          CGImageSourceGetCount(source) > 0,
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
          let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int,
          pixelWidth > 0, pixelHeight > 0 else {
      return nil
    }
    // Orientations 5–8 turn the image on its side.
    let sideways = ((properties[kCGImagePropertyOrientation] as? Int) ?? 1) >= 5
    let width = sideways ? pixelHeight : pixelWidth
    let height = sideways ? pixelWidth : pixelHeight
    // The thumbnail's limit is on the longer side; scale it so the width
    // comes out at most what is wanted.
    let scale = min(1, Double(maxPixelWidth) / Double(width))
    let longest = Int((Double(max(width, height)) * scale).rounded(.up))
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: max(longest, 1),
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
      return nil
    }
    self.image = image
    naturalSize = CGSize(width: width, height: height)
    isWhole = scale >= 1
  }
}
