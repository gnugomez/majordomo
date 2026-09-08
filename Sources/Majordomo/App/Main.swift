// Entry point. A menu-bar app (accessory activation policy) with an
// AppKit-managed lifecycle: SwiftUI owns every view, but the status item and
// its windows are opened from AppKit, which a SwiftUI App scene can't do.

import AppKit

@main
enum Main {
  static func main() {
    // main() always starts on the main thread.
    MainActor.assumeIsolated {
      let app = NSApplication.shared
      let delegate = AppDelegate()
      app.delegate = delegate
      app.setActivationPolicy(.accessory)
      app.run()
      // app.run() never returns, but keep the delegate rooted regardless:
      // NSApplication.delegate is an unowned reference.
      withExtendedLifetime(delegate) {}
    }
  }
}
