// The status-bar icons: the same template PNGs the Electron app renders
// (pure black + alpha; the system recolors them for menu bar state and
// appearance). 1x and 2x reps are folded into one NSImage by hand — the
// PNGs live loose in the SPM resource bundle, outside NSImage's automatic
// @2x pairing.

import AppKit

/// The SPM resource bundle. Packaged apps carry it in Contents/Resources
/// (scripts/bundle.sh puts it there), but the accessor SwiftPM generates for
/// executable targets only checks the app root and the machine-specific
/// build directory — fine under `swift run`, a launch-time crash in an
/// installed app. Resolve Resources first; only the dev case ever touches
/// Bundle.module (whose accessor traps when it can't resolve).
private let resources: Bundle = {
  if let url = Bundle.main.resourceURL?.appendingPathComponent("Majordomo_Majordomo.bundle"),
     let bundle = Bundle(url: url) {
    return bundle
  }
  return .module
}()

@MainActor
enum TrayIcon {
  static let normal = load("trayTemplate")
  static let dot = load("trayDotTemplate")

  private static func load(_ name: String) -> NSImage {
    let image = NSImage(size: NSSize(width: 16, height: 16))
    for suffix in ["", "@2x"] {
      if let url = resources.url(forResource: name + suffix, withExtension: "png"),
         let rep = NSImageRep(contentsOf: url) {
        rep.size = NSSize(width: 16, height: 16)
        image.addRepresentation(rep)
      }
    }
    image.isTemplate = true
    return image
  }
}
