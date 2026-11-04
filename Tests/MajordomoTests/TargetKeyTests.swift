// Which notification urls make a board card, and the key the card goes
// by: one per issue, pull or merge request, whichever address names it.

import Testing
@testable import Majordomo

@Suite("Target keys")
struct TargetKeyTests {
  @Test func issuesPullsAndMergeRequestsKeyWithoutTheirAnchor() {
    let issue = GitForgeVisuals.targetUrl("https://github.com/acme/app/issues/12#issuecomment-99")
    #expect(issue?.key == "https://github.com/acme/app/issues/12")
    #expect(issue?.reference == "#12")
    #expect(GitForgeVisuals.targetUrl("https://github.com/acme/app/pull/7")?.reference == "#7")
    let merge = GitForgeVisuals.targetUrl("https://gitlab.example.com/acme/app/-/merge_requests/58#note_3")
    #expect(merge?.key == "https://gitlab.example.com/acme/app/-/merge_requests/58")
    #expect(merge?.reference == "!58")
  }

  @Test func aWorkItemKeysAsTheIssueItIs() {
    let workItem = GitForgeVisuals.targetUrl("https://gitlab.example.com/acme/api/app/-/work_items/42#note_7")
    #expect(workItem?.key == "https://gitlab.example.com/acme/api/app/-/issues/42")
    #expect(workItem?.reference == "#42")
    #expect(GitForgeVisuals.targetUrl("https://gitlab.example.com/acme/api/app/-/issues/42")?.key == workItem?.key)
  }

  @Test func aGroupsWorkItemMakesNoKey() {
    #expect(GitForgeVisuals.targetUrl("https://gitlab.example.com/groups/acme/-/work_items/5") == nil)
    // A project in a subgroup named "groups" is still a project.
    #expect(GitForgeVisuals.targetUrl("https://gitlab.example.com/acme/groups/app/-/work_items/5") != nil)
  }

  @Test func otherPagesMakeNoKey() {
    #expect(GitForgeVisuals.targetUrl("https://github.com/acme/app") == nil)
    #expect(GitForgeVisuals.targetUrl("https://github.com/acme/app/releases/397938427") == nil)
    #expect(GitForgeVisuals.targetUrl("https://github.com/acme/app/discussions/3") == nil)
    #expect(GitForgeVisuals.targetUrl("https://gitlab.example.com/acme/app/-/work_items/") == nil)
  }
}
