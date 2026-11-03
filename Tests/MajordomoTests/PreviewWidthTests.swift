// The preview's widths: one for the inbox and one for the boards, where
// each is kept, what each opens at, and which widths are the user's to
// keep.

import CoreGraphics
import Foundation
import Testing
@testable import Majordomo

@Suite("Preview widths")
@MainActor
struct PreviewWidthTests {
  private let defaults = MemoryDefaults()

  private func stored(_ place: PreviewPlace) -> Double? {
    defaults.object(forKey: place.widthKey) as? Double
  }

  // MARK: Places

  @Test func eachPlaceKeepsItsWidthUnderItsOwnKey() {
    #expect(PreviewPlace(onBoard: false) == .inbox)
    #expect(PreviewPlace(onBoard: true) == .board)
    #expect(PreviewPlace.inbox.other == .board)
    #expect(PreviewPlace.board.other == .inbox)
    // The inbox keeps the key the single width had, so it carries over.
    #expect(PreviewPlace.inbox.widthKey == "previewWidth")
    #expect(PreviewPlace.board.widthKey != PreviewPlace.inbox.widthKey)
  }

  @Test func aBoardOpensNarrowerThanTheInbox() {
    let range = PreviewPlace.widths
    #expect(PreviewPlace.board.standardWidth < PreviewPlace.inbox.standardWidth)
    #expect(range.contains(PreviewPlace.board.standardWidth))
    #expect(range.contains(PreviewPlace.inbox.standardWidth))
  }

  // MARK: Reading

  @Test func aPlaceOpensAtItsStandardWidthUntilOneIsKept() {
    let widths = PreviewWidths(store: defaults)
    #expect(widths.width(in: .inbox) == PreviewPlace.inbox.standardWidth)
    #expect(widths.width(in: .board) == PreviewPlace.board.standardWidth)
    defaults.set(0.0, forKey: PreviewPlace.board.widthKey)
    #expect(widths.width(in: .board) == PreviewPlace.board.standardWidth)
    defaults.set(512.0, forKey: PreviewPlace.inbox.widthKey)
    #expect(widths.width(in: .inbox) == 512)
    #expect(widths.width(in: .board) == PreviewPlace.board.standardWidth)
  }

  @Test func aKeptWidthOpensWithinThePreviewsRange() {
    let widths = PreviewWidths(store: defaults)
    defaults.set(2000.0, forKey: PreviewPlace.inbox.widthKey)
    defaults.set(100.0, forKey: PreviewPlace.board.widthKey)
    #expect(widths.width(in: .inbox) == PreviewPlace.widths.upperBound)
    #expect(widths.width(in: .board) == PreviewPlace.widths.lowerBound)
  }

  // MARK: Noting

  @Test func aDragIsKeptForThePlaceItIsIn() {
    let widths = PreviewWidths(store: defaults)
    widths.note(470, in: .board)
    widths.note(610, in: .inbox)
    #expect(stored(.board) == 470)
    #expect(stored(.inbox) == 610)
    widths.note(455, in: .board)
    #expect(stored(.board) == 455)
    #expect(stored(.inbox) == 610)
  }

  @Test func noWidthIsNotKept() {
    let widths = PreviewWidths(store: defaults)
    widths.note(470, in: .board)
    widths.note(0, in: .board)
    #expect(stored(.board) == 470)
  }

  @Test func theOtherPlacesWidthIsNotKept() {
    // Arriving on a board with the preview open, the inspector keeps the
    // width it had beside the inbox.
    let widths = PreviewWidths(store: defaults)
    widths.note(620, in: .inbox)
    widths.note(450, in: .board)
    widths.note(620, in: .board)
    #expect(stored(.board) == 450)
    // Before the board has a width of its own, its standard width counts.
    let fresh = PreviewWidths(store: MemoryDefaults())
    fresh.note(PreviewPlace.board.standardWidth, in: .inbox)
    #expect(fresh.width(in: .inbox) == PreviewPlace.inbox.standardWidth)
  }
}
