// A view with its preview over its foot, for a preview that stands under a
// board rather than beside it: a pane of the sidebar's glass that slides
// up from the window's foot as the inspector slides in from its edge. The
// view runs on beneath it, as the board runs on beneath the sidebar, its
// scroll content and scrollers ending at the pane's edge, and the hairline
// along the pane's top drags. The split always holds the view, the pane or
// not, so showing the pane never rebuilds what it sits under. The pane
// opens at the height it was last left at, noted straight into the
// defaults like the columns' widths.

import SwiftUI

struct BottomPreviewSplit<Content: View, Preview: View>: View {
  /// Whether the pane is up.
  let shown: Bool
  @ViewBuilder let content: Content
  @ViewBuilder let preview: Preview

  /// The height the user gave the pane, which it keeps whenever the view
  /// has the room.
  @State private var height = rememberedPreviewHeight()
  /// The view's own height, which bounds the pane's.
  @State private var room: CGFloat = 0
  /// The pane's height when a drag of the divider began, while one is
  /// under way.
  @State private var dragStart: CGFloat?

  var body: some View {
    let pane = shown ? fittedPaneHeight(height, room: room) : 0
    content
      .contentMargins(.bottom, pane, for: .scrollContent)
      .contentMargins(.bottom, pane, for: .scrollIndicators)
      // Over the view rather than beside it, so the pane's height never
      // reaches the view's size, nor the window's minimum size that
      // follows it: one that moved with every step of a drag took AppKit's
      // layout down.
      .overlay(alignment: .bottom) {
        if shown {
          VStack(spacing: 0) {
            Divider()
            preview
          }
          .frame(height: pane)
          .background {
            SidebarGlass()
          }
          .overlay(alignment: .top) {
            handle
          }
          .transition(.move(edge: .bottom))
        }
      }
      .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
        room = height
      }
  }

  /// Where the divider drags: a band astride the hairline, wider than it,
  /// as an AppKit split view's is.
  private var handle: some View {
    Color.clear
      .frame(height: handleHeight)
      .contentShape(Rectangle())
      .offset(y: -handleHeight / 2)
      .pointerStyle(.rowResize)
      // Measured in the window: the handle moves with the drag.
      .gesture(
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
          .onChanged { value in
            let start = dragStart ?? fittedPaneHeight(height, room: room)
            dragStart = start
            height = fittedPaneHeight(start - value.translation.height, room: room)
          }
          .onEnded { _ in
            dragStart = nil
            UserDefaults.standard.set(Double(height), forKey: previewHeightKey)
          }
      )
  }
}

/// `height`, no shorter than the pane's least, and no taller than leaves
/// the view its own least of `room`.
private func fittedPaneHeight(_ height: CGFloat, room: CGFloat) -> CGFloat {
  let tallest = room > 0 ? max(previewMinHeight, room - contentMinHeight) : .infinity
  return min(max(height, previewMinHeight), tallest)
}

/// The glass the sidebar stands on: AppKit's own, in the sidebar's
/// variant, so the pane reads as the sidebar does over what passes
/// beneath. The variant is the glass view's own private setting, the one
/// the split view gives its sidebar; where it is missing the glass keeps
/// its regular look.
private struct SidebarGlass: NSViewRepresentable {
  func makeNSView(context: Context) -> NSGlassEffectView {
    let view = NSGlassEffectView()
    view.style = .regular
    view.cornerRadius = 0
    if view.responds(to: NSSelectorFromString("set_variant:")) {
      view.setValue(sidebarGlassVariant, forKey: "_variant")
    }
    return view
  }

  func updateNSView(_ view: NSGlassEffectView, context: Context) {}
}

/// The glass variant the split view gives its sidebar.
private let sidebarGlassVariant = 17

/// The pane's least height, and the least it leaves the view above.
private let previewMinHeight: CGFloat = 180
private let contentMinHeight: CGFloat = 200
private let handleHeight: CGFloat = 8

private let previewHeightKey = "boardPreviewHeight"

/// The height the pane was last left at, or room for the facts the first
/// time.
private func rememberedPreviewHeight() -> CGFloat {
  let saved = UserDefaults.standard.double(forKey: previewHeightKey)
  return saved > 0 ? saved : 320
}
