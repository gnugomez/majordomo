// The editor for a filter (RuleFilter), shared by the Rules page and the
// board editor: each group a box of condition rows headed "When all/any of
// these hold", the boxes joined by "or" or "and" — the filter's own match,
// switched from any joiner — and an Apple Intelligence check added through
// a button of its own, its question a row of its own (QuestionRow).

import SwiftUI

struct FilterEditor: View {
  @Binding var filter: RuleFilter
  let accounts: [AccountState]
  /// The fields a condition row offers.
  let fields: [RuleField]
  /// See ConditionRow.live.
  var live = false
  /// What a new condition starts as.
  var newCondition = RuleCondition(field: .title, op: .contains)
  /// Said while the filter holds no conditions at all.
  let emptyText: String
  /// Said under every question: who answers it, and when.
  let questionHint: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if filter.groups.isEmpty {
        Text(emptyText)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
        AddConditionButtons(newCondition: newCondition) { condition in
          filter.groups.append(RuleGroup(conditions: [condition]))
        }
      } else {
        ForEach(filter.groups.indices, id: \.self) { index in
          if index > 0 {
            joiner
          }
          GroupEditor(
            group: $filter.groups.element(index, fallback: RuleGroup()),
            accounts: accounts,
            fields: fields,
            live: live,
            newCondition: newCondition,
            questionHint: questionHint,
            onRemove: {
              filter.groups.remove(at: index)
            }
          )
        }
        Button {
          filter.groups.append(RuleGroup(conditions: [newCondition]))
        } label: {
          Label("Add Group", systemImage: "plus.square.on.square")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help("Another set of conditions, joined to these by \(filter.match == .any ? "or" : "and")")
      }
    }
  }

  /// Between two groups: "or" when any group will do, "and" when every
  /// one must hold. Every joiner shows, and switches, the same choice.
  private var joiner: some View {
    Picker("Join", selection: $filter.match) {
      Text("or").tag(RuleMatch.any)
      Text("and").tag(RuleMatch.all)
    }
    .labelsHidden()
    .controlSize(.small)
    .fixedSize()
    .help("Whether one group holding is enough, or every group must")
  }
}

/// One group: its all-or-any switch, its conditions, and the buttons that
/// add one.
private struct GroupEditor: View {
  @Binding var group: RuleGroup
  let accounts: [AccountState]
  let fields: [RuleField]
  let live: Bool
  let newCondition: RuleCondition
  let questionHint: String
  let onRemove: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Text("When")
        Picker("Match", selection: $group.match) {
          Text("all").tag(RuleMatch.all)
          Text("any").tag(RuleMatch.any)
        }
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        Text("of these hold")
        Spacer()
        Button(action: onRemove) {
          Image(systemName: "xmark")
        }
        .buttonStyle(.borderless)
        .help("Remove this group")
      }
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(.secondary)
      ForEach(group.conditions.indices, id: \.self) { index in
        let condition = $group.conditions.element(index, fallback: RuleCondition(field: .title))
        if group.conditions[index].field == .question {
          QuestionRow(condition: condition, live: live, hint: questionHint) {
            group.conditions.remove(at: index)
          }
        } else {
          ConditionRow(condition: condition, accounts: accounts, fields: fields, live: live) {
            group.conditions.remove(at: index)
          }
        }
      }
      if group.conditions.isEmpty {
        Text("No conditions: matches nothing yet")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
      AddConditionButtons(newCondition: newCondition) { condition in
        group.conditions.append(condition)
      }
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
  }
}

/// Adds a condition, or an Apple Intelligence check — never offered as a
/// field to pick, since its value is a question rather than a word.
private struct AddConditionButtons: View {
  let newCondition: RuleCondition
  let add: (RuleCondition) -> Void

  var body: some View {
    HStack(spacing: 12) {
      Button {
        add(newCondition)
      } label: {
        Label("Add Condition", systemImage: "plus")
      }
      Button {
        add(.question(""))
      } label: {
        Label("Add Apple Intelligence Check", systemImage: "apple.intelligence")
      }
      .help("A yes-or-no question the on-device model answers, in your own words")
    }
    .buttonStyle(.borderless)
    .controlSize(.small)
  }
}

/// What a question row says under the question: that the model answers it
/// on this Mac and keeps each answer until the question or the `subject`
/// changes — or why nothing is answering it.
@MainActor
func questionHint(_ model: AppModel, subject: String) -> String {
  if let reason = model.intelligence.reason {
    return reason
  }
  if !model.intelligenceEnabled {
    return "Apple Intelligence is switched off in Settings, so nothing is being answered."
  }
  return "Answered on this Mac, and kept until the question or the \(subject) changes."
}

extension Binding {
  /// One element of a bound array by position. A row being removed can
  /// still be read once its element is gone; it reads `fallback` then,
  /// and writes go nowhere.
  func element<Element: Sendable>(_ index: Int, fallback: Element) -> Binding<Element> where Value == [Element] {
    Binding<Element>(
      get: { index < wrappedValue.count ? wrappedValue[index] : fallback },
      set: { element in
        if index < wrappedValue.count {
          wrappedValue[index] = element
        }
      }
    )
  }
}
