// Writes the store file off the engine's actor. A save is the costliest
// thing the store does — the file is rewritten whole, and a busy inbox
// makes it megabytes — so the store hands over a snapshot at most about
// once a second (the engine decides when; see SyncEngine.flushSoon), and
// the writer encodes and writes it on a queue of its own, in the order the
// snapshots were handed over.

import Foundation
import os

private let log = Logger(subsystem: "dev.majordomo.app", category: "store")

final class StoreWriter: Sendable {
  let fileURL: URL
  /// Serial: a later snapshot never lands before an earlier one.
  private let queue = DispatchQueue(label: "dev.majordomo.store-writer", qos: .utility)

  init(fileURL: URL) {
    self.fileURL = fileURL
  }

  /// Encodes and writes `file`, after every snapshot handed over before it.
  func write(_ file: StoreFile) {
    let url = fileURL
    queue.async {
      Self.save(file, to: url)
    }
  }

  /// Returns once every snapshot handed over so far is on disk.
  func drain() async {
    await withCheckedContinuation { continuation in
      queue.async {
        continuation.resume()
      }
    }
  }

  private static func save(_ file: StoreFile, to url: URL) {
    do {
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try encoder().encode(file).write(to: url, options: .atomic)
    } catch {
      log.error("failed to save store: \(error)")
    }
  }

  /// ISO 8601 dates, the format the store reads back (Store.decoder).
  static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(ISODate.format(date))
    }
    return encoder
  }
}
