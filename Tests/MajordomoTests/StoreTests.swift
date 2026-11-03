// Saving: a change is only noted, a flush writes everything noted since
// the last one in one go, and the engine flushes a moment after a change
// and again when it stops.

import Foundation
import Testing
@testable import Majordomo

/// A fresh directory for one test's store.
private func scratchDirectory() -> URL {
  FileManager.default.temporaryDirectory.appending(path: "majordomo-tests-\(UUID().uuidString)")
}

private func storeFile(in directory: URL) -> URL {
  directory.appending(path: "majordomo.json")
}

@Suite("Store saves")
struct StoreTests {
  @Test func changesWaitForTheFlush() async {
    let directory = scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = Store(directory: directory)
    store.setLabels([userLabel("work")])
    store.setRules([LabelRule(id: "r", name: "r", filter: RuleFilter(), labelIds: ["work"])])
    store.seedBoards([Board(id: "b", name: "Work", symbol: "eye", columns: [])], firstSet: [])
    #expect(store.hasUnsavedChanges)
    #expect(!FileManager.default.fileExists(atPath: storeFile(in: directory).path))

    store.flush()
    #expect(!store.hasUnsavedChanges)
    await store.writer?.drain()
    let reopened = Store(directory: directory)
    #expect(reopened.labels().map(\.id) == ["work"])
    #expect(reopened.rules().map(\.id) == ["r"])
    #expect(reopened.boards().map(\.id) == ["b"])
  }

  @Test func aFlushWithNothingNewWritesNothing() async {
    let directory = scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = Store(directory: directory)
    store.flush()
    await store.writer?.drain()
    #expect(!FileManager.default.fileExists(atPath: storeFile(in: directory).path))
  }

  @Test func theFixtureStoreNeverWrites() {
    let store = fixtureStore()
    store.setLabels([userLabel("work")])
    #expect(!store.hasUnsavedChanges)
    #expect(store.writer == nil)
  }

  @Test func engineSavesAMomentAfterAChange() async {
    let directory = scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let engine = SyncEngine(store: Store(directory: directory), clients: [:], offline: true, saveDelay: .milliseconds(50))
    await engine.setLabels([userLabel("work")])
    await engine.settle()
    let file = storeFile(in: directory)
    #expect(await eventually { FileManager.default.fileExists(atPath: file.path) })
    await engine.stop()
    #expect(Store(directory: directory).labels().map(\.id) == ["work"])
  }

  @Test func engineWritesEverythingWhenItStops() async {
    let directory = scratchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let engine = SyncEngine(store: Store(directory: directory), clients: [:], offline: true, saveDelay: .seconds(60))
    await engine.setLabels([userLabel("work")])
    await engine.setRules([LabelRule(id: "r", name: "r", filter: RuleFilter(), labelIds: ["work"])])
    #expect(!FileManager.default.fileExists(atPath: storeFile(in: directory).path))
    await engine.stop()
    let reopened = Store(directory: directory)
    #expect(reopened.labels().map(\.id) == ["work"])
    #expect(reopened.rules().map(\.id) == ["r"])
  }
}
