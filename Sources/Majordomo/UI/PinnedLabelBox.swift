// The box above the inbox: the newest unread of one pinned label, under
// the label's own name — what a rule marked "Show at the top of Recent"
// collects. Several labels pinned at once rotate through the one box
// rather than stacking, the way the suggestions do. The items stay in the
// list below: the box is a spotlight, not a filing cabinet.
//
// It rides inside the list as an unselectable first row, so it scrolls
// away with everything else instead of permanently taking the top of the
// column. Everything in it is measured the same way the list measures its
// own rows — single-line text, no Button — because the table measures this
// row once, at a width it doesn't have yet, and keeps whatever height that
// gave.

import SwiftUI

/// Unread rows the box shows at most, after which it says how many more.
private let pinnedRowCap = 3
/// The model's own colors, for the light that marks what it chose. The
/// system vends no style for them, so they are named here — and only here,
/// since nothing else in the app speaks in them.
private let intelligenceColors: [Color] = [
  Color(red: 1.00, green: 0.18, blue: 0.33),
  Color(red: 0.69, green: 0.32, blue: 0.87),
  Color(red: 0.00, green: 0.48, blue: 1.00),
  Color(red: 0.20, green: 0.78, blue: 0.95),
  Color(red: 1.00, green: 0.58, blue: 0.00),
]

/// Where the light comes up from: the foot of the card, in the middle.
private let glowOrigin = UnitPoint(x: 0.5, y: 1.0)
/// The brightest the wash ever gets. A cue, not a highlighter.
private let glowPeak = 0.22

/// How long the light takes to rise, hold, and fade away.
private let glowRise: Double = 0.55
private let glowHold: Double = 0.3
private let glowFade: Double = 1.2

/// What the light is doing at one instant: how far the wash has spread,
/// and how strongly it shows.
private struct GlowPhase {
  var spread = 0.25
  var opacity = 0.0
}

/// One pinned label with what it has to show right now.
struct PinnedBox: Identifiable {
  let label: InboxLabel
  /// Unread threads carrying the label, newest first, capped.
  let threads: [InboxThread]
  /// How many unread it holds in total — the cap hides the rest.
  let unread: Int
  /// True when a rule that pins this label is judged by the model: the
  /// box says so, the way a generated line does.
  let byModel: Bool

  var id: LabelId { label.id }
}

/// The labels to spotlight, in catalog order: those a rule pins, holding
/// unread among the threads on screen. Empty when there is nothing to show
/// — the box never draws itself as an empty state.
@MainActor
func pinnedBoxes(model: AppModel, threads: [InboxThread]) -> [PinnedBox] {
  let pinning = model.rules.filter { $0.enabled && $0.pinsToTop }
  guard !pinning.isEmpty else {
    return []
  }
  return model.allLabels.compactMap { label in
    let rules = pinning.filter { $0.labelIds.contains(label.id) }
    guard !rules.isEmpty else {
      return nil
    }
    let unread = threads.filter { thread in
      !thread.read && thread.items.contains { $0.labels.contains(label.id) }
    }
    guard !unread.isEmpty else {
      return nil
    }
    return PinnedBox(
      label: label,
      threads: Array(unread.prefix(pinnedRowCap)),
      unread: unread.count,
      byModel: rules.contains { $0.judge == .intelligence }
    )
  }
}

struct PinnedLabelBox: View {
  let model: AppModel
  let boxes: [PinnedBox]

  /// Which pinned label is showing; clamped as labels come and go.
  @State private var index = 0
  /// Bumped to set the light off. The keyframes need a value that CHANGES
  /// to play, and the box arrives with its content already in place — so
  /// the first change has to be made here, once the view exists.
  @State private var pulse = 0

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let box = boxes[min(index, boxes.count - 1)]
    VStack(alignment: .leading, spacing: 0) {
      header(box)
      // Spelled out rather than looped, and ruled with a rectangle rather
      // than a Divider: inside a list row, both a ForEach and a Divider
      // measure as nothing on the pass that fixes the row's height, and the
      // box drew as a header with its rows cut off. The cap is three.
      ForEach(0 ..< pinnedRowCap, id: \.self) { position in
        if position < box.threads.count {
          Rectangle()
            .fill(.quaternary)
            .frame(height: 1)
          row(box.threads[position])
        }
      }
    }
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(.quaternary, lineWidth: 1)
    }
    // Over the resting border, so the light reaches the edge too and
    // leaves it as it found it.
    .overlay {
      glow(onBorder: true)
    }
    .background {
      glow(onBorder: false)
    }
    // The row has to report its full height when the box gains a line, or
    // the list keeps the height it first measured and clips it until
    // something else forces a pass.
    .fixedSize(horizontal: false, vertical: true)
    .task(id: "\(box.id):\(box.threads.first?.id ?? "")") {
      pulse += 1
    }
    .onChange(of: boxes.count) {
      index = min(index, max(0, boxes.count - 1))
    }
  }

  /// The light that fills the card once, when the box arrives or its top
  /// item changes: the model's colors washing out from inside and fading
  /// away again. It settles rather than pulsing — a box that glowed
  /// forever would be a distraction rather than a cue. Keyframes drive it
  /// because the values live inside gradients and frames, where an
  /// implicit animation has nothing to interpolate.
  @ViewBuilder
  private func glow(onBorder: Bool) -> some View {
    if reduceMotion {
      EmptyView()
    } else {
      KeyframeAnimator(initialValue: GlowPhase(), trigger: pulse) { phase in
        GeometryReader { proxy in
          let span = max(proxy.size.width, proxy.size.height)
          // The model's colors laid across the card, shown only where the
          // mask lets them through: a soft circle opening from the foot of
          // the card. Growing the mask is what makes the light rise, and
          // the same mask over the edge is what carries it into the border.
          let colors = LinearGradient(
            colors: intelligenceColors, startPoint: .leading, endPoint: .trailing
          )
          let light = RadialGradient(
            colors: [.white, .white.opacity(0.55), .clear],
            center: glowOrigin,
            startRadius: 0,
            endRadius: span * phase.spread
          )
          Group {
            if onBorder {
              RoundedRectangle(cornerRadius: 12)
                .strokeBorder(colors, lineWidth: 1)
                .mask { light }
                // A line carries less color than a wash of the same alpha,
                // so it is lit harder to read as the same light.
                .opacity(min(1, phase.opacity * 3.4))
            } else {
              colors
                .mask { light }
                .blur(radius: 10)
                .opacity(phase.opacity)
            }
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .allowsHitTesting(false)
      } keyframes: { _ in
        KeyframeTrack(\.spread) {
          LinearKeyframe(1.0, duration: glowRise)
          LinearKeyframe(1.35, duration: glowHold + glowFade)
        }
        KeyframeTrack(\.opacity) {
          LinearKeyframe(glowPeak, duration: glowRise)
          LinearKeyframe(glowPeak, duration: glowHold)
          LinearKeyframe(0.0, duration: glowFade)
        }
      }
    }
  }

  /// The label's glyph and name, the model's mark when it is the one
  /// choosing, and the arrows when more than one label is pinned.
  private func header(_ box: PinnedBox) -> some View {
    HStack(spacing: 6) {
      Image(systemName: box.label.symbol)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(box.label.tint.color)
        .frame(width: 16)
      Text(box.label.name)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(.secondary)
      if box.byModel {
        Image(systemName: "apple.intelligence")
          .font(.system(size: 10))
          .foregroundStyle(.tertiary)
          .help("Chosen by Apple Intelligence on this Mac")
      }
      Spacer(minLength: 6)
      if box.unread > box.threads.count {
        Text("+\(box.unread - box.threads.count)")
          .font(.system(size: 10))
          .foregroundStyle(.tertiary)
      }
      if boxes.count > 1 {
        rotation
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
  }

  /// ‹ 1 of 2 › — the same control the suggestions rotate with.
  private var rotation: some View {
    HStack(spacing: 2) {
      Button {
        index = max(0, index - 1)
      } label: {
        Image(systemName: "chevron.left")
      }
      .disabled(index == 0)
      Text("\(min(index, boxes.count - 1) + 1) of \(boxes.count)")
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
        .monospacedDigit()
      Button {
        index = min(boxes.count - 1, index + 1)
      } label: {
        Image(systemName: "chevron.right")
      }
      .disabled(index >= boxes.count - 1)
    }
    .buttonStyle(.plain)
    .font(.system(size: 9, weight: .semibold))
    .foregroundStyle(.secondary)
  }

  /// One spotlit thread: its title and whatever line the rows show —
  /// the model's summary when it has written one. Clicking picks it, the
  /// way clicking the row below would.
  private func row(_ thread: InboxThread) -> some View {
    let item = thread.lead
    return VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 4) {
        Image(systemName: spec(for: item.provider).symbol(for: item))
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(spec(for: item.provider).color(for: item))
        Text(item.title)
          .font(.system(size: 12, weight: .medium))
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: .infinity, alignment: .leading)
        Text(relativeTime(item.updatedAt, now: model.now))
          .font(.system(size: 10))
          .foregroundStyle(.secondary)
          .fixedSize()
      }
      if let line = summaryLine(for: item) {
        line
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          // One line, like the title: a box whose rows wrap has a height
          // that depends on its width, and the list measures the row
          // before it knows that width.
          .lineLimit(1)
          .truncationMode(.tail)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .contentShape(Rectangle())
    // A gesture rather than a Button: a Button reports no height while the
    // list is measuring the row it sits in, and the box drew as a header
    // with nothing under it. The row it rides in takes no selection, so
    // there are no table clicks for this to swallow.
    .onTapGesture {
      // Picking it is reading it: the box holds what is still unread, so
      // the row leaves as soon as it has been looked at.
      model.selectedThreadIds = [thread.id]
      model.selectedMemberId = nil
      model.markRead(Set(thread.itemIds))
    }
    .help(item.title)
  }

  /// What the box says about an item under its title: the model's summary
  /// when it has written one, marked as generated the way the rows mark
  /// it, and nothing at all otherwise — a box of raw body text would be
  /// three paragraphs where three lines belong.
  private func summaryLine(for item: InboxItem) -> Text? {
    guard let summary = item.summary, !summary.isEmpty else {
      return nil
    }
    return Text("\(Image(systemName: summaryGlyph)) \(summary)")
  }
}
