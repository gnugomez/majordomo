// The targets' conversations, a file each in a folder beside the store.
// Together they run to megabytes — a maintainer's inbox points at
// thousands of targets, each with a description and its latest comments —
// and the store file is rewritten whole on every save, so they stay out of
// it and are read one at a time, when a preview asks for one.

import CryptoKit
import Foundation
import os

private let log = Logger(subsystem: "dev.majordomo.app", category: "conversations")

/// Not Sendable by design: owned by the Store, and through it by the
/// SyncEngine actor.
final class ConversationFiles {
  /// nil for the in-memory fixture store: conversations live in `memory`.
  private let directory: URL?
  private var memory: [String: TargetConversation] = [:]
  private let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()
  private let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()

  init(directory: URL?, seed: [String: TargetConversation] = [:]) {
    self.directory = directory
    memory = directory == nil ? seed : [:]
  }

  func read(_ key: String) -> TargetConversation? {
    guard let directory else {
      return memory[key]
    }
    guard let data = try? Data(contentsOf: directory.appending(path: fileName(key))) else {
      return nil
    }
    return try? decoder.decode(TargetConversation.self, from: data)
  }

  func write(_ conversation: TargetConversation, for key: String) {
    guard let directory else {
      memory[key] = conversation
      return
    }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try encoder.encode(conversation).write(to: directory.appending(path: fileName(key)), options: .atomic)
    } catch {
      log.error("failed to save a conversation: \(error)")
    }
  }

  /// Drops every conversation but those of `keys`.
  func keep(only keys: Set<String>) {
    guard let directory else {
      memory = memory.filter { keys.contains($0.key) }
      return
    }
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
      return
    }
    let kept = Set(keys.map(fileName))
    for name in names where !kept.contains(name) {
      try? FileManager.default.removeItem(at: directory.appending(path: name))
    }
  }

  /// A key as a file name: its digest, since a key is a url.
  private func fileName(_ key: String) -> String {
    let digest = SHA256.hash(data: Data(key.utf8))
    return digest.prefix(16).map { String(format: "%02x", $0) }.joined() + ".json"
  }
}
