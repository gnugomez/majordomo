// The on-device model's background passes — row summaries, answers to the
// rules' and boards' questions, and suggested labels — with the switches
// that govern them. What sets a pass off is the reaction table's call
// (EngineChange); how one runs is here, its bookkeeping in ModelPass.

import Foundation

/// The shortest gap between suggestion passes. Patterns build over days,
/// so asking the model more often than this would spend battery to be
/// told the same thing — and a deep sync's import must not set off a
/// burst of them.
private let suggestionSweepInterval: TimeInterval = 6 * 60 * 60

/// One question the model is asked about one item or one target, with
/// what the answer is filed against.
private struct VerdictAsk {
  enum Subject: Hashable {
    case item(String)
    case target(String)
  }

  let subject: Subject
  /// The question's key.
  let question: String
  let unread: Bool
  let activityAt: Date

  /// What a failure is remembered by.
  var failureKey: String {
    switch subject {
    case .item(let id): "item:\(id)|\(question)"
    case .target(let key): "target:\(key)|\(question)"
    }
  }
}

extension SyncEngine {
  // MARK: Provider and switches

  /// Installs the provider the app shell built (the real one needs
  /// FoundationModels, which the engine doesn't import).
  func setIntelligence(_ provider: any IntelligenceProvider) {
    intelligence = provider
  }

  func intelligenceAvailability() -> IntelligenceAvailability {
    intelligence.availability()
  }

  /// The on-device switches as the user left them, pushed once at launch:
  /// the engine's own defaults are only right for a first run.
  func setIntelligenceSwitches(intelligence: Bool, suggestions: Bool, summaries: Bool) {
    intelligenceEnabled = intelligence
    suggestionsEnabled = suggestions
    summariesEnabled = summaries
  }

  /// Turns every on-device feature off or on. Off, nothing is drafted and
  /// no pass runs; what was already suggested simply stops being offered
  /// (the app model's call), and the summaries already written stay on
  /// their rows. On, the model catches up at once.
  func setIntelligenceEnabled(_ enabled: Bool) {
    intelligenceEnabled = enabled
    if enabled {
      record(.intelligenceOn)
    }
  }

  /// Turns the row summaries on or off. Switching them on catches up at
  /// once — the alternative is a minute of rows that say nothing.
  func setSummariesEnabled(_ enabled: Bool) {
    guard enabled != summariesEnabled else {
      return
    }
    summariesEnabled = enabled
    if enabled {
      record(.summariesOn)
    }
  }

  /// Turns pattern-watching on or off. Switching it off stops the passes
  /// and hides what is pending (the app model's call), without forgetting
  /// the dismissals — on again and the same patterns stay quiet.
  func setSuggestionsEnabled(_ enabled: Bool) {
    suggestionsEnabled = enabled
  }

  // MARK: Passes

  /// Whether the model may run a job now: switched on, able to run here,
  /// and the job's own switch on.
  private func modelMayRun(_ job: ModelJob) -> Bool {
    guard intelligenceEnabled, intelligence.availability().isAvailable else {
      return false
    }
    switch job {
    case .summaries: return summariesEnabled
    case .verdicts: return true
    case .suggestions: return suggestionsEnabled
    }
  }

  /// Starts a pass of the job in the background — or, while one is out,
  /// has another follow it, so nothing asked for meanwhile waits for the
  /// next sync.
  func requestPass(_ job: ModelJob) {
    Task {
      await self.runPasses(job)
    }
  }

  private func runPasses(_ job: ModelJob) async {
    guard modelMayRun(job), passes[job, default: ModelPass()].begin() else {
      return
    }
    repeat {
      switch job {
      case .summaries: await summaryPass()
      case .verdicts: await verdictPass()
      case .suggestions: await suggestionPass()
      }
    } while passes[job, default: ModelPass()].takeRequest() && modelMayRun(job)
    passes[job, default: ModelPass()].end()
  }

  /// True when no suggestion pass has run yet, or the interval has passed.
  func suggestionSweepIsDue() -> Bool {
    guard let lastSuggestionSweepAt else {
      return true
    }
    return Date().timeIntervalSince(lastSuggestionSweepAt) >= suggestionSweepInterval
  }

  // MARK: Summaries

  /// Writes the missing row summaries, a budget's worth at a time, the
  /// rows in front of the user first.
  private func summaryPass() async {
    var written: [(itemId: String, summary: String, text: String)] = []
    let queue = store.itemsNeedingSummary(limit: ModelJob.summaries.budget)
      .filter { !passes[.summaries, default: ModelPass()].failures.contains($0.id) }
    for item in queue {
      guard let body = item.body else {
        continue
      }
      let request = SummaryRequest(
        title: item.title, repo: item.repo, author: item.author, body: body
      )
      guard let summary = try? await intelligence.summarize(request), !summary.isEmpty else {
        passes[.summaries, default: ModelPass()].failures.insert(item.id)
        continue
      }
      written.append((itemId: item.id, summary: summary, text: body))
    }
    // One push for the batch rather than one per answer: every push
    // re-lays the list out, and a pass that did it per answer kept the
    // window busy for as long as the model worked.
    guard !written.isEmpty else {
      return
    }
    store.setSummaries(written)
    // The cards carry their notifications, summaries and all.
    record(.summaries)
  }

  // MARK: Verdicts

  /// Answers what the last sweep found worth asking — the questions whose
  /// answers could move an item into a label or a card into a column — a
  /// budget's worth per pass across items and targets alike, newest
  /// unread first.
  private func verdictPass() async {
    let queue = verdictQueue()
    guard !queue.isEmpty else {
      return
    }
    var itemAnswers: [(id: String, question: String, matched: Bool, text: String)] = []
    var targetAnswers: [(key: String, question: String, matched: Bool, text: String)] = []
    for (ask, question) in queue {
      switch ask.subject {
      case .item(let id):
        guard let item = store.item(id) else {
          continue
        }
        let request = VerdictRequest(
          question: question, title: item.title, repo: item.repo, author: item.author,
          body: item.body, isMention: item.isMention
        )
        if let matched = await answer(request, for: ask) {
          itemAnswers.append((id: id, question: ask.question, matched: matched, text: item.judgedText))
        }
      case .target(let key):
        guard let card = swept.cards[key] else {
          continue
        }
        let text = judgedText(card)
        if let matched = await answer(verdictRequest(question, about: card), for: ask) {
          targetAnswers.append((key: key, question: ask.question, matched: matched, text: text))
        }
      }
    }
    // The answers only become labels and columns through the sweep: store
    // them, then let the reactions sweep and publish — once for the batch,
    // since both cost the whole collection.
    guard !itemAnswers.isEmpty || !targetAnswers.isEmpty else {
      return
    }
    store.setVerdicts(items: itemAnswers, targets: targetAnswers)
    var changes: Set<EngineChange> = []
    if !itemAnswers.isEmpty {
      changes.insert(.itemVerdicts)
    }
    if !targetAnswers.isEmpty {
      changes.insert(.targetVerdicts)
    }
    record(changes)
  }

  /// The model's answer, or nil. A failure is remembered for the rest of
  /// the run — unless the model was only busy, which says nothing about
  /// the text.
  private func answer(_ request: VerdictRequest, for ask: VerdictAsk) async -> Bool? {
    do {
      return try await intelligence.evaluate(request)
    } catch {
      if (error as? IntelligenceError)?.retryable != true {
        passes[.verdicts, default: ModelPass()].failures.insert(ask.failureKey)
      }
      return nil
    }
  }

  /// The next budget's worth of questions, with their wording: one queue
  /// across every question and subject, so neither a long backlog of
  /// notifications nor a board full of cards starves the other. Only what
  /// lacks a current answer is asked — never answered, or answered about
  /// text that has changed since.
  private func verdictQueue() -> [(ask: VerdictAsk, question: String)] {
    var asks: [VerdictAsk] = []
    for (id, keys) in swept.openItemQuestions {
      guard let item = store.item(id) else {
        continue
      }
      for key in keys {
        asks.append(VerdictAsk(subject: .item(id), question: key, unread: !item.read, activityAt: item.updatedAt))
      }
    }
    for (key, questions) in swept.openTargetQuestions {
      guard let card = swept.cards[key] else {
        continue
      }
      for question in questions {
        asks.append(VerdictAsk(subject: .target(key), question: question, unread: card.unread, activityAt: card.activityAt))
      }
    }
    let failures = passes[.verdicts, default: ModelPass()].failures
    let ordered = asks
      .filter { !failures.contains($0.failureKey) }
      .sorted { a, b in
        if a.unread != b.unread {
          return a.unread
        }
        return a.activityAt > b.activityAt
      }
    var queue: [(ask: VerdictAsk, question: String)] = []
    for ask in ordered where queue.count < ModelJob.verdicts.budget {
      guard let question = swept.questionTexts[ask.question], needsAnswer(ask) else {
        continue
      }
      queue.append((ask, question))
    }
    return queue
  }

  private func needsAnswer(_ ask: VerdictAsk) -> Bool {
    switch ask.subject {
    case .item(let id):
      return store.itemNeedsVerdict(id, question: ask.question)
    case .target(let key):
      guard let card = swept.cards[key] else {
        return false
      }
      return store.targetNeedsVerdict(key, question: ask.question, text: judgedText(card))
    }
  }

  /// What a card's answers are given for: its title, its latest
  /// notification, and the conversation stored for it — any of them
  /// changing queues a fresh answer.
  private func judgedText(_ card: BoardCard) -> String {
    let conversation = card.target?.conversationAt.map { ISODate.format($0) } ?? ""
    return "\(card.title)\n\(card.lead.body ?? "")\n\(conversation)"
  }

  /// A card put to the model as its target: the title, and the target's
  /// own description when its conversation is in — else what its latest
  /// notification says.
  private func verdictRequest(_ question: String, about card: BoardCard) -> VerdictRequest {
    VerdictRequest(
      question: question,
      title: card.title,
      repo: card.lead.repo,
      author: card.snapshot?.author ?? card.lead.author,
      body: store.conversation(for: card.id)?.description ?? card.lead.body,
      isMention: card.flag(.mention)
    )
  }

  // MARK: Suggestions

  /// Looks for patterns worth a label and asks the model about the
  /// strongest few. Mining is deterministic (see Suggestion.swift); the
  /// model only names and judges.
  private func suggestionPass() async {
    lastSuggestionSweepAt = Date()
    let labels = store.labels()
    let candidates = suggestionCandidates(
      in: store.inboxItems(),
      coveredSignatures: coveredSignatures(in: store.rules()),
      dismissed: store.dismissedSignatures()
    ).prefix(ModelJob.suggestions.budget)
    guard !candidates.isEmpty else {
      return
    }
    var fresh: [Suggestion] = []
    for candidate in candidates {
      guard let draft = try? await intelligence.judge(candidate, labels: labels), !draft.targetName.isEmpty else {
        continue
      }
      // The model names the label; the conditions stay the mined ones, so
      // a suggestion always matches the pattern it came from.
      fresh.append(
        Suggestion(
          id: UUID().uuidString,
          signature: candidate.signature,
          name: draft.name.isEmpty ? draft.targetName : draft.name,
          targetName: draft.targetName,
          targetKind: draft.targetKind.lowercased() == "inbox" ? .inbox : .label,
          targetSymbol: NSSymbolName.known(draft.targetSymbol) ?? "tag",
          targetTint: LabelTint(rawValue: draft.targetTint.lowercased()) ?? .blue,
          rationale: draft.rationale,
          conditions: candidate.conditions,
          matchCount: candidate.count,
          createdAt: Date()
        )
      )
    }
    guard !fresh.isEmpty else {
      return
    }
    store.addSuggestions(fresh)
    record(.suggestions)
  }

  /// Turns a suggestion into a real label and rule.
  func acceptSuggestion(_ id: String) {
    guard let suggestion = store.suggestions().first(where: { $0.id == id }) else {
      return
    }
    let labels = store.labels()
    let existing = labels.first { $0.name.caseInsensitiveCompare(suggestion.targetName) == .orderedSame }
    let target = existing ?? InboxLabel(
      id: UUID().uuidString,
      name: suggestion.targetName,
      symbol: suggestion.targetSymbol,
      tint: suggestion.targetTint,
      notify: .follow,
      order: labels.count,
      kind: suggestion.targetKind
    )
    let rule = LabelRule(
      id: UUID().uuidString, name: suggestion.name, filter: RuleFilter(conditions: suggestion.conditions),
      labelIds: [target.id]
    )
    applyRule(ValidatedRule(rule: rule, newTarget: existing == nil ? target : nil))
    store.removeSuggestion(id)
    record(.suggestions)
  }

  func dismissSuggestion(_ id: String) {
    store.dismissSuggestion(id)
    record(.suggestions)
  }
}
