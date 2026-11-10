// A GitHub project gives its statuses no stage of their own, so the
// client reads one off the name.

import Testing
@testable import Majordomo

@Suite("Project status names")
struct StatusStageTests {
  @Test func aProjectsOwnStatusesReadTheirStage() {
    #expect(projectStatusStage("Todo") == "todo")
    #expect(projectStatusStage("In Progress") == "in_progress")
    #expect(projectStatusStage("Done") == "done")
  }

  @Test func addedStatusesReadTheStepTheyName() {
    #expect(projectStatusStage("Backlog") == "todo")
    #expect(projectStatusStage("In review") == "in_progress")
    #expect(projectStatusStage("Won't fix") == "canceled")
    #expect(projectStatusStage("Not planned") == "canceled")
    #expect(projectStatusStage("Needs triage") == "triage")
    #expect(projectStatusStage("Shipped 🚀") == "done")
  }

  @Test func aNameThatSaysNothingLeavesTheStageUnsaid() {
    #expect(projectStatusStage("Q3") == nil)
    #expect(projectStatusStage("") == nil)
  }
}
