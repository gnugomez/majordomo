// Describing a rule in a sentence. The on-device model drafts it, the app
// validates the draft (see RuleDraft), and what comes back is shown for
// confirmation — never saved behind the user's back. Without Apple
// Intelligence the field says why it can't help and the page carries on
// working by hand.

import SwiftUI

struct RuleComposerView: View {
  let model: AppModel
  /// Handed the rule the user accepted, so the page can select it.
  let onAdded: (LabelRule) -> Void
  /// True while a draft is waiting on the user — the page hides its
  /// suggestion meanwhile, so only one thing is ever asking to be judged.
  let onPending: (Bool) -> Void

  @State private var text = ""
  @State private var drafting = false
  @State private var error: String?
  /// The drafted rule, waiting on the user.
  @State private var proposal: ValidatedRule?

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
        CommitTextField("Describe a rule — “anything from dependabot can wait”", text: text) { typed in
          text = typed
          submit()
        }
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)
        .disabled(!available || drafting)
        if drafting {
          ProgressView()
            .controlSize(.small)
        } else {
          Button("Draft", action: submit)
            .controlSize(.small)
            .disabled(!available || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }

      if let reason = unavailableReason {
        Text(reason)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }
      if let error {
        Text(error)
          .font(.system(size: 11))
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let proposal {
        ProposalCard(
          model: model,
          proposal: proposal,
          onAdd: { add(proposal) },
          onDiscard: {
            self.proposal = nil
            onPending(false)
          }
        )
      }
    }
    .task {
      model.refreshIntelligence()
    }
  }

  private func submit() {
    let ask = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard available, !ask.isEmpty, !drafting else {
      return
    }
    drafting = true
    error = nil
    proposal = nil
    Task {
      switch await model.composeRule(ask) {
      case .success(let validated):
        proposal = validated
      case .failure(let failure):
        error = failure.message
      }
      drafting = false
      onPending(proposal != nil)
    }
  }

  private func add(_ validated: ValidatedRule) {
    model.applyRule(validated)
    proposal = nil
    error = nil
    text = ""
    onPending(false)
    onAdded(validated.rule)
  }
}

/// A drafted rule as the user will get it: what it matches on, where it
/// lands, and how much of the inbox it would take right now.
private struct ProposalCard: View {
  let model: AppModel
  let proposal: ValidatedRule
  let onAdd: () -> Void
  let onDiscard: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        if let target {
          LabelGlyph(symbol: target.symbol, tint: target.tint, size: 16)
          Text(target.name)
            .font(.system(size: 12, weight: .medium))
        }
        Text(targetNote)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
      }
      Text("When \(describe(proposal.rule))")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 8) {
        Text(matchLine)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
        Button("Discard", action: onDiscard)
        Button("Add Rule", action: onAdd)
          .keyboardShortcut(.defaultAction)
      }
      .controlSize(.small)
    }
    .padding(8)
    .settingsCard()
  }

  /// The label or inbox the rule fills — the new one when there is one,
  /// else the existing target it found.
  private var target: InboxLabel? {
    proposal.newTarget ?? proposal.rule.labelIds.compactMap { model.label($0) }.first
  }

  private var targetNote: String {
    guard let target else {
      return ""
    }
    let kind = target.kind == .inbox ? "inbox" : "label"
    return proposal.newTarget == nil ? "existing \(kind)" : "new \(kind)"
  }

  private var matchLine: String {
    let count = model.items.filter { LabelEngine.matches(proposal.rule, $0) }.count
    return switch count {
    case 0: "Nothing in the inbox matches it yet"
    case 1: "Matches 1 item now"
    default: "Matches \(count) items now"
    }
  }
}
