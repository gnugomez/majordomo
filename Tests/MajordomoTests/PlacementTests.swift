// Board placement: the scope, pins that hold and let go, the Done and
// Other windows, the first column that holds, and which questions about a
// card are worth asking.

import Foundation
import Testing
@testable import Majordomo

private let finishedStates: Set<String> = ["closed", "merged"]

private func isFinished(_ card: BoardCard) -> Bool {
  card.state.map(finishedStates.contains) ?? false
}

private func place(_ cards: [BoardCard], on board: Board) -> BoardEngine.Placing {
  BoardEngine.place(cards, on: board, now: referenceDate, isFinished: isFinished)
}

private func column(_ id: String, _ conditions: RuleCondition...) -> BoardColumn {
  BoardColumn(id: id, name: id, filter: RuleFilter(conditions: conditions))
}

private let risky = "Could this break production?"
private let riskyKey = RuleEngine.questionKey(risky)

@Suite("Board placement")
struct PlacementTests {
  private let board = Board(id: "b", name: "Work", symbol: "eye", columns: [
    column("review", condition(.reviewer, .is, "@me")),
    column("mine", condition(.assignee, .is, "@me")),
    column("by-hand"),
  ])

  @Test func firstColumnThatHoldsWins() {
    let both = card("both", assignees: ["octocat"], reviewers: ["octocat"])
    let assigned = card("assigned", assignees: ["octocat"])
    let placement = place([both, assigned], on: board).placement
    #expect(placement.columns["review"]?.map(\.id) == ["both"])
    #expect(placement.columns["mine"]?.map(\.id) == ["assigned"])
    #expect(placement.columns["by-hand"] == nil)
    #expect(placement.count == 2 && placement.unread == 2)
  }

  @Test func otherHoldsRecentCardsNoColumnTakes() {
    let fresh = card("fresh", updatedAt: referenceDate.addingTimeInterval(-days(29)))
    let stale = card("stale", updatedAt: referenceDate.addingTimeInterval(-days(31)))
    let placement = place([fresh, stale], on: board).placement
    #expect(placement.other.map(\.id) == ["fresh"])
    #expect(placement.byId["stale"] == nil)
  }

  @Test func doneHoldsFinishedCardsForItsWindow() {
    var short = board
    short.doneDays = 3
    let recent = card("recent", state: "merged", reviewers: ["octocat"], updatedAt: referenceDate.addingTimeInterval(-days(2)))
    let old = card("old", state: "closed", updatedAt: referenceDate.addingTimeInterval(-days(4)))
    let placement = place([recent, old], on: short).placement
    // Finished beats every column.
    #expect(placement.done.map(\.id) == ["recent"])
    #expect(placement.columns.isEmpty)
    #expect(placement.byId["old"] == nil)
  }

  @Test func pinHoldsWhileTheStateIsUnchanged() {
    var pinned = board
    pinned.pins["c"] = BoardPin(column: "by-hand", state: "open")
    let placement = place([card("c", state: "open", reviewers: ["octocat"])], on: pinned).placement
    #expect(placement.columns["by-hand"]?.map(\.id) == ["c"])
    #expect(placement.pinned == ["c"])
  }

  @Test func pinLetsGoOnceTheStateMovesOn() {
    var pinned = board
    pinned.pins["c"] = BoardPin(column: "by-hand", state: "draft")
    let reopened = place([card("c", state: "open", reviewers: ["octocat"])], on: pinned).placement
    #expect(reopened.columns["review"]?.map(\.id) == ["c"])
    #expect(reopened.pinned.isEmpty)
    let merged = place([card("c", state: "merged")], on: pinned).placement
    #expect(merged.done.map(\.id) == ["c"])
  }

  @Test func pinMadeBeforeTheStateWasKnownHoldsUntilFinished() {
    var pinned = board
    pinned.pins["c"] = BoardPin(column: "by-hand", state: nil)
    #expect(place([card("c", state: "open")], on: pinned).placement.pinned == ["c"])
    #expect(place([card("c", state: "closed")], on: pinned).placement.done.map(\.id) == ["c"])
  }

  @Test func pinToAColumnThatIsGoneIsIgnored() {
    var pinned = board
    pinned.pins["c"] = BoardPin(column: "deleted", state: "open")
    let placement = place([card("c", assignees: ["octocat"])], on: pinned).placement
    #expect(placement.columns["mine"]?.map(\.id) == ["c"])
  }

  @Test func scopeNarrowsTheBoardAndEmptyTakesEverything() {
    let pull = card("pull", items: [item("p:1", kind: "pull")])
    let issue = card("issue", items: [item("i:1", kind: "issue")])
    #expect(place([pull, issue], on: board).placement.count == 2)
    var pulls = board
    pulls.scope = filter(.any, group(.all, condition(.kind, .is, "pull")))
    let placement = place([pull, issue], on: pulls).placement
    #expect(Set(placement.byId.keys) == ["pull"])
  }

  @Test func questionsInColumnsPlaceByTheCardsOwnAnswers() {
    var asking = board
    asking.columns.insert(column("risky", condition(.reviewer, .is, "@me"), .question(risky)), at: 0)
    let yes = card("yes", reviewers: ["octocat"], verdicts: [riskyKey: true])
    let no = card("no", reviewers: ["octocat"], verdicts: [riskyKey: false])
    let unasked = card("unasked", reviewers: ["octocat"])
    let placing = place([yes, no, unasked], on: asking)
    #expect(placing.placement.columns["risky"]?.map(\.id) == ["yes"])
    #expect(placing.placement.columns["review"]?.map(\.id) == ["no", "unasked"])
    #expect(placing.open["unasked"] == [riskyKey])
  }

  @Test func onlyQuestionsThatCanPlaceACardAreAsked() {
    var asking = board
    asking.scope = filter(.any, group(.all, condition(.kind, .is, "issue")))
    // Tried after a column that already takes every reviewer's card.
    asking.columns.insert(column("late", .question(risky)), at: 1)
    let outOfScope = card("pull", items: [item("p:1", kind: "pull")])
    let reviewed = card("reviewed", reviewers: ["octocat"])
    let pinned = card("pinned")
    let finished = card("finished", state: "closed")
    let open = card("open")
    asking.pins["pinned"] = BoardPin(column: "by-hand", state: "open")
    let placing = place([outOfScope, reviewed, pinned, finished, open], on: asking)
    #expect(placing.open == ["open": [riskyKey]])
  }

  @Test func aQuestionInTheScopeIsAskedBeforeAnyColumn() {
    var asking = board
    asking.scope = filter(.any, group(.all, .question(risky)))
    asking.columns.insert(column("late", .question("Is it blocked?")), at: 0)
    let placing = place([card("c")], on: asking)
    #expect(placing.placement.count == 0)
    #expect(placing.open == ["c": [riskyKey]])
  }

  @Test func narrowingKeepsEachCardWhereItWas() {
    let both = card("both", assignees: ["octocat"], reviewers: ["octocat"])
    let assigned = card("assigned", assignees: ["octocat"])
    let placement = place([both, assigned], on: board).placement
    let narrowed = placement.narrowed(to: ["assigned"])
    #expect(narrowed.columns["mine"]?.map(\.id) == ["assigned"])
    #expect(narrowed.columns["review"] == [])
    #expect(narrowed.count == 1)
  }

  @Test func pinningMovesACardAheadOfTheSweep() {
    let older = card("older", assignees: ["octocat"], updatedAt: referenceDate.addingTimeInterval(-60))
    let newer = card("newer", reviewers: ["octocat"])
    let placement = place([newer, older], on: board).placement
    let moved = placement.pinning(newer, to: "mine")
    #expect(moved.columns["mine"]?.map(\.id) == ["newer", "older"])
    #expect(moved.columns["review"] == [])
    #expect(moved.pinned == ["newer"] && moved.count == 2)
  }
}
