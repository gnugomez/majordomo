// The name a picture's bytes get for Quick Look: the address's own, with
// the extension the bytes call for when it has none that fits.

import AppKit
import Foundation
import Testing
@testable import Majordomo

@Suite("Quick Look files")
struct QuickLookFileTests {
  private let png: Data = {
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
      hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    return bitmap.representation(using: .png, properties: [:])!
  }()

  @Test func anAddressEndingInAnIdGetsTheExtensionItsBytesCallFor() {
    let url = URL(string: "https://github.com/user-attachments/assets/0a1b2c3d-4e5f")!
    #expect(QuickLookFiles.name(for: url, data: png) == "0a1b2c3d-4e5f.png")
  }

  @Test func aFittingExtensionStays() {
    let url = URL(string: "https://example.com/uploads/shot.PNG")!
    #expect(QuickLookFiles.name(for: url, data: png) == "shot.PNG")
  }

  @Test func anExtensionTheBytesBelieGetsAnotherAfterIt() {
    let url = URL(string: "https://example.com/uploads/shot.gif")!
    #expect(QuickLookFiles.name(for: url, data: png) == "shot.gif.png")
  }

  @Test func anSVGIsToldByItsText() {
    let svg = Data("<?xml version=\"1.0\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>".utf8)
    #expect(QuickLookFiles.name(for: URL(string: "https://example.com/logo")!, data: svg) == "logo.svg")
  }

  @Test func unknownBytesKeepTheAddressesName() {
    let bytes = Data([0, 1, 2, 3])
    #expect(QuickLookFiles.name(for: URL(string: "https://example.com/file.bin")!, data: bytes) == "file.bin")
    #expect(QuickLookFiles.name(for: URL(string: "https://example.com/")!, data: bytes) == "image")
    #expect(QuickLookFiles.name(for: URL(string: "https://example.com/.hidden")!, data: bytes) == "hidden")
  }
}
