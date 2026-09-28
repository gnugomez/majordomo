// Where the on-device model plugs in. Two jobs, both optional: turning a
// sentence into a rule, and judging the patterns Suggestion.swift mined.
// The protocol keeps the rest of the app honest — nothing here knows about
// FoundationModels, and with no model present every caller sees the same
// "unavailable" and carries on.

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
}

/// A failure fit for the UI, verbatim.
struct IntelligenceError: LocalizedError, Sendable {
  let message: String
  var errorDescription: String? { message }
}
