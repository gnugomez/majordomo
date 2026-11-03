// What the on-device model's background passes share — the summaries,
// the verdicts, and the suggestions: a budget per pass, one pass of a kind
// out at a time, a request that arrives while one is out runs another once
// it lands, and what the model wouldn't do this run is remembered so later
// passes don't spend their budget on it again.

/// The model's background jobs.
enum ModelJob: CaseIterable, Hashable, Sendable {
  /// The rows' one-line summaries.
  case summaries
  /// Answers to the questions rules and boards ask.
  case verdicts
  /// Labels and rules worth suggesting.
  case suggestions

  /// What one pass takes on at most. Each answer is a model round trip of
  /// a second or two, so a pass takes what is in front of the user first
  /// and leaves the rest to the next one.
  var budget: Int {
    switch self {
    case .summaries: 8
    case .verdicts: 8
    case .suggestions: suggestionCandidateBudget
    }
  }
}

/// One job's bookkeeping between passes.
struct ModelPass {
  /// True while a pass is out with the model.
  private(set) var running = false
  /// Asked for again while running.
  private var wanted = false
  /// What the model wouldn't do this run — a guardrail refusal or a
  /// hiccup — by the job's own key. Forgotten at relaunch; retrying them
  /// on every pass would spend the budget on the same failures.
  var failures: Set<String> = []

  /// Takes the job for a pass; when one is already out, notes that
  /// another is wanted once it lands, and returns false.
  mutating func begin() -> Bool {
    guard !running else {
      wanted = true
      return false
    }
    running = true
    return true
  }

  /// Whether another pass was asked for while this one ran; the job stays
  /// taken for it.
  mutating func takeRequest() -> Bool {
    defer {
      wanted = false
    }
    return wanted
  }

  /// Gives the job back.
  mutating func end() {
    running = false
    wanted = false
  }
}
