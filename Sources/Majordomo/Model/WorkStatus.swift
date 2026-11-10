// Where a work item stands in its workflow — to do, in progress, done —
// as its provider tracks that apart from the item's open-or-closed state:
// GitLab's work item status, the status of a GitHub project's items.

import Foundation

/// A target's workflow status. The name is the provider's own, custom
/// statuses included; the stage is the token both forges share for the
/// step of the workflow the status stands for, so one rule tests it on
/// every provider.
struct WorkStatus: Codable, Hashable, Sendable {
  /// The status's own name ("To do", "In review").
  var name: String
  /// The stage token ("triage", "todo", "in_progress", "done",
  /// "canceled"); nil for a status whose stage the provider doesn't say.
  var stage: String?
}
