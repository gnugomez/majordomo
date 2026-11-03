// Describing a rule in a sentence. The on-device model drafts it, the app
// validates the draft (see RuleDraft), and what comes back takes the rule
// editor's place for confirmation (DraftReview) — never saved behind the
// user's back. Without Apple Intelligence the field says why it can't help
// and the page carries on working by hand.

import SwiftUI

/// The composer's state, shared by the field that drafts and the review
/// that confirms. Observation tracks each property apart, so typing
/// redraws the field alone and the page only follows the draft.
@MainActor @Observable
final class RuleComposer {
  /// The sentence, kept until its draft is added: a discarded draft is
  /// one rewording away.
  var text = ""
  var drafting = false
  var error: String?
  /// The drafted rule, waiting on the user.
  var draft: ValidatedRule?

  /// Drafts a rule from the sentence. The draft on show stays until the
  /// new one replaces it, so the page doesn't blink back to the editor
  /// while the model thinks; a failure clears it, since its message is
  /// about the new sentence.
  func submit(_ model: AppModel) {
    let ask = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard model.intelligenceActive, !ask.isEmpty, !drafting else {
      return
    }
    drafting = true
    error = nil
    Task {
      switch await model.composeRule(ask) {
      case .success(let validated):
        draft = validated
      case .failure(let failure):
        draft = nil
        error = failure.message
      }
      drafting = false
    }
  }

  /// Saves the draft, and the label or inbox it needs, and clears the
  /// field for the next one. Hands back the rule, for the page to select.
  func add(_ model: AppModel) -> LabelRule? {
    guard let draft else {
      return nil
    }
    model.applyRule(draft)
    self.draft = nil
    error = nil
    text = ""
    return draft.rule
  }
}

struct RuleComposerView: View {
  let model: AppModel
  @Bindable var composer: RuleComposer

  /// The composer needs both: a model that can run, and the user's
  /// switch left on.
  private var available: Bool { model.intelligenceActive }

  /// Why it is unavailable — the hardware's reason, or the user's own
  /// choice, which is not a fault to explain at length.
  private var unavailableReason: String? {
    if let reason = model.intelligence.reason {
      return reason
    }
    return model.intelligenceEnabled ? nil : "Apple Intelligence is off — turn it on in Settings › Intelligence."
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: "sparkles")
          .font(.system(size: 11))
          .foregroundStyle(available ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
        // A plain field, not a committing one: nothing is stored until a
        // draft is added, and the Draft button reads what is typed.
        TextField("Describe a rule — “anything from dependabot can wait”", text: $composer.text)
          .onSubmit { composer.submit(model) }
          .textFieldStyle(.roundedBorder)
          .controlSize(.small)
          .disabled(!available || composer.drafting)
        if composer.drafting {
          ProgressView()
            .controlSize(.small)
        } else {
          Button("Draft") {
            composer.submit(model)
          }
          .controlSize(.small)
          .disabled(!available || composer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }

      if let reason = unavailableReason {
        Text(reason)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }
      if let error = composer.error {
        Text(error)
          .font(.system(size: 11))
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .task {
      model.refreshIntelligence()
    }
  }
}

/// A drafted rule where the rule editor goes, until the user adds or
/// discards it: what it applies, its filter read line by line, what an
/// Apple Intelligence check in it costs, and what it would match now.
struct DraftReview: View {
  let model: AppModel
  let draft: ValidatedRule
  let onAdd: () -> Void
  let onDiscard: () -> Void

  private var filter: RuleFilter { draft.rule.filter }

  var body: some View {
    // Worked out once per draw, for the preview, its header and the
    // check's note alike.
    let matches = inboxOrder(RuleEngine.matching(filter, among: model.items))
    let waiting = RuleEngine.awaitingModel(filter, among: model.items)
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Image(systemName: "sparkles")
          .foregroundStyle(Color.accentColor)
        Text("Drafted from your sentence")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
        Button("Discard", action: onDiscard)
        Button("Add Rule", action: onAdd)
          .keyboardShortcut(.defaultAction)
      }
      .controlSize(.small)

      summary
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .settingsCard()

      if filter.asksModel {
        Label {
          Text(costNote(waiting: waiting))
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
          Image(systemName: "apple.intelligence")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      }

      Text(matchHeader(matches.count, waiting: waiting))
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
      List {
        ForEach(matches.prefix(rulePreviewCap)) { item in
          MatchRow(item: item, now: model.now)
        }
        if matches.isEmpty {
          Text(waiting > 0 ? "The preview fills in as Apple Intelligence answers." : "Nothing in the inbox matches it right now.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
      }
      .listStyle(.bordered)
      .frame(maxHeight: .infinity)
    }
  }

  /// The rule's name, where it lands, and its filter.
  private var summary: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Text(draft.rule.name)
          .font(.system(size: 13, weight: .semibold))
          .lineLimit(1)
        Image(systemName: "arrow.right")
          .font(.system(size: 10))
          .foregroundStyle(.tertiary)
        if let target {
          LabelGlyph(symbol: target.symbol, tint: target.tint, size: 16)
          Text(target.name)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
          Text(targetNote(target))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
      }
      outlineText
        .font(.system(size: 12))
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// The filter as its outline: a single condition reads as one sentence,
  /// anything more as a line per part under "all" or "any".
  @ViewBuilder private var outlineText: some View {
    let outline = outline(filter)
    if outline.lines.count == 1 {
      Text("When \(outline.lines[0])")
    } else {
      VStack(alignment: .leading, spacing: 3) {
        Text("When \(outline.match == .any ? "any" : "all") of these hold:")
          .foregroundStyle(.secondary)
        ForEach(outline.lines.indices, id: \.self) { index in
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•")
              .foregroundStyle(.tertiary)
            Text(outline.lines[index])
          }
        }
      }
    }
  }

  /// The label or inbox the rule fills — the new one when there is one,
  /// else the existing target it found.
  private var target: InboxLabel? {
    draft.newTarget ?? draft.rule.labelIds.compactMap { model.label($0) }.first
  }

  private func targetNote(_ target: InboxLabel) -> String {
    let kind = target.kind == .inbox ? "inbox" : "label"
    return draft.newTarget == nil ? "existing \(kind)" : "new \(kind)"
  }

  /// What a check costs: a model call on this Mac per notification the
  /// cheap conditions let through, and how many are `waiting` on one now.
  private func costNote(waiting: Int) -> String {
    let checks = filter.conditions.count { $0.question != nil }
    let what = checks == 1 ? "an Apple Intelligence check" : "\(checks) Apple Intelligence checks"
    let backlog = switch waiting {
    case 0: "none to judge right now"
    case 1: "1 to judge now"
    default: "\(waiting) to judge now, a few at a time"
    }
    return "Includes \(what), judged on this Mac for each notification the other conditions let through — \(backlog)."
  }

  private func matchHeader(_ count: Int, waiting: Int) -> String {
    switch count {
    case 0: waiting > 0 ? "Nothing matches until Apple Intelligence answers" : "Nothing in the inbox matches it yet"
    case 1: "Would match 1 item now"
    default: "Would match \(count) items now"
    }
  }
}
