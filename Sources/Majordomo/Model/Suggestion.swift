// Suggested labels and rules. Candidates are mined here, deterministically:
// a pattern is a group of items sharing a repo, an author, or a repo and
// reason, big enough and spread over enough days to look like a habit
// rather than a burst. Only then is the on-device model asked whether the
// pattern deserves a label and what to call it — so the model judges a
// handful of candidates instead of reading the whole inbox, and the same
// inbox always yields the same candidates. Foundation only.

import Foundation

/// A pattern worth considering, before the model has an opinion.
struct SuggestionCandidate: Hashable, Sendable {
  /// The field the pattern is expressed in.
  var field: RuleField
  /// The shared value — a repo path, an author login.
  var value: String
  /// A second test that narrows it (a reason token alongside a repo).
  var secondField: RuleField?
  var secondValue: String?
  /// How many items share it.
  var count: Int
  /// How many days separate its oldest and newest item.
  var spanDays: Int
  /// A few titles, for the model to read.
  var sampleTitles: [String]

  /// Stable across launches and item churn: what a dismissal remembers and
  /// what keeps the same pattern from being suggested twice.
  var signature: String {
    let second = secondField.map { "\($0.rawValue)=\(secondValue ?? "")" } ?? ""
    return "\(field.rawValue)=\(value.lowercased())|\(second.lowercased())"
  }

  /// The conditions a rule for this pattern would carry.
  var conditions: [RuleCondition] {
    var list = [RuleCondition(field: field, op: .is, value: value)]
    if let secondField, let secondValue {
      list.append(RuleCondition(field: secondField, op: .is, value: secondValue))
    }
    return list
  }
}

/// A suggestion the user hasn't answered yet, or has dismissed. Accepted
/// ones become a label and a rule and stop being suggestions.
struct Suggestion: Identifiable, Codable, Hashable, Sendable {
  var id: String
  /// The candidate's signature — dismissal is remembered by this.
  var signature: String
  /// What the rule would be called.
  var name: String
  /// The label or inbox it would fill.
  var targetName: String
  var targetKind: LabelKind
  var targetSymbol: String
  var targetTint: LabelTint
  /// One sentence for the user: why this is being offered.
  var rationale: String
  var conditions: [RuleCondition]
  var matchCount: Int
  var createdAt: Date
  var dismissed: Bool = false
}

/// How big and how spread a pattern must be before it is worth a word.
private let minimumCount = 5
private let minimumSpanDays = 3
/// Candidates handed to the model per sweep; the rest wait.
let suggestionCandidateBudget = 4

/// Patterns among items no user rule already covers, strongest first.
/// `coveredValues` holds what existing user rules already test for, so the
/// same repo is never suggested twice; `dismissed` holds the signatures the
/// user has said no to.
func suggestionCandidates(
  in items: [InboxItem],
  coveredSignatures: Set<String>,
  dismissed: Set<String>,
  now: Date = Date()
) -> [SuggestionCandidate] {
  // Items already carrying a user label or inbox are handled; they say
  // nothing about what is missing.
  let uncovered = items.filter { $0.labels.isEmpty }
  guard uncovered.count >= minimumCount else {
    return []
  }
  var groups: [String: [InboxItem]] = [:]
  var keyed: [String: (field: RuleField, value: String, second: (RuleField, String)?)] = [:]

  func add(_ item: InboxItem, field: RuleField, value: String, second: (RuleField, String)? = nil) {
    guard !value.isEmpty else {
      return
    }
    let secondPart = second.map { "\($0.0.rawValue)=\($0.1.lowercased())" } ?? ""
    let key = "\(field.rawValue)=\(value.lowercased())|\(secondPart)"
    groups[key, default: []].append(item)
    keyed[key] = (field, value, second)
  }

  for item in uncovered {
    add(item, field: .repo, value: item.repo)
    if let author = item.author {
      add(item, field: .author, value: author)
    }
    add(item, field: .repo, value: item.repo, second: (.reason, item.reason))
  }

  let day: TimeInterval = 24 * 60 * 60
  return groups.compactMap { key, members -> SuggestionCandidate? in
    guard members.count >= minimumCount, let shape = keyed[key] else {
      return nil
    }
    let dates = members.map(\.updatedAt)
    let span = Int(((dates.max() ?? now).timeIntervalSince(dates.min() ?? now)) / day)
    guard span >= minimumSpanDays else {
      return nil
    }
    let candidate = SuggestionCandidate(
      field: shape.field,
      value: shape.value,
      secondField: shape.second?.0,
      secondValue: shape.second?.1,
      count: members.count,
      spanDays: span,
      sampleTitles: members.sorted { $0.updatedAt > $1.updatedAt }.prefix(3).map(\.title)
    )
    guard !dismissed.contains(candidate.signature), !coveredSignatures.contains(candidate.signature) else {
      return nil
    }
    return candidate
  }
  // Biggest first; ties by the wider span, then the signature so the order
  // never wobbles between sweeps.
  .sorted { a, b in
    if a.count != b.count {
      return a.count > b.count
    }
    if a.spanDays != b.spanDays {
      return a.spanDays > b.spanDays
    }
    return a.signature < b.signature
  }
}

/// What the user's existing rules already test for, in candidate-signature
/// form, so a pattern they have already handled is never offered again.
func coveredSignatures(in rules: [LabelRule]) -> Set<String> {
  var covered = Set<String>()
  for rule in rules {
    let single = rule.conditions.filter { $0.op == .is && !$0.negated }
    for condition in single {
      covered.insert("\(condition.field.rawValue)=\(condition.value.lowercased())|")
    }
    if single.count == 2 {
      let pair = single.sorted { $0.field.rawValue < $1.field.rawValue }
      covered.insert(
        "\(pair[0].field.rawValue)=\(pair[0].value.lowercased())|\(pair[1].field.rawValue)=\(pair[1].value.lowercased())"
      )
    }
  }
  return covered
}
