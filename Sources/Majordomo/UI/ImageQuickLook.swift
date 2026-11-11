// A body's picture, clicked, in Quick Look: the system's own preview
// panel, zooming out of the picture's place in the pane, over the bytes
// the preview fetched through the account — so a picture from a private
// repository shows as well as a public one, and a GIF plays. Quick Look
// reads files and tells their kind by the extension, so the bytes go to a
// file of their own under the app's temporary folder, named as the body's
// address names the picture with the extension its bytes call for; the
// folder is emptied the first time it is used after a launch. The panel
// finds its controller down the responder chain from the key window:
// MainWindowController hands it here.

import AppKit
import CryptoKit
import ImageIO
import os
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

private let log = Logger(subsystem: "dev.majordomo.app", category: "quicklook")

/// The one picture the panel shows at a time, and what it zooms from.
@MainActor
final class ImageQuickLook: NSObject {
  static let shared = ImageQuickLook()

  private var item: QuickLookImage?
  /// Where the picture stands on screen, for the panel's zoom.
  private var sourceFrame = NSRect.zero
  /// The picture as the pane draws it, for the zoom's first frame.
  private var transition: NSImage?

  /// Shows `file` in the panel, opening it or turning the open one to it.
  func show(_ file: URL, title: String, from frame: NSRect, transition: NSImage?) {
    item = QuickLookImage(url: file, title: title)
    sourceFrame = frame
    self.transition = transition
    guard let panel = QLPreviewPanel.shared() else {
      return
    }
    if !panel.isVisible {
      // Finds the controller down the responder chain (`control`).
      panel.makeKeyAndOrderFront(nil)
    }
    panel.reloadData()
  }

  /// The panel's controller takes it, from the responder chain, as the
  /// panel opens over the main window.
  func control(_ panel: QLPreviewPanel) {
    panel.dataSource = self
    panel.delegate = self
  }

  func release(_ panel: QLPreviewPanel) {
    panel.dataSource = nil
    panel.delegate = nil
  }
}

// The panel calls on the main thread; the protocols don't say so.
extension ImageQuickLook: @preconcurrency QLPreviewPanelDataSource {
  func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
    item == nil ? 0 : 1
  }

  func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
    item
  }
}

extension ImageQuickLook: @preconcurrency QLPreviewPanelDelegate {
  func previewPanel(_ panel: QLPreviewPanel!, sourceFrameOnScreenFor item: (any QLPreviewItem)!) -> NSRect {
    sourceFrame
  }

  func previewPanel(
    _ panel: QLPreviewPanel!, transitionImageFor item: (any QLPreviewItem)!, contentRect: UnsafeMutablePointer<NSRect>!
  ) -> Any! {
    transition
  }
}

/// A file for the panel, titled as the body names the picture.
private final class QuickLookImage: NSObject, QLPreviewItem {
  let previewItemURL: URL!
  let previewItemTitle: String!

  init(url: URL, title: String) {
    previewItemURL = url
    previewItemTitle = title
  }
}

/// The files the panel reads: a picture's bytes, written once per address
/// under the app's temporary folder, each in a folder of its own so two
/// pictures of one name don't collide.
actor QuickLookFiles {
  static let shared = QuickLookFiles(
    directory: FileManager.default.temporaryDirectory.appending(path: "dev.majordomo.app/QuickLook")
  )

  private let directory: URL
  /// Whether this launch has emptied the folder of what earlier ones left.
  private var emptied = false

  init(directory: URL) {
    self.directory = directory
  }

  /// The file holding `data`, named for `url`; nil when it can't be
  /// written.
  func file(for url: URL, data: Data) -> URL? {
    if !emptied {
      try? FileManager.default.removeItem(at: directory)
      emptied = true
    }
    let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
    let folder = directory.appending(path: digest.prefix(8).map { String(format: "%02x", $0) }.joined())
    let file = folder.appending(path: Self.name(for: url, data: data))
    if FileManager.default.fileExists(atPath: file.path) {
      return file
    }
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      try data.write(to: file, options: .atomic)
      return file
    } catch {
      log.error("failed to write an image for Quick Look: \(error)")
      return nil
    }
  }

  /// The picture's name for the panel and for Preview, should the user
  /// open it there: the address's last part, given the extension its
  /// bytes call for when it has none that fits — an address often ends in
  /// an id (GitHub's attachments), or in `.png` serving a GIF.
  static func name(for url: URL, data: Data) -> String {
    var base = url.lastPathComponent
    base = String(base.drop { $0 == "." }).replacingOccurrences(of: ":", with: "-")
    if base.isEmpty || base == "/" {
      base = "image"
    }
    base = String(base.prefix(100))
    guard let type = contentType(of: data) else {
      return base
    }
    let extensions = type.tags[.filenameExtension] ?? []
    let current = (base as NSString).pathExtension.lowercased()
    if !current.isEmpty, extensions.contains(current) {
      return base
    }
    guard let preferred = type.preferredFilenameExtension else {
      return base
    }
    return "\(base).\(preferred)"
  }

  /// What the bytes are, as ImageIO reads them; an SVG, which it doesn't,
  /// by its text.
  private static func contentType(of data: Data) -> UTType? {
    if let source = CGImageSourceCreateWithData(data as CFData, nil),
       let identifier = CGImageSourceGetType(source) as String?,
       let type = UTType(identifier) {
      return type
    }
    let head = String(decoding: data.prefix(512), as: UTF8.self).lowercased()
    if head.contains("<svg") {
      return .svg
    }
    return nil
  }
}

/// Where a view stands on screen, read when a click asks: a view of
/// AppKit's in its background, out of hit testing, that knows its window.
/// Nothing tracks the frame through every scroll step.
@MainActor
final class ScreenAnchor {
  fileprivate weak var view: NSView?

  var frame: NSRect? {
    guard let view, let window = view.window else {
      return nil
    }
    return window.convertToScreen(view.convert(view.bounds, to: nil))
  }
}

struct ScreenAnchorView: NSViewRepresentable {
  let anchor: ScreenAnchor

  func makeNSView(context: Context) -> NSView {
    let view = PassThroughView()
    anchor.view = view
    return view
  }

  func updateNSView(_ view: NSView, context: Context) {
    anchor.view = view
  }

  /// Draws nothing and takes no clicks: the picture over it does.
  private final class PassThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
      nil
    }
  }
}
