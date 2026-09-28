// What the on-device model noticed. Patterns are mined from the inbox
// (see Suggestion.swift) and only the ones it thinks are worth a label
// arrive here, one card at a time: what it would make, why, and what it
// would catch. Adding turns it into a real label and rule; "Not now"
// keeps that pattern quiet for good.

import SwiftUI

struct SuggestionsView: View {
  let model: AppModel

  /// Which of several suggestions is showing; one at a time keeps the
  /// page from growing with the backlog.
  @State private var index = 0

  var body: some View {
    let suggestions = model.suggestions
    if !suggestions.isEmpty {
      let shown = suggestions[min(index, suggestions.count - 1)]
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          Image(systemName: "sparkles")
            .font(.system(size: 11))
            .foregroundStyle(Color.accentColor)
          Text("Suggested")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
          Spacer(minLength: 0)
          if suggestions.count > 1 {
            pager(count: suggestions.count)
          }
        }
        SuggestionCard(
          suggestion: shown,
          onAdd: {
            model.acceptSuggestion(shown.id)
            clamp(after: suggestions.count)
          },
          onDismiss: {
            model.dismissSuggestion(shown.id)
            clamp(after: suggestions.count)
          }
        )
      }
    }
  }

  private func pager(count: Int) -> some View {
    HStack(spacing: 4) {
      Button {
        index = max(0, index - 1)
      } label: {
        Image(systemName: "chevron.left")
      }
      .disabled(index == 0)
      Text("\(min(index, count - 1) + 1) of \(count)")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .monospacedDigit()
      Button {
        index = min(count - 1, index + 1)
      } label: {
        Image(systemName: "chevron.right")
      }
      .disabled(index >= count - 1)
    }
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)
    .controlSize(.small)
  }

  /// Answering the last suggestion leaves the index past the end.
  private func clamp(after count: Int) {
    index = min(index, max(0, count - 2))
  }
}

/// One suggestion: the label it proposes, the model's reason, and the
/// pattern behind it.
private struct SuggestionCard: View {
  let suggestion: Suggestion
  let onAdd: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        LabelGlyph(symbol: suggestion.targetSymbol, tint: suggestion.targetTint, size: 16)
        Text(suggestion.targetName)
          .font(.system(size: 12, weight: .medium))
        Text(suggestion.targetKind == .inbox ? "new inbox" : "new label")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
        Spacer(minLength: 0)
      }
      if !suggestion.rationale.isEmpty {
        Text(suggestion.rationale)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      HStack(spacing: 8) {
        Text("\(matchCount) · \(describeConditions(suggestion.conditions, match: .all))")
          .font(.system(size: 11))
          .foregroundStyle(.tertiary)
          .lineLimit(1)
          .truncationMode(.tail)
        Spacer(minLength: 0)
        Button("Not now", action: onDismiss)
        Button("Add", action: onAdd)
      }
      .controlSize(.small)
    }
    .padding(8)
    .settingsCard()
  }

  private var matchCount: String {
    suggestion.matchCount == 1 ? "matches 1 item" : "matches \(suggestion.matchCount) items"
  }
}
