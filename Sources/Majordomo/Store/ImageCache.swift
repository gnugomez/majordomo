// The images previews have shown, as fetched, a file each under the app's
// Caches folder, keyed by address. A preview opened again draws its images
// without asking the network, and the folder stays within a size: past it,
// the images least recently drawn go first. The system may empty Caches
// at will, which only costs a fetch.

import CryptoKit
import Foundation
import os

private let log = Logger(subsystem: "dev.majordomo.app", category: "images")

/// What the folder may hold before the least recently used images go.
private let diskByteLimit = 150 * 1024 * 1024
/// What a trim brings the folder back down to, so the next few images
/// don't each set off another.
private let trimmedByteTarget = 120 * 1024 * 1024

actor ImageCache {
  /// The app's cache. Demo mode keeps nothing on disk: its images are
  /// fixtures already.
  static let shared = ImageCache(
    directory: isDemo ? nil : FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appending(path: "dev.majordomo.app/Images")
  )

  /// nil keeps nothing.
  private let directory: URL?
  /// What the folder holds, once measured.
  private var diskBytes: Int?

  init(directory: URL?) {
    self.directory = directory
  }

  /// The stored bytes for an address, marked as just used.
  func data(for url: URL) -> Data? {
    guard let file = file(for: url), let data = try? Data(contentsOf: file) else {
      return nil
    }
    try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
    return data
  }

  func store(_ data: Data, for url: URL) {
    guard let directory, let file = file(for: url) else {
      return
    }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try data.write(to: file, options: .atomic)
    } catch {
      log.error("failed to cache an image: \(error)")
      return
    }
    let total = (diskBytes ?? measure()) + data.count
    diskBytes = total > diskByteLimit ? trim() : total
  }

  /// An address as a file name: its digest, since an address can be any
  /// length and carry any character.
  private func file(for url: URL) -> URL? {
    guard let directory else {
      return nil
    }
    let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
    return directory.appending(path: digest.prefix(16).map { String(format: "%02x", $0) }.joined())
  }

  private func entries() -> [(url: URL, size: Int, used: Date)] {
    guard let directory,
          let urls = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
          ) else {
      return []
    }
    return urls.compactMap { url in
      let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
      return (url, values?.fileSize ?? 0, values?.contentModificationDate ?? .distantPast)
    }
  }

  private func measure() -> Int {
    entries().reduce(0) { $0 + $1.size }
  }

  /// Removes the least recently used images until the folder is back
  /// under `trimmedByteTarget`; returns what it holds after.
  private func trim() -> Int {
    var held = entries().sorted { $0.used < $1.used }
    var total = held.reduce(0) { $0 + $1.size }
    while total > trimmedByteTarget, !held.isEmpty {
      let oldest = held.removeFirst()
      try? FileManager.default.removeItem(at: oldest.url)
      total -= oldest.size
    }
    return total
  }
}
