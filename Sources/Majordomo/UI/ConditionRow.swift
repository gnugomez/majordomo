// One condition in an editor: the field, the test (operator and negation
// folded into one menu so it reads as a sentence), and the value control
// the field calls for. The Rules page offers the fields a notification
// carries; a board's columns offer every field, the target's own included.

import SwiftUI

struct ConditionRow: View {
  let condition: RuleCondition
  let accounts: [AccountState]
  /// The fields the field picker offers.
  var fields: [RuleField] = RuleField.itemFields
  /// Hands every keystroke back, for an editor that saves as a whole —
  /// a commit on blur would miss the value still being typed when Save is
  /// clicked.
  var live = false
  let onChange: (RuleCondition) -> Void
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
      Button {
        onRemove()
      } label: {
        Image(systemName: "minus.circle")
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .help("Remove this condition")
    }
  }

  // MARK: Bindings

  private var fieldBinding: Binding<RuleField> {
    Binding(
      get: { condition.field },
      set: { field in
        var updated = condition
        updated.field = field
        // A picker-valued field needs a value from its own vocabulary;
        // a text field starts blank rather than inheriting an id.
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
        onChange(updated)
      }
    )
  }

  private var testBinding: Binding<ConditionTest> {
    Binding(
      get: { ConditionTest(op: condition.op, negated: condition.negated) },
      set: { test in
        var updated = condition
        updated.op = test.op
        updated.negated = test.negated
        onChange(updated)
      }
    )
  }

  private var valueBinding: Binding<String> {
    Binding(
      get: { condition.value },
      set: { value in
        var updated = condition
        updated.value = value
        onChange(updated)
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
      Picker("Provider", selection: valueBinding) {
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
        Picker("Account", selection: valueBinding) {
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
            TextField(placeholder, text: valueBinding)
          } else {
            CommitTextField(placeholder, text: condition.value) { value in
              valueBinding.wrappedValue = value
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
                valueBinding.wrappedValue = value
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
    case .milestone: return "v2.0"
    case .provider, .account, .mention, .unread: return ""
    }
  }
}
