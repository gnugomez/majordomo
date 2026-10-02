// A mouse wheel moves the inbox a row's worth per notch.
//
// A wheel notch scrolls by the scroll view's line height, and the table
// sets that to its own row height on every tile. The list's row height is
// the lowered `defaultMinListRowHeight` the resting spotlight needs — a
// single point — which would move the inbox a point per notch. This sets
// the line to a row's height and holds it there across the re-tiles.
// Trackpads scroll by exact distances and never read the line.

import AppKit
import SwiftUI

/// What one wheel notch scrolls: the line the table sets for itself under
/// the standard row floor.
private let wheelLineScroll: CGFloat = 24

extension View {
  /// Gives this list's scroll view a row-high wheel line.
  func wheelScrollsByRow() -> some View {
    background(WheelLineScroll())
  }
}

private struct WheelLineScroll: NSViewRepresentable {
  /// Holds the watch on the scroll view the table lives in.
  @MainActor
  final class Hold {
    var started = false
    var observation: NSKeyValueObservation?
  }

  func makeCoordinator() -> Hold {
    Hold()
  }

  func makeNSView(context: Context) -> NSView {
    NSView(frame: .zero)
  }

  func updateNSView(_ view: NSView, context: Context) {
    let hold = context.coordinator
    guard !hold.started else {
      return
    }
    hold.started = true
    // The table is a sibling, and may not exist yet on the pass that
    // installs this view — look just after, and briefly keep looking.
    Task { @MainActor in
      for _ in 0 ..< 10 {
        if let scroll = scrollView(around: view) {
          hold.observation = holdLine(of: scroll)
          return
        }
        try? await Task.sleep(for: .milliseconds(50))
      }
    }
  }

  static func dismantleNSView(_ view: NSView, coordinator: Hold) {
    coordinator.observation?.invalidate()
  }

  /// The scroll view of the table drawn in this view's frame.
  @MainActor
  private func scrollView(around view: NSView) -> NSScrollView? {
    guard let window = view.window else {
      return nil
    }
    let area = view.convert(view.bounds, to: nil)
    guard !area.isEmpty else {
      return nil
    }
    return tableView(in: window.contentView, within: area)?.enclosingScrollView
  }

  /// Sets the wheel line now and again whenever a re-tile resets it.
  @MainActor
  private func holdLine(of scroll: NSScrollView) -> NSKeyValueObservation {
    scroll.verticalLineScroll = wheelLineScroll
    return scroll.observe(\.verticalLineScroll) { scroll, _ in
      MainActor.assumeIsolated {
        if scroll.verticalLineScroll != wheelLineScroll {
          scroll.verticalLineScroll = wheelLineScroll
        }
      }
    }
  }
}
