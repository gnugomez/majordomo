// What rule conditions read. A notification is one subject; a board's card
// — a target with every notification about it — is another. Both answer
// the same fields, so one engine and one condition editor serve labels and
// board columns alike.

import Foundation

/// Anything rules can test. A field reads as the values the subject holds
/// for it — one for most fields, several for labels or assignees, none when
/// the subject knows nothing of it — and a test holds when any one of them
/// passes.
protocol RuleSubject {
  func values(of field: RuleField) -> [String]
  /// The answer to a flag field (`isFlag`).
  func flag(_ field: RuleField) -> Bool
  /// The logins `@me` stands for; empty when the subject can't tell.
  var ownLogins: [String] { get }
}

extension InboxItem: RuleSubject {
  /// A missing single value reads as the empty string, which no test
  /// matches but a negated one does.
  func values(of field: RuleField) -> [String] {
    switch field {
    case .repo: [repo]
    case .title: [title]
    case .body: [body ?? ""]
    case .author: [author ?? ""]
    case .kind: [kind]
    case .reason: [reason]
    case .state: [state ?? ""]
    case .provider: [provider.rawValue]
    case .account: [accountId]
    case .upstreamLabel: upstreamLabels
    case .assignee, .reviewer, .review, .checks, .milestone, .lastCommenter, .mention, .unread: []
    }
  }

  func flag(_ field: RuleField) -> Bool {
    switch field {
    case .mention: isMention
    case .unread: !read
    default: false
    }
  }

  var ownLogins: [String] {
    []
  }
}
