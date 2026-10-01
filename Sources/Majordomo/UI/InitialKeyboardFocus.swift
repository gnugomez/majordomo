// The inbox list takes the window's keyboard when it first appears.
//
// SwiftUI hands a NavigationSplitView's first responder to the sidebar and
// offers no way to say otherwise: `defaultFocus` on the split view and a
// `FocusState` on the content column are both ignored. So the list claims
// it through AppKit — a zero-sized backing view finds the table drawn in
// its own frame and gives it the keyboard, once per window. Everything
// after that is ordinary: a click or a tab moves focus wherever the user
// puts it.

import AppKit
import SwiftUI

extension View {
  /// Hands this list the window's keyboard the first time it appears.
  func claimsInitialKeyboardFocus() -> some View {
    background(InitialKeyboardFocus())
  }
}

/// Windows whose list has already claimed the keyboard. The claim is a
/// one-time nudge as the window opens, never a grab of focus the user has
/// since moved somewhere else.
@MainActor
private enum ClaimedWindows {
  static var ids: Set<ObjectIdentifier> = []
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
    // The table is a sibling this view has no handle on, and it may not
    // exist yet on the layout pass that installs this one — so look for it
    // just after, and keep looking briefly before giving up.
    Task { @MainActor in
      for _ in 0 ..< 10 {
        if claim(from: view) {
          return
        }
        try? await Task.sleep(for: .milliseconds(50))
      }
    }
  }

  /// True once the keyboard is settled — handed over, claimed earlier, or
  /// somewhere this has no business taking it from.
  @MainActor
  private func claim(from view: NSView) -> Bool {
    guard let window = view.window else {
      return false
    }
    // A window claims the keyboard once — except when nobody holds it at
    // all, which is where a rebuilt list leaves things: AppKit hands the
    // first responder back to the window when the table holding it goes.
    let unheld = window.firstResponder === window
    guard unheld || !ClaimedWindows.ids.contains(ObjectIdentifier(window)) else {
      return true
    }
    // Never out of a text field: the search field may hold the keyboard by
    // the time a first item arrives, and a keystroke must not go missing.
    if window.firstResponder is NSText {
      return true
    }
    let area = view.convert(view.bounds, to: nil)
    guard !area.isEmpty, let table = tableView(in: window.contentView, within: area) else {
      return false
    }
    ClaimedWindows.ids.insert(ObjectIdentifier(window))
    window.makeFirstResponder(table)
    return true
  }
}

/// The row-drawing view inside this area: the list's own table, told apart
/// from the sidebar's by where it sits.
@MainActor
private func tableView(in view: NSView?, within area: NSRect) -> NSTableView? {
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
