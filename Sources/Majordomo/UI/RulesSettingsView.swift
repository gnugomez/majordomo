// The Rules settings page: what the on-device model suggests, a field for
// describing a rule in a sentence, and the rules themselves — the
// providers' built-in ones (the sidebar buckets, read-only), the user's
// with their switches, and the editor for the selected one: its filter
// (groups of conditions, Apple Intelligence checks among them — the board
// editor's own FilterEditor), what it applies, and a live preview of the
// items it matches right now. Edits commit whole user rules through the
// model; text commits on submit or blur.

import SwiftUI

/// The editor's fixed height, shared with its placeholder so the page
/// never resizes on selection.
private let editorHeight: CGFloat = 430
/// The filter box grows with what it holds up to this height, then
/// scrolls — a built-in rule's four conditions fit, and a partly visible
/// row below is the scroll cue.
private let filterBoxMaxHeight: CGFloat = 220
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
      if !draftPending, model.suggestionsActive {
        SuggestionsView(model: model)
      }
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
        Menu {
          Button("Rule") {
            add(name: "New Rule", condition: RuleCondition(field: .title, op: .contains))
          }
          Button("Apple Intelligence Rule") {
            add(name: "New Intelligence Rule", condition: .question(""))
          }
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
        RuleEditor(model: model, rule: Binding(get: { rule }, set: { replace($0) }))
      } else if let rule = selectedBuiltin {
        // Read-only: the conditions as they are, nothing to change.
        RuleEditor(model: model, rule: .constant(rule), definedBy: providerName(defining: rule))
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

  /// "2 conditions → Urgent, Infra" for the list row — "any of 2 groups"
  /// when the filter has several, "a question" when the model alone
  /// decides (see summarize).
  private func summary(_ rule: LabelRule) -> String {
    let conditions = summarize(rule.filter)
    let names = rule.labelIds.compactMap { model.label($0)?.name }
    guard !names.isEmpty else {
      return conditions
    }
    let moved = rule.movesItems ? " (moved)" : ""
    return "\(conditions) → \(names.joined(separator: ", "))\(moved)"
  }

  private func replace(_ updated: LabelRule) {
    model.setRules(model.rules.map { $0.id == updated.id ? updated : $0 })
  }

  /// A new rule opening on one condition to fill in — a blank question for
  /// an Apple Intelligence rule, since the whole of it is the user's
  /// wording.
  private func add(name: String, condition: RuleCondition) {
    let rule = LabelRule(
      id: UUID().uuidString, name: name, filter: RuleFilter(conditions: [condition]), labelIds: []
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

/// The selected rule: name, filter, labels, and a live preview of what it
/// matches. A built-in rule (`definedBy` names its provider) shows the
/// same, with every control disabled — the preview stays readable.
private struct RuleEditor: View {
  let model: AppModel
  /// Every change hands the whole rule back, which commits it.
  @Binding var rule: LabelRule
  var definedBy: String?

  /// The filter editor's own height, as laid out; the box around it takes
  /// that much, up to filterBoxMaxHeight.
  @State private var filterHeight: CGFloat = 0

  private var readOnly: Bool { definedBy != nil }

  var body: some View {
    // Compiled once per draw, for the preview and its header alike.
    let matches = inboxOrder(RuleEngine.matching(rule.filter, among: model.items))
    VStack(alignment: .leading, spacing: 8) {
      editingControls
        .disabled(readOnly)

      Text(matchHeader(matches))
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
      List {
        ForEach(matches.prefix(previewCap)) { item in
          MatchRow(item: item, now: model.now)
        }
        if matches.isEmpty {
          Text(emptyPreview)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
      }
      .listStyle(.bordered)
      // The preview takes whatever the rest of the editor leaves: the
      // filter box grows with its rows, and the slack belongs here rather
      // than as dead space under the page.
      .frame(minHeight: previewMinHeight, maxHeight: .infinity)
    }
    .frame(maxHeight: .infinity, alignment: .top)
  }

  /// Name, filter, and labels — everything a user rule lets you change.
  private var editingControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      CommitTextField("Rule name", text: rule.name) { name in
        rule.name = name.isEmpty ? "Untitled" : name
      }
      .textFieldStyle(.roundedBorder)

      ScrollView {
        FilterEditor(
          filter: $rule.filter,
          accounts: model.accounts,
          fields: RuleField.itemFields,
          emptyText: "No conditions: the rule matches nothing yet.",
          questionHint: questionHint(model, subject: "notification")
        )
        .padding(8)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { filterHeight = $0 }
      }
      // A rule of its own each time: the box opens scrolled to the top.
      .id(rule.id)
      .frame(height: min(max(filterHeight, 44), filterBoxMaxHeight))
      .settingsCard()

      Text("Apply to")
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
      // A user rule feeds the user's inboxes and labels; a built-in one
      // fills a built-in inbox, so the read-only view offers those.
      let inboxes = readOnly ? model.catalog.builtinLabels : model.userInboxes
      let labels = model.userLabels
      let choices = inboxes + labels
      RuleTargetRow(
        pills: choices.filter { rule.labelIds.contains($0.id) },
        placeholder: choices.isEmpty ? "Create an inbox or a label first." : "Nothing yet",
        inboxes: inboxes,
        labels: labels,
        help: "Choose the inboxes and labels this rule applies",
        binding: labelBinding
      )

      moveControl
      pinControl
    }
  }

  /// Whether a matching item is moved rather than copied. Moved means it
  /// shows where this rule applies it and nowhere else — no further
  /// choice to make.
  private var moveControl: some View {
    VStack(alignment: .leading, spacing: 2) {
      Toggle(isOn: $rule.movesItems) {
        Text("Show only here")
          .font(.system(size: 12))
      }
      .toggleStyle(.checkbox)
      .controlSize(.small)
      Text("Matching items move into the inboxes above and drop out of every other one, Recent included.")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// Whether what this rule catches rides at the top of Recent, in a box
  /// of its own. The box is the label's, not the rule's: two rules filling
  /// the same label share one.
  private var pinControl: some View {
    VStack(alignment: .leading, spacing: 2) {
      Toggle(isOn: $rule.pinsToTop) {
        Text("Show at the top of Recent")
          .font(.system(size: 12))
      }
      .toggleStyle(.checkbox)
      .controlSize(.small)
      Text("The newest unread ones sit in a box above the list, under the label's name. They stay in the list too.")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// Whether the rule applies one inbox or label.
  private func labelBinding(_ id: LabelId) -> Binding<Bool> {
    Binding(
      get: { rule.labelIds.contains(id) },
      set: { on in
        var labelIds = rule.labelIds.filter { $0 != id }
        if on {
          labelIds.append(id)
        }
        rule.labelIds = labelIds
      }
    )
  }

  /// What the preview's header says: how much the rule takes now, how
  /// much is still waiting on the model — without that, a half-judged
  /// rule looks like a broken one — and why it might be doing nothing.
  private func matchHeader(_ matches: [InboxItem]) -> String {
    guard !rule.filter.isEmpty else {
      return "Add a condition — an empty rule matches nothing"
    }
    let matched = switch matches.count {
    case 0: "No items match yet"
    case 1: "Matches 1 item now"
    default: "Matches \(matches.count) items now"
    }
    return [matched, awaitingNote, stateNote].compactMap { $0 }.joined(separator: " · ")
  }

  /// How many items wait on an answer before the rule can place them.
  private var awaitingNote: String? {
    let waiting = RuleEngine.awaitingModel(rule.filter, among: model.items)
    guard waiting > 0 else {
      return nil
    }
    return "\(waiting) waiting on Apple Intelligence"
  }

  /// Why the rule might be doing nothing, when that isn't its own doing.
  private var stateNote: String? {
    if let definedBy {
      return "built into \(definedBy), read-only"
    }
    return rule.enabled ? nil : "the rule is switched off"
  }

  private var emptyPreview: String {
    if rule.filter.isEmpty {
      return "The preview fills in as you add conditions."
    }
    if rule.filter.asksModel {
      return "Nothing matches yet — Apple Intelligence may still have answers to give."
    }
    return "Nothing in the inbox matches these conditions."
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
      GlyphImage(glyph: spec(for: item.provider).glyph(for: item))
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
