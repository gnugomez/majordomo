// Every label and rule that exists, in one value. The providers define
// built-in inboxes and the rules that fill them; the user defines their own
// labels, inboxes, and rules. Both kinds run through the same engine and
// show in the same sidebar, so nearly everything downstream wants the union
// — and wants it ordered the same way every time, built-ins first. Assembling
// that by hand at each call site is how the orderings drift apart, so it is
// assembled here once. Foundation only: the catalog is handed its built-ins
// rather than reaching for the provider registry.

import Foundation

struct LabelCatalog: Sendable {
  /// The providers' inboxes, merged across providers by whoever builds the
  /// catalog.
  let builtinLabels: [InboxLabel]
  /// The rules that fill them.
  let builtinRules: [LabelRule]
  /// The user's own labels and inboxes together, in their stored order.
  let user: [InboxLabel]
  /// The user's own rules, in evaluation order.
  let userRules: [LabelRule]

  init(
    builtinLabels: [InboxLabel] = [],
    builtinRules: [LabelRule] = [],
    user: [InboxLabel] = [],
    userRules: [LabelRule] = []
  ) {
    self.builtinLabels = builtinLabels
    self.builtinRules = builtinRules
    self.user = user
    self.userRules = userRules
  }

  /// Every label and inbox, built-ins first — the order the sidebar and
  /// the settings pages list them in.
  var labels: [InboxLabel] {
    builtinLabels + user
  }

  /// Every rule the engine runs. Rules are independent and their labels
  /// union, so this order is for reading, not for precedence.
  var rules: [LabelRule] {
    builtinRules + userRules
  }

  /// The user's tags: pills on rows, applied by hand, the Labels page.
  var userLabels: [InboxLabel] {
    user.filter { $0.kind == .label }
  }

  /// The user's own inboxes: rule-fed buckets seen only in the sidebar,
  /// made and edited on the Inboxes page.
  var userInboxes: [InboxLabel] {
    user.filter { $0.kind == .inbox }
  }

  /// What the providers define — the ids the store must keep out of a
  /// user-label edit, since they live in code and not in the file.
  var builtinIds: Set<LabelId> {
    Set(builtinLabels.map(\.id))
  }

  /// Every id that exists, built-in or the user's.
  var ids: Set<LabelId> {
    Set(labels.map(\.id))
  }

  /// One label by id, whoever defined it.
  func label(_ id: LabelId) -> InboxLabel? {
    labels.first { $0.id == id }
  }
}
