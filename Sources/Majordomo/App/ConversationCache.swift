// The conversations the preview reads: the most recent few held in memory,
// so looking back at one is instant and nothing builds up over a long
// session, and the asks ahead of the refresh rounds for a target they
// haven't reached yet.

import Foundation
import Observation

/// Conversations held at most.
private let conversationCacheLimit = 40

@MainActor
@Observable
final class ConversationCache {
  /// Where an item's target's conversation stands, as the preview shows it.
  enum Load: Sendable {
    /// Not in yet: the background refresh hasn't reached it, and the
    /// preview asked for it ahead of the rounds.
    case fetching
    case loaded(TargetConversation)
    /// The provider won't show the target; why, fit to show verbatim.
    case unreadable(String)
    /// The ask ahead of the rounds came back empty; why, fit to show. The
    /// rounds go on asking.
    case waiting(String)
  }

  /// A stored conversation read for the preview, and the activity it is
  /// current as of.
  private struct Held {
    let at: Date
    let conversation: TargetConversation
  }

  /// Conversations read, by target key — the most recent
  /// `conversationCacheLimit` of them.
  private var held: [String: Held] = [:]
  @ObservationIgnored private var order: [String] = []
  /// Why an ask ahead of the rounds came back empty, by target key.
  private var failures: [String: String] = [:]
  /// Targets an ask ahead of the rounds is out for.
  @ObservationIgnored private var fetching: Set<String> = []

  /// The conversation of the target at `key`, as the preview shows it; nil
  /// while a stored one is on its way from disk.
  func load(_ key: String, target: TrackedTarget?) -> Load? {
    if let at = target?.conversationAt {
      guard let conversation = held[key], conversation.at == at else {
        return nil
      }
      return .loaded(conversation.conversation)
    }
    if let reason = target?.unreadable {
      return .unreadable(reason)
    }
    if let failure = failures[key] {
      return .waiting(failure)
    }
    return .fetching
  }

  /// Reads the target's stored conversation, or, when the background
  /// refresh hasn't brought it yet, asks for it ahead of the rounds. An
  /// ask cancelled because the selection moved on leaves nothing behind.
  func fetch(_ key: String, target: TrackedTarget?, from engine: SyncEngine) async {
    if let at = target?.conversationAt {
      guard held[key]?.at != at else {
        return
      }
      if let conversation = await engine.conversation(for: key) {
        hold(key, Held(at: at, conversation: conversation))
      }
      return
    }
    guard target?.unreadable == nil, !fetching.contains(key) else {
      return
    }
    fetching.insert(key)
    defer { fetching.remove(key) }
    if failures[key] != nil {
      failures[key] = nil
    }
    let failure = await engine.refreshConversation(key)
    if let failure, !Task.isCancelled {
      failures[key] = failure
    }
  }

  /// Keeps a conversation read, letting go of the oldest beyond the limit.
  private func hold(_ key: String, _ conversation: Held) {
    held[key] = conversation
    order.removeAll { $0 == key }
    order.append(key)
    while order.count > conversationCacheLimit {
      held[order.removeFirst()] = nil
    }
  }
}
