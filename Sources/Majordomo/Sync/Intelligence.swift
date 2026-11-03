// Where the on-device model plugs in. Four jobs, all optional: turning a
// sentence into a rule, judging the patterns Suggestion.swift mined,
// summarizing a notification's text for its inbox row, and answering a
// user's own yes-or-no question — an Apple Intelligence check in a rule or
// a board — about a notification or a board's card. The protocol keeps the
// rest of the app honest — nothing here knows about FoundationModels, and
// with no model present every caller sees the same "unavailable" and
// carries on.

import Foundation

/// Whether the on-device model can run here, with a settings-ready
/// explanation when it can't.
enum IntelligenceAvailability: Equatable, Sendable {
  case available
  case unavailable(String)

  var isAvailable: Bool {
    self == .available
  }

  var reason: String? {
    if case .unavailable(let reason) = self {
      return reason
    }
    return nil
  }
}

/// One notification to summarize, as the model sees it: its text, and the
/// little context that makes the summary read right. Provider tokens stay
/// out — the model is told what the item says, not what the platform calls
/// it.
struct SummaryRequest: Sendable {
  let title: String
  let repo: String
  let author: String?
  let body: String
}

/// One notification, or one card's target, put to an Apple Intelligence
/// check's question. The question is the user's, in their words; the rest
/// is what the notification — or the target's description — says.
struct VerdictRequest: Sendable {
  let question: String
  let title: String
  let repo: String
  let author: String?
  let body: String?
  /// The core's own "needs you" tier — not a provider token.
  let isMention: Bool
}

/// What the app asks a model to do. One implementation talks to Apple
/// Intelligence; the null one stands in wherever it can't run.
protocol IntelligenceProvider: Sendable {
  func availability() -> IntelligenceAvailability
  /// A sentence the user typed, plus the targets that already exist, into
  /// a draft rule. Throws a human-readable message.
  func composeRule(from text: String, labels: [InboxLabel]) async throws -> RuleDraft
  /// Whether a mined pattern deserves a label, and what to call it. nil
  /// means "not worth suggesting".
  func judge(_ candidate: SuggestionCandidate, labels: [InboxLabel]) async throws -> RuleDraft?
  /// A notification's text in one line, for the row to show under the
  /// title. Throws a human-readable message; the caller skips the item.
  func summarize(_ request: SummaryRequest) async throws -> String
  /// Whether the request's text answers its question yes. Throws a
  /// human-readable message, marked retryable when the model was only
  /// busy; the caller leaves the subject unanswered.
  func evaluate(_ request: VerdictRequest) async throws -> Bool
}

/// The stand-in when Apple Intelligence isn't available: it says so, and
/// never invents anything.
struct NoIntelligence: IntelligenceProvider {
  let reason: String

  func availability() -> IntelligenceAvailability {
    .unavailable(reason)
  }

  func composeRule(from text: String, labels: [InboxLabel]) async throws -> RuleDraft {
    throw IntelligenceError(message: reason)
  }

  func judge(_ candidate: SuggestionCandidate, labels: [InboxLabel]) async throws -> RuleDraft? {
    nil
  }

  func summarize(_ request: SummaryRequest) async throws -> String {
    throw IntelligenceError(message: reason)
  }

  func evaluate(_ request: VerdictRequest) async throws -> Bool {
    throw IntelligenceError(message: reason)
  }
}

/// A failure fit for the UI, verbatim.
struct IntelligenceError: LocalizedError, Sendable {
  let message: String
  /// The model was busy or not ready — nothing was said about the text,
  /// so asking again on a later pass is worth it.
  var retryable = false
  var errorDescription: String? { message }
}
