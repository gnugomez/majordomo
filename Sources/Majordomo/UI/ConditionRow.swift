// One condition in a filter editor: the field, the test (operator and
// negation folded into one menu so it reads as a sentence), and the value
// control the field calls for. The Rules page offers the fields a
// notification carries; a board offers every field, the target's own
// included. An Apple Intelligence check has a row of its own
// (QuestionRow): the question is a sentence, not a value.

import SwiftUI

struct ConditionRow: View {
  @Binding var condition: RuleCondition
  let accounts: [AccountState]
  /// The fields the field picker offers.
  var fields: [RuleField] = RuleField.itemFields
  /// Hands every keystroke back, for an editor that saves as a whole —
  /// a commit on blur would miss the value still being typed when Save is
  /// clicked.
  var live = false
  let onRemove: () -> Void

  var body: some View {
    HStack(spacing: 6) {
      Picker("Field", selection: fieldBinding) {
        ForEach(fields, id: \.self) { field in
          Text(fieldLabel(field)).tag(field)
        }
      }
      .labelsHidden()
      .controlSize(.small)
      .frame(width: 116)

      Picker("Test", selection: testBinding) {
        ForEach(tests, id: \.self) { test in
          Text(test.label(for: condition.field)).tag(test)
        }
      }
      .labelsHidden()
      .controlSize(.small)
      .frame(width: condition.field.isFlag ? 120 : 112)

      valueControl

      Spacer(minLength: 0)
      RemoveButton(help: "Remove this condition", action: onRemove)
    }
  }

  // MARK: Bindings

  /// A new field changes the condition whole, in one write: a
  /// picker-valued field needs a value from its own vocabulary, and a text
  /// field starts blank rather than inheriting an id.
  private var fieldBinding: Binding<RuleField> {
    Binding(
      get: { condition.field },
      set: { field in
        var updated = condition
        updated.field = field
        switch field {
        case .provider:
          updated.value = providerSpecs[0].id.rawValue
          updated.op = .is
        case .account:
          updated.value = accounts.first?.id ?? ""
          updated.op = .is
        case _ where field.isFlag:
          updated.value = ""
          updated.op = .is
        default:
          if [.provider, .account].contains(condition.field) || condition.field.isFlag {
            updated.value = ""
          }
        }
        condition = updated
      }
    )
  }

  /// Operator and negation, set together.
  private var testBinding: Binding<ConditionTest> {
    Binding(
      get: { ConditionTest(op: condition.op, negated: condition.negated) },
      set: { test in
        var updated = condition
        updated.op = test.op
        updated.negated = test.negated
        condition = updated
      }
    )
  }

  /// Picker-valued and flag fields offer only `is` (negatable); text
  /// fields offer every operator.
  private var tests: [ConditionTest] {
    if condition.field.isFlag || [.provider, .account].contains(condition.field) {
      return [ConditionTest(op: .is, negated: false), ConditionTest(op: .is, negated: true)]
    }
    return RuleOperator.allCases.flatMap { op in
      [ConditionTest(op: op, negated: false), ConditionTest(op: op, negated: true)]
    }
  }

  @ViewBuilder
  private var valueControl: some View {
    switch condition.field {
    case .provider:
      Picker("Provider", selection: $condition.value) {
        ForEach(providerSpecs, id: \.id) { spec in
          Text(spec.displayName).tag(spec.id.rawValue)
        }
      }
      .labelsHidden()
      .controlSize(.small)
      .frame(width: 110)
    case .account:
      if accounts.isEmpty {
        Text("No accounts")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      } else {
        Picker("Account", selection: $condition.value) {
          ForEach(accounts) { account in
            Text(accountDescriptor(account)).tag(account.id)
          }
        }
        .labelsHidden()
        .controlSize(.small)
        .frame(width: 130)
      }
    case _ where condition.field.isFlag || condition.op == .exists:
      EmptyView()
    default:
      HStack(spacing: 2) {
        Group {
          if live {
            TextField(placeholder, text: $condition.value)
          } else {
            CommitTextField(placeholder, text: condition.value) { value in
              condition.value = value
            }
          }
        }
        .textFieldStyle(.roundedBorder)
        .controlSize(.small)
        .frame(minWidth: 90)
        if !suggestions.isEmpty {
          Menu {
            ForEach(suggestions, id: \.self) { value in
              Button(value) {
                condition.value = value
              }
            }
          } label: {
            Image(systemName: "chevron.down")
          }
          .menuStyle(.button)
          .buttonStyle(.borderless)
          .menuIndicator(.hidden)
          .controlSize(.small)
          .fixedSize()
          .help("Pick a value")
        }
      }
    }
  }

  /// Values worth offering for the field: the providers' own tokens, and
  /// `@me` wherever a login goes — on a board, which knows whose cards
  /// they are.
  private var suggestions: [String] {
    guard condition.op == .is else {
      return []
    }
    if condition.field == .dueDate {
      return DueDate.vocabulary
    }
    if [.author, .assignee, .reviewer, .lastCommenter].contains(condition.field), fields != RuleField.itemFields {
      return ["@me"]
    }
    var seen: Set<String> = []
    return providerSpecs.flatMap { $0.tokens(for: condition.field) }.filter { seen.insert($0).inserted }
  }

  /// An example in the field's own terms.
  private var placeholder: String {
    if condition.op == .matches {
      return "^fix:"
    }
    switch condition.field {
    case .repo: return "eclipse/*"
    case .title: return "crash"
    case .body: return "stack trace"
    case .author: return "dependabot[bot]"
    case .kind: return "issue"
    case .reason: return "mentioned"
    case .state: return "open"
    case .upstreamLabel: return "urgent"
    case .assignee, .reviewer, .lastCommenter: return "@me"
    case .review: return "approved"
    case .checks: return "failure"
    case .merge: return "conflicts"
    case .status: return "in_progress"
    case .milestone: return "v2.0"
    case .dueDate: return "today"
    case .provider, .account, .mention, .unread, .question: return ""
    }
  }
}

/// An Apple Intelligence check: the question, in the user's own words, and
/// whether a yes or a no from the model satisfies it.
struct QuestionRow: View {
  @Binding var condition: RuleCondition
  /// See ConditionRow.live.
  var live = false
  /// Who answers the question, and when — or why nothing is answering.
  let hint: String
  let onRemove: () -> Void

  private let prompt = "Describe what this should catch, the way you would say it out loud."

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 4) {
        Image(systemName: "apple.intelligence")
          .foregroundStyle(.secondary)
        Text("Apple Intelligence answers")
        Picker("Answer", selection: $condition.negated) {
          Text("yes").tag(false)
          Text("no").tag(true)
        }
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        Text("to")
        Spacer(minLength: 0)
        RemoveButton(help: "Remove this check", action: onRemove)
      }
      .font(.system(size: 12))
      Group {
        if live {
          TextField(prompt, text: $condition.value, axis: .vertical)
        } else {
          CommitTextField(prompt, text: condition.value, axis: .vertical) { question in
            condition.value = question
          }
        }
      }
      .lineLimit(2 ... 5)
      .textFieldStyle(.roundedBorder)
      .controlSize(.small)
      Text(hint)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

/// The minus at a row's end.
private struct RemoveButton: View {
  let help: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "minus.circle")
        .foregroundStyle(.secondary)
    }
    .buttonStyle(.plain)
    .help(help)
  }
}
