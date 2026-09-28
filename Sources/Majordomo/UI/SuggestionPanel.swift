// The suggestion panel: a floating card over the foot of the inbox,
// offering one label-and-rule the on-device model thinks would help. It
// exists only while there is something to offer — no empty state, no
// permanent chrome — and it floats on glass rather than docking, so it
// reads as a passing offer over the list instead of part of it.

import SwiftUI

struct SuggestionPanel: View {
  let model: AppModel

  /// The oldest pending suggestion: one question at a time, answered in
  /// the order they arrived.
  private var suggestion: Suggestion? {
    guard model.suggestionsEnabled else {
      return nil
    }
    return model.suggestions.min { $0.createdAt < $1.createdAt }
  }

  var body: some View {
    if let suggestion {
      card(suggestion)
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.snappy, value: suggestion.id)
    }
  }

  private func card(_ suggestion: Suggestion) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        LabelGlyph(symbol: suggestion.targetSymbol, tint: suggestion.targetTint, size: 22)
        VStack(alignment: .leading, spacing: 1) {
          Text(suggestion.targetName)
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
          Text(suggestion.targetKind == .inbox ? "Suggested inbox" : "Suggested label")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        if model.suggestions.count > 1 {
          Text("1 of \(model.suggestions.count)")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
      }
      Text(suggestion.rationale)
        .font(.system(size: 12))
        .foregroundStyle(.primary)
        .fixedSize(horizontal: false, vertical: true)
      Text("\(suggestion.matchCount) items · \(describeConditions(suggestion.conditions, match: .all))")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
      HStack(spacing: 8) {
        Spacer(minLength: 0)
        Button("Not now") {
          model.dismissSuggestion(suggestion.id)
        }
        Button("Add") {
          model.acceptSuggestion(suggestion.id)
        }
        .buttonStyle(.borderedProminent)
      }
      .controlSize(.small)
    }
    .padding(12)
    // Glass, so the list stays legible underneath and the card reads as
    // floating over it rather than as another row.
    .glassEffect(.regular, in: .rect(cornerRadius: 14))
  }
}
