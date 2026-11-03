// The rule composer: a sentence into a rule the app will actually run,
// and storing what the user confirms.

import Foundation

extension SyncEngine {
  /// A sentence into a rule the app will actually run: the model drafts,
  /// `RuleDraft.validated` checks, and only then does anything reach the
  /// store. Returns the rule and the target it would create, for the user
  /// to confirm — nothing is saved here.
  func composeRule(from text: String) async -> Result<ValidatedRule, IntelligenceError> {
    guard intelligenceEnabled else {
      return .failure(IntelligenceError(message: "Apple Intelligence features are switched off in Settings."))
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return .failure(IntelligenceError(message: "Describe the rule you want in a sentence."))
    }
    do {
      let draft = try await intelligence.composeRule(from: trimmed, labels: store.labels())
      switch draft.validated(against: store.labels()) {
      case .success(let validated):
        return .success(validated)
      case .failure(let error):
        return .failure(IntelligenceError(message: error.localizedDescription))
      }
    } catch {
      let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
      return .failure(IntelligenceError(message: message))
    }
  }

  /// Stores a composed or accepted rule: its new target first, so the rule
  /// has something to point at, then the rule — swept like any rule edit,
  /// so the inbox reflects it at once.
  func applyRule(_ validated: ValidatedRule) {
    if let target = validated.newTarget {
      store.setLabels(store.labels() + [target])
    }
    store.setRules(store.rules() + [validated.rule])
    record([.labels, .rules])
  }
}
