// A board's keyboard: an AppKit view laid behind the grid that can hold
// the window's first responder, reading the keys a board answers — the
// arrows, Return and ⌘↓, Space, Escape — and handing each to the board.
// An AppKit view rather than a SwiftUI focusable: the window gives its
// keyboard to the sidebar first, and SwiftUI's focus can't take it back
// (see InitialKeyboardFocus), so the board claims it the way the inbox
// list does, with a view AppKit can make first responder. The view takes
// no clicks; a click on a card or on the board's space hands it the
// keyboard (`BoardFocus.take`). It draws no focus ring — the selected
// card's outline says where the keys are.

import AppKit
import SwiftUI

/// A key a board answers.
enum BoardKey: Equatable {
  /// An arrow.
  case move(BoardMove)
  /// Return or ⌘↓: the selected card opens in the browser.
  case open
  /// Space: the selected card's preview shows or goes away.
  case togglePreview
  /// Escape: the preview goes away, or else the selection.
  case dismiss

  private static let escape: UInt16 = 53

  /// The key `event` presses, when the board answers it. Modifiers other
  /// than ⌘ on ↓ leave the key to whoever else takes it.
  init?(_ event: NSEvent) {
    // Arrow keys carry these on every press; they say nothing of the
    // user's modifiers.
    let modifiers = event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.numericPad, .function, .capsLock])
    if modifiers == .command, event.specialKey == .downArrow {
      self = .open
      return
    }
    guard modifiers.isEmpty else {
      return nil
    }
    switch event.specialKey {
    case .upArrow?:
      self = .move(.up)
    case .downArrow?:
      self = .move(.down)
    case .leftArrow?:
      self = .move(.left)
    case .rightArrow?:
      self = .move(.right)
    case .carriageReturn?, .enter?:
      self = .open
    default:
      if event.keyCode == Self.escape {
        self = .dismiss
      } else if event.charactersIgnoringModifiers == " " {
        self = .togglePreview
      } else {
        return nil
      }
    }
  }
}

/// A board's hold on the keyboard, shared by its views: the key view once
/// it is drawn, where the arrows last left the selection, and the cards
/// waiting to be brought into view. Nothing here is observed, so moving it
/// redraws nothing.
@MainActor
final class BoardFocus {
  fileprivate weak var view: NSView?
  /// The selection as the arrows last left it, for the aim a sideways
  /// move keeps; it counts only while that card is still the selection.
  var cursor: BoardCursor?
  /// The lanes the lazy grid has on screen. A lane it hasn't built holds
  /// no card to scroll to, so a card there waits for its lane to come
  /// into view first (`awaited`).
  private var shownLanes: Set<String> = []
  private var awaited: (lane: String, card: String)?
  /// A card to bring into view once the pane holds still: the preview
  /// Space opens narrows the pane, and may cover the card it shows.
  private var pendingReveal: String?
  private var revealTask: Task<Void, Never>?

  func isShown(_ lane: String) -> Bool {
    shownLanes.contains(lane)
  }

  /// Brings `card` into view once its lane, scrolled to, is built.
  func revealOnArrival(_ card: String, in lane: String) {
    awaited = (lane, card)
  }

  /// Notes a lane on screen, handing back the card waiting on it.
  func laneAppeared(_ lane: String) -> String? {
    shownLanes.insert(lane)
    guard let awaited, awaited.lane == lane else {
      return nil
    }
    self.awaited = nil
    return awaited.card
  }

  func laneDisappeared(_ lane: String) {
    shownLanes.remove(lane)
  }

  /// Brings `card` into view after the pane's next resize settles.
  func revealAfterResize(_ card: String) {
    pendingReveal = card
  }

  /// Drops any reveal still waiting: the keys have moved on.
  func cancelReveal() {
    awaited = nil
    pendingReveal = nil
    revealTask?.cancel()
  }

  /// The pane changed width; a waiting card is revealed once it stops.
  func paneResized(reveal: @escaping @MainActor (String) -> Void) {
    guard let card = pendingReveal else {
      return
    }
    revealTask?.cancel()
    revealTask = Task {
      try? await Task.sleep(for: .milliseconds(150))
      guard !Task.isCancelled else {
        return
      }
      pendingReveal = nil
      reveal(card)
    }
  }

  /// Hands the board the window's keyboard, as a click on it does.
  func take() {
    guard let view, let window = view.window, window.firstResponder !== view else {
      return
    }
    window.makeFirstResponder(view)
  }

  /// Tells VoiceOver where the selection went: the key view, not a card,
  /// holds the keyboard, so nothing else would say.
  func announce(_ text: String) {
    guard let view else {
      return
    }
    NSAccessibility.post(element: view, notification: .announcementRequested, userInfo: [
      .announcement: text,
      .priority: NSAccessibilityPriorityLevel.high.rawValue,
    ])
  }
}

struct BoardKeyboard: NSViewRepresentable {
  let focus: BoardFocus
  /// What VoiceOver calls the board while it holds the keyboard.
  let label: String
  /// Answers a key; false hands it on, as an unanswered key goes.
  let handle: @MainActor (BoardKey) -> Bool

  func makeNSView(context: Context) -> KeyView {
    let view = KeyView()
    view.focusRingType = .none
    view.setAccessibilityElement(true)
    view.setAccessibilityRole(.group)
    return view
  }

  func updateNSView(_ view: KeyView, context: Context) {
    view.handle = handle
    view.setAccessibilityLabel(label)
    focus.view = view
  }

  final class KeyView: NSView {
    var handle: (@MainActor (BoardKey) -> Bool)?

    override var acceptsFirstResponder: Bool {
      true
    }

    // In the window's key view loop, so Tab reaches the board.
    override var canBecomeKeyView: Bool {
      true
    }

    override func keyDown(with event: NSEvent) {
      if let key = BoardKey(event), handle?(key) == true {
        return
      }
      super.keyDown(with: event)
    }

    // Takes the window's keyboard as the board first shows, under the
    // claim's rules: once per window, and never out of a text field.
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      if window != nil {
        KeyboardClaim.start(from: self) { [weak self] _ in
          self
        }
      }
    }

    // Draws nothing and takes no clicks: the board's own views do.
    override func hitTest(_ point: NSPoint) -> NSView? {
      nil
    }
  }
}
