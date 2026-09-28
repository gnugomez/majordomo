// The Rules settings page: what the on-device model suggests, a field for
// describing a rule in a sentence, and the rules themselves — the
// providers' built-in ones (the sidebar buckets, read-only), the user's
// with their switches, and the editor for the selected one: its
// conditions (field, test, value), what it applies, and a live preview of
// the items it matches right now. Edits commit whole user rules through
// the model; text commits on submit or blur.

import SwiftUI

/// The editor's fixed height, shared with its placeholder so the page
/// never resizes on selection.
private let editorHeight: CGFloat = 380
/// The conditions box grows with its rows up to this many, then scrolls —
/// a built-in rule carries four, and a partly visible fifth row is the
/// scroll cue.
private let visibleConditionRows = 4
private let conditionRowHeight: CGFloat = 28
/// Rows the match preview shows at most; the header carries the true count.
private let previewCap = 50
/// The match preview never shrinks below this, however tall the rule is.
private let previewMinHeight: CGFloat = 100

struct RulesSettingsView: View {
  let model: AppModel

  @State private var selection: String?
  /// Set once the first rule has been picked for the user, so a later
  /// deselection stays.
  @State private var autoSelected = false
  /// The built-in rules fold away by default: the user's own are the
  /// point of the page, and there are a dozen provider rules.
  @State private var builtinExpanded = false
  /// True while the composer holds a draft awaiting confirmation.
  @State private var draftPending = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // One thing asking to be judged at a time: a draft waiting on the
      // user takes the place of the suggestion card.
      if !draftPending, model.suggestionsEnabled {
        SuggestionsView(model: model)
      }
      suggestionsToggle
      RuleComposerView(model: model) { added in
        selection = added.id
        autoSelected = true
      } onPending: { pending in
        draftPending = pending
      }

      List(selection: $selection) {
        DisclosureGroup(isExpanded: $builtinExpanded) {
          ForEach(model.catalog.builtinRules) { rule in
            BuiltinRuleRow(rule: rule, provider: providerName(defining: rule), summary: describe(rule))
              .tag(rule.id)
          }
        } label: {
          HStack(spacing: 8) {
            Image(systemName: "lock")
              .font(.system(size: 11))
              .foregroundStyle(.tertiary)
              .frame(width: 14)
            Text("Built-in")
              .font(.system(size: 13))
            Spacer()
            Text("\(model.catalog.builtinRules.count) provider rules")
              .font(.system(size: 11))
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, 2)
        }
        ForEach(model.rules) { rule in
          RuleListRow(rule: rule, summary: summary(rule)) { updated in
            replace(updated)
          }
          .tag(rule.id)
        }
        if model.rules.isEmpty {
          Text("No rules yet")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
      }
      .listStyle(.bordered)
      .frame(height: 132)

      ControlGroup {
        Button {
          add()
        } label: {
          Image(systemName: "plus")
        }
        .help("Add a rule")
        Button {
          remove()
        } label: {
          Image(systemName: "minus")
        }
        .disabled(selected == nil)
        .help("Remove the selected rule")
      }
      .controlSize(.small)
      .fixedSize()

      if let rule = selected {
        RuleEditor(model: model, rule: rule) { updated in
          replace(updated)
        }
      } else if let rule = selectedBuiltin {
        // Read-only: the conditions as they are, nothing to change.
        RuleEditor(model: model, rule: rule, definedBy: providerName(defining: rule)) { _ in }
      } else {
        VStack {
          Text(model.rules.isEmpty ? "Add a rule to label items automatically." : "Select a rule to edit its conditions and labels.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: editorHeight, maxHeight: editorHeight)
        .settingsCard()
      }
    }
    .padding(16)
    // The editor is the point of the page: open on the first rule once the
    // rules are in (the engine's first state push can land after the page
    // appears).
    .onChange(of: model.rules.isEmpty, initial: true) {
      if selection == nil, !autoSelected, let first = model.rules.first {
        selection = first.id
        autoSelected = true
      }
    }
  }

  /// The selected USER rule; a built-in row selects nothing editable.
  private var selected: LabelRule? {
    model.rules.first { $0.id == selection }
  }

  private var selectedBuiltin: LabelRule? {
    model.catalog.builtinRules.first { $0.id == selection }
  }

  /// The provider whose spec defines a built-in rule.
  private func providerName(defining rule: LabelRule) -> String {
    providerSpecs.first { spec in spec.builtinRules.contains { $0.id == rule.id } }?.displayName ?? ""
  }

  /// "2 conditions → Urgent, Infra" for the list row — "any of 2
  /// conditions" when one holding is enough.
  private func summary(_ rule: LabelRule) -> String {
    let count = rule.conditions.count
    var conditions = count == 1 ? "1 condition" : "\(count) conditions"
    if rule.match == .any, count > 1 {
      conditions = "any of \(conditions)"
    }
    let names = rule.labelIds.compactMap { model.label($0)?.name }
    return names.isEmpty ? conditions : "\(conditions) → \(names.joined(separator: ", "))"
  }

  /// Pattern-watching, off or on. Switching it off stops the sweeps and
  /// hides what is pending; dismissals are remembered either way, so
  /// turning it back on doesn't replay what was already refused.
  private var suggestionsToggle: some View {
    HStack(spacing: 6) {
      Image(systemName: "sparkles")
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
      Text("Suggest labels from patterns in your inbox")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      Spacer(minLength: 0)
      Toggle(
        "Suggest labels",
        isOn: Binding(
          get: { model.suggestionsEnabled },
          set: { model.setSuggestionsEnabled($0) }
        )
      )
      .labelsHidden()
      .toggleStyle(.switch)
      .controlSize(.mini)
      .disabled(!model.intelligence.isAvailable)
    }
  }

  private func replace(_ updated: LabelRule) {
    model.setRules(model.rules.map { $0.id == updated.id ? updated : $0 })
  }

  private func add() {
    let rule = LabelRule(
      id: UUID().uuidString, name: "New Rule",
      conditions: [RuleCondition(field: .title, op: .contains, value: "")], labelIds: []
    )
    model.setRules(model.rules + [rule])
    selection = rule.id
  }

  private func remove() {
    guard let selection else {
      return
    }
    model.setRules(model.rules.filter { $0.id != selection })
    self.selection = nil
  }
}

/// One provider rule in the list: who defines it, the label it fills, and
/// its conditions in words. Read-only by design.
private struct BuiltinRuleRow: View {
  let rule: LabelRule
  let provider: String
  let summary: String

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: "lock")
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .frame(width: 14)
      Text("\(provider) · \(rule.name)")
        .font(.system(size: 13))
      Spacer()
      Text(summary)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
    }
    .padding(.vertical, 2)
  }
}

/// One user rule in the list: its switch, name, and a one-line summary.
private struct RuleListRow: View {
  let rule: LabelRule
  let summary: String
  let onChange: (LabelRule) -> Void

  var body: some View {
    HStack(spacing: 8) {
      Toggle(
        "Enabled",
        isOn: Binding(
          get: { rule.enabled },
          set: { enabled in
            var updated = rule
            updated.enabled = enabled
            onChange(updated)
          }
        )
      )
      .labelsHidden()
      .toggleStyle(.checkbox)
      Text(rule.name.isEmpty ? "Untitled" : rule.name)
        .font(.system(size: 13))
        .foregroundStyle(rule.enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
      Spacer()
      Text(summary)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .padding(.vertical, 2)
  }
}

/// The selected rule: name, conditions, labels, and a live preview of what
/// it matches. A built-in rule (`definedBy` names its provider) shows the
/// same, with every control disabled — the preview stays readable.
private struct RuleEditor: View {
  let model: AppModel
  let rule: LabelRule
  var definedBy: String?
  let onChange: (LabelRule) -> Void

  private var readOnly: Bool { definedBy != nil }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      editingControls
        .disabled(readOnly)

      Text(matchHeader)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
      List {
        ForEach(matches.prefix(previewCap)) { item in
          MatchRow(item: item, now: model.now)
        }
        if matches.isEmpty {
          Text(rule.conditions.isEmpty ? "The preview fills in as you add conditions." : "Nothing in the inbox matches these conditions.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
      }
      .listStyle(.bordered)
      // The preview takes whatever the rest of the editor leaves: the
      // conditions box grows with its rows, and the slack belongs here
      // rather than as dead space under the page.
      .frame(minHeight: previewMinHeight, maxHeight: .infinity)
    }
    .frame(maxHeight: .infinity, alignment: .top)
  }

  /// Name, conditions, and labels — everything a user rule lets you change.
  private var editingControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      CommitTextField("Rule name", text: rule.name) { name in
        var updated = rule
        updated.name = name.isEmpty ? "Untitled" : name
        onChange(updated)
      }
      .textFieldStyle(.roundedBorder)

      // "When [all|any] of these hold": the rule's match mode, as Mail's
      // rules put it.
      HStack(spacing: 4) {
        Text("When")
        Picker(
          "Match",
          selection: Binding(
            get: { rule.match },
            set: { match in
              var updated = rule
              updated.match = match
              onChange(updated)
            }
          )
        ) {
          Text("all").tag(RuleMatch.all)
          Text("any").tag(RuleMatch.any)
        }
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        Text("of these hold")
      }
      .font(.system(size: 11, weight: .medium))
      .foregroundStyle(.secondary)
      ScrollView {
        VStack(spacing: 6) {
          ForEach(Array(rule.conditions.enumerated()), id: \.offset) { index, condition in
            ConditionRow(condition: condition, accounts: model.accounts) { updated in
              var conditions = rule.conditions
              conditions[index] = updated
              commit(conditions: conditions)
            } onRemove: {
              var conditions = rule.conditions
              conditions.remove(at: index)
              commit(conditions: conditions)
            }
          }
          if rule.conditions.isEmpty {
            Text("No conditions")
              .font(.system(size: 12))
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity)
              .padding(.top, 8)
          }
        }
        .padding(8)
      }
      .frame(height: conditionsBoxHeight)
      .settingsCard()
      Button("Add Condition") {
        commit(conditions: rule.conditions + [RuleCondition(field: .title, op: .contains, value: "")])
      }
      .controlSize(.small)

      Text("Apply to")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
      // One row whatever the count: the applied inboxes and labels as
      // pills, and a menu of every choice, inboxes first, to toggle them. A
      // user rule feeds the user's inboxes and labels; a built-in one fills
      // a built-in inbox, so the read-only view offers those.
      let inboxes = readOnly ? model.catalog.builtinLabels : model.userInboxes
      let labels = model.userLabels
      let choices = inboxes + labels
      let applied = choices.filter { rule.labelIds.contains($0.id) }
      HStack(spacing: 6) {
        if applied.isEmpty {
          Text(choices.isEmpty ? "Create an inbox or a label first." : "Nothing yet")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        } else {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
              ForEach(applied) { label in
                LabelCapsule(label: label)
              }
            }
          }
        }
        Spacer(minLength: 0)
        Menu {
          if !inboxes.isEmpty {
            Section("Inboxes") {
              ForEach(inboxes) { inbox in
                Toggle(isOn: labelBinding(inbox.id)) {
                  Label(inbox.name, systemImage: inbox.symbol)
                }
              }
            }
          }
          if !labels.isEmpty {
            Section("Labels") {
              ForEach(labels) { label in
                Toggle(isOn: labelBinding(label.id)) {
                  Label(label.name, systemImage: label.symbol)
                }
              }
            }
          }
        } label: {
          Image(systemName: "plus")
        }
        .menuIndicator(.hidden)
        .controlSize(.small)
        .fixedSize()
        .disabled(choices.isEmpty)
        .help("Choose the inboxes and labels this rule applies")
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .settingsCard()
    }
  }

  /// Sized to the rows, one row minimum, scrolling past visibleConditionRows.
  private var conditionsBoxHeight: CGFloat {
    CGFloat(max(1, min(rule.conditions.count, visibleConditionRows))) * conditionRowHeight + 12
  }

  private func commit(conditions: [RuleCondition]) {
    var updated = rule
    updated.conditions = conditions
    onChange(updated)
  }

  private func labelBinding(_ id: LabelId) -> Binding<Bool> {
    Binding(
      get: { rule.labelIds.contains(id) },
      set: { on in
        var updated = rule
        updated.labelIds.removeAll { $0 == id }
        if on {
          updated.labelIds.append(id)
        }
        onChange(updated)
      }
    )
  }

  /// What the rule would label right now, newest first — the fastest way
  /// to see whether a condition is written right. The engine's own
  /// evaluation, so all/any and the empty-rule case agree with the sweep.
  private var matches: [InboxItem] {
    inboxOrder(model.items.filter { LabelEngine.matches(rule, $0) })
  }

  private var matchHeader: String {
    guard !rule.conditions.isEmpty else {
      return "Add a condition — an empty rule matches nothing"
    }
    let count = matches.count
    let matched = switch count {
    case 0: "No items match yet"
    case 1: "Matches 1 item now"
    default: "Matches \(count) items now"
    }
    if let definedBy {
      return "\(matched) · built into \(definedBy), read-only"
    }
    return rule.enabled ? matched : "\(matched) · the rule is switched off"
  }
}

/// One matching item in the preview: the kind/state glyph in the
/// provider's color, the title, and the where-and-when line with the
/// provider mark — the inbox row's shape, minus everything interactive.
private struct MatchRow: View {
  let item: InboxItem
  let now: Date

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      Image(systemName: spec(for: item.provider).symbol(for: item))
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(spec(for: item.provider).color(for: item))
        .frame(width: 14)
      VStack(alignment: .leading, spacing: 1) {
        Text(item.title)
          .font(.system(size: 12))
          .lineLimit(1)
          .truncationMode(.tail)
        HStack(spacing: 4) {
          let source = metaSource(for: item)
          let time = relativeTime(item.updatedAt, now: now)
          Text(source.isEmpty ? time : "\(source) · \(time)")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
          ProviderMark(provider: item.provider)
            .foregroundStyle(.tertiary)
            .frame(width: 10, height: 10)
        }
      }
    }
    .padding(.vertical, 1)
  }
}

/// One condition: the field, the test (operator and negation folded into
/// one menu so it reads as a sentence), and the value control the field
/// calls for.
private struct ConditionRow: View {
  let condition: RuleCondition
  let accounts: [AccountState]
  let onChange: (RuleCondition) -> Void
  let onRemove: () -> Void

  var body: some View {
    HStack(spacing: 6) {
      Picker("Field", selection: fieldBinding) {
        ForEach(RuleField.allCases, id: \.self) { field in
          Text(fieldLabel(field)).tag(field)
        }
      }
      .labelsHidden()
      .controlSize(.small)
      .frame(width: 116)

      Picker("Test", selection: testBinding) {
        ForEach(tests, id: \.self) { test in
          Text(test.label(mention: condition.field == .mention)).tag(test)
        }
      }
      .labelsHidden()
      .controlSize(.small)
      .frame(width: condition.field == .mention ? 120 : 112)

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
        case .mention:
          updated.value = ""
          updated.op = .is
        default:
          if [.provider, .account, .mention].contains(condition.field) {
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

  /// Picker-valued fields offer only `is` (negatable); text fields offer
  /// every operator.
  private var tests: [ConditionTest] {
    switch condition.field {
    case .provider, .account, .mention:
      [ConditionTest(op: .is, negated: false), ConditionTest(op: .is, negated: true)]
    default:
      RuleOperator.allCases.flatMap { op in
        [ConditionTest(op: op, negated: false), ConditionTest(op: op, negated: true)]
      }
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
    case .mention:
      EmptyView()
    default:
      CommitTextField(placeholder, text: condition.value) { value in
        valueBinding.wrappedValue = value
      }
      .textFieldStyle(.roundedBorder)
      .controlSize(.small)
      .frame(minWidth: 90)
    }
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
    case .provider, .account, .mention: return ""
    }
  }
}

