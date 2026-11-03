// The inbox list, or a board, takes the window's keyboard when it first
// appears.
//
// SwiftUI hands a NavigationSplitView's first responder to the sidebar and
// offers no way to say otherwise: `defaultFocus` on the split view and a
// `FocusState` on the content column are both ignored. So the pane claims
// it through AppKit — the list through a zero-sized backing view that
// finds the table drawn in its own frame, a board through the key view it
// draws itself (BoardKeyboard) — once per window. Everything after that is
// ordinary: a click or a tab moves focus wherever the user puts it.

import AppKit
import SwiftUI

extension View {
  /// Hands this list the window's keyboard the first time it appears.
  func claimsInitialKeyboardFocus() -> some View {
    background(InitialKeyboardFocus())
  }
}

/// The claim both panes make, and the windows that have had it. The claim
/// is a one-time nudge as the window opens, never a grab of focus the user
/// has since moved somewhere else.
@MainActor
enum KeyboardClaim {
  private static var claimedWindows: Set<ObjectIdentifier> = []

  /// Hands the keyboard of `view`'s window to what `home` finds there.
  /// What should take it may not exist yet on the pass that asks — the
  /// list's table is a sibling built after its backing view — so this
  /// looks just after, and keeps looking briefly before giving up.
  static func start(from view: NSView, home: @escaping @MainActor (NSWindow) -> NSResponder?) {
    Task { @MainActor in
      for _ in 0 ..< 10 {
        if settle(from: view, home: home) {
          return
        }
        try? await Task.sleep(for: .milliseconds(50))
      }
    }
  }

  /// True once the keyboard is settled — handed over, claimed earlier, or
  /// somewhere this has no business taking it from.
  private static func settle(from view: NSView, home: (NSWindow) -> NSResponder?) -> Bool {
    guard let window = view.window else {
      return false
    }
    // A window claims the keyboard once — except when nobody holds it at
    // all, which is where a rebuilt pane leaves things: AppKit hands the
    // first responder back to the window when the view holding it goes.
    let unheld = window.firstResponder === window
    guard unheld || !claimedWindows.contains(ObjectIdentifier(window)) else {
      return true
    }
    // Never out of a text field: the search field may hold the keyboard by
    // the time a first item arrives, and a keystroke must not go missing.
    if window.firstResponder is NSText {
      return true
    }
    guard let target = home(window) else {
      return false
    }
    claimedWindows.insert(ObjectIdentifier(window))
    window.makeFirstResponder(target)
    return true
  }
}

private struct InitialKeyboardFocus: NSViewRepresentable {
  /// One attempt per backing view: updates arrive on every keystroke the
  /// list reacts to, and each must not start a poll of its own.
  @MainActor
  final class Attempt {
    var started = false
  }

  func makeCoordinator() -> Attempt {
    Attempt()
  }

  func makeNSView(context: Context) -> NSView {
    NSView(frame: .zero)
  }

  func updateNSView(_ view: NSView, context: Context) {
    guard !context.coordinator.started else {
      return
    }
    context.coordinator.started = true
    // The table is a sibling this view has no handle on: found by where
    // it sits, in this view's frame.
    KeyboardClaim.start(from: view) { window in
      let area = view.convert(view.bounds, to: nil)
      return area.isEmpty ? nil : tableView(in: window.contentView, within: area)
    }
  }
}

/// The row-drawing view inside this area: the list's own table, told apart
/// from the sidebar's by where it sits.
@MainActor
func tableView(in view: NSView?, within area: NSRect) -> NSTableView? {
  guard let view else {
    return nil
  }
  if let table = view as? NSTableView, table.convert(table.bounds, to: nil).intersects(area) {
    return table
  }
  for subview in view.subviews {
    if let found = tableView(in: subview, within: area) {
      return found
    }
  }
  return nil
}
