// The engine's reactions: what each change sets off, that a turn's
// changes go out as one push carrying only the slices they moved, and the
// events a sync tells its subscribers.

import Foundation
import Testing
@testable import Majordomo

private let urgent = "Is this urgent?"

@Suite("Reaction table")
struct ReactionTableTests {
  @Test func readStateOnlyPlaces() {
    #expect(EngineChange.readState.reactions == [.place])
    #expect(EngineChange.readState.slices == [.items])
  }

  @Test func ruleChangeRelabelsAndAsksAgain() {
    let reactions = EngineChange.rules.reactions
    #expect(reactions.contains(.relabel))
    #expect(reactions.contains(.forgetAnswers))
    #expect(reactions.contains(.askQuestions))
  }

  @Test func pinChangePlacesWithoutRelabeling() {
    #expect(EngineChange.pins.reactions == [.place])
    #expect(EngineChange.pins.echoes == [.boards, .placements])
  }

  @Test func everySyncPlacesForTheClock() {
    let reactions = EngineChange.synced.reactions
    #expect(reactions.contains(.place))
    #expect(!reactions.contains(.relabel))
    #expect(reactions.contains(.refreshTargets))
  }

  @Test func changesUnion() {
    let changes: Set<EngineChange> = [.readState, .labels]
    #expect(changes.reactions == [.relabel, .place, .reconcileSidebar])
    #expect(changes.slices == [.items, .labels, .rules, .sidebar])
    #expect(changes.echoes == [.labels])
  }
}

@Suite("Engine")
struct EngineTests {
  private func launched(_ store: sending Store, client: ScriptedClient? = nil) async -> SyncEngine {
    let engine = SyncEngine(store: store, clients: client.map { [.github: $0] } ?? [:], offline: client == nil)
    await engine.start()
    await engine.settle()
    return engine
  }

  @Test func turnOfReadsPushesOnce() async {
    let engine = await launched(fixtureStore(items: [storedItem(1), storedItem(2), storedItem(3)]))
    let states = await engine.states(buffering: .unbounded)
    await engine.markEachRead(["acct:1", "acct:2", "acct:3"])
    await engine.settle()
    await engine.stop()
    let pushes = await collect(states)
    // The latest push on subscribing, then the reads' one.
    #expect(pushes.count == 2)
    guard pushes.count == 2 else {
      return
    }
    let moved = pushes[1].revisions.moved(since: pushes[0].revisions)
    #expect(moved.contains(.items))
    #expect(moved.isSubset(of: [.items, .placements]))
    #expect(pushes[1].items.allSatisfy { $0.read })
  }

  @Test func ruleChangeRelabelsAndAsksTheModel() async {
    let model = YesModel()
    let engine = await launched(fixtureStore(items: [storedItem(1)], labels: [userLabel("app"), userLabel("hot")]))
    await engine.setIntelligence(model)
    await engine.setRules([
      LabelRule(id: "r1", name: "App", filter: RuleFilter(conditions: [condition(.repo, .is, "acme/app")]), labelIds: ["app"]),
      LabelRule(id: "r2", name: "Hot", filter: RuleFilter(conditions: [.question(urgent)]), labelIds: ["hot"]),
    ])
    await engine.settle()
    let labeled = await engine.currentState().items.first?.labels ?? []
    #expect(labeled.contains("app"))
    // The question goes to the model, and its answer labels the item.
    #expect(await eventually { model.questionsAsked == 1 })
    #expect(await eventually { await engine.currentState().items.first?.labels.contains("hot") == true })
    await engine.stop()
  }

  @Test func pinMovesTheCardAndLeavesTheLabels() async {
    let board = Board(id: "b", name: "Work", symbol: "eye", columns: [
      BoardColumn(id: "mine", name: "Mine", filter: RuleFilter(conditions: [condition(.repo, .is, "acme/app")])),
      BoardColumn(id: "later", name: "Later"),
    ])
    let engine = await launched(fixtureStore(items: [storedItem(1)], boards: [board]))
    let before = await engine.currentState()
    let card = "https://github.com/acme/app/issues/1"
    #expect(before.placements["b"]?.columns["mine"]?.map(\.id) == [card])
    await engine.setPin(board: "b", card: card, column: "later", state: "open")
    await engine.settle()
    let after = await engine.currentState()
    #expect(after.placements["b"]?.columns["later"]?.map(\.id) == [card])
    let moved = after.revisions.moved(since: before.revisions)
    #expect(moved == [.boards, .placements])
    await engine.stop()
  }

  @Test func syncAnnouncesFreshThreadsOncePerThread() async {
    let known = storedItem(1, updatedAt: Date().addingTimeInterval(-3600))
    var comment = storedItem(2)
    var mention = storedItem(3, mention: true)
    // Two notifications about one target: one banner, fronted by the
    // mention.
    mention.url = comment.url + "#issuecomment-1"
    comment.title = mention.title
    let client = ScriptedClient([
      .success(FetchResult(items: [fetched(known), fetched(comment), fetched(mention)], complete: false)),
    ])
    let engine = await launched(fixtureStore(items: [known]), client: client)
    let events = await engine.events()
    await engine.syncNow(depth: .recent)
    await engine.settle()
    await engine.stop()
    let told = await collect(events)
    #expect(told.count == 1)
    guard case .threadsArrived(let fronts) = told.first else {
      Issue.record("expected arrivals, got \(told)")
      return
    }
    #expect(fronts.map(\.id) == ["acct:3"])
  }

  @Test func firstSyncSeedsSilently() async {
    let client = ScriptedClient([.success(FetchResult(items: [fetched(storedItem(1))], complete: false))])
    let engine = await launched(fixtureStore(), client: client)
    let events = await engine.events()
    await engine.syncNow(depth: .recent)
    await engine.settle()
    await engine.stop()
    #expect(await collect(events).isEmpty)
    #expect(await engine.currentState().items.map(\.id) == ["acct:1"])
  }

  @Test func accountFailuresAndRecoveryAreTold() async {
    let client = ScriptedClient([
      .failure(ProviderError(message: "GitHub is having trouble right now.")),
      .success(FetchResult(items: [], complete: false)),
      .failure(ProviderError(message: "GitHub token was rejected (401).", rejectsToken: true)),
      .failure(ProviderError(message: "GitHub token was rejected (401).", rejectsToken: true)),
    ])
    let engine = await launched(fixtureStore(items: [storedItem(1)]), client: client)
    let events = await engine.events()
    for _ in 0 ..< 4 {
      await engine.syncNow(depth: .recent)
    }
    await engine.stop()
    // The same failure twice is told once.
    #expect(await collect(events) == [
      .syncFailed("acct", reason: "GitHub is having trouble right now."),
      .accountRecovered("acct"),
      .tokenRejected("acct", reason: "GitHub token was rejected (401)."),
    ])
    #expect(await engine.currentState().accounts.first?.error == "GitHub token was rejected (401).")
  }
}
