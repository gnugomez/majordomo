// The status-bar icons: the same template PNGs the Electron app renders
// (pure black + alpha; the system recolors them for menu bar state and
// appearance). 1x and 2x reps are folded into one NSImage by hand — the
// PNGs live loose in the SPM resource bundle, outside NSImage's automatic
// @2x pairing.

import AppKit

@MainActor
enum TrayIcon {
  static let normal = load("trayTemplate")
  static let dot = load("trayDotTemplate")

  private static func load(_ name: String) -> NSImage {
    let image = NSImage(size: NSSize(width: 16, height: 16))
    for suffix in ["", "@2x"] {
      if let url = Bundle.module.url(forResource: name + suffix, withExtension: "png"),
         let rep = NSImageRep(contentsOf: url) {
        rep.size = NSSize(width: 16, height: 16)
        image.addRepresentation(rep)
      }
    }
    image.isTemplate = true
    return image
  }
}
