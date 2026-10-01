// The box above the inbox: the newest unread of one pinned label, under
// the label's own name — what a rule marked "Show at the top of Recent"
// collects. Several labels pinned at once rotate through the one box
// rather than stacking, the way the suggestions do. The items stay in the
// list below: the box is a spotlight, not a filing cabinet.
//
// It rides inside the list as an unselectable first row, so it scrolls
// away with everything else instead of permanently taking the top of the
// column. Its rows are single-line for the same reason the list's own
// measurements have to be honest: a row whose height depends on its width
// is measured once, at a width the list doesn't have yet, and draws
// clipped until something forces another pass.

import SwiftUI

/// Unread rows the box shows at most, after which it says how many more.
private let pinnedRowCap = 3
/// How long the light takes to travel the card's edge once.
private let glowDuration: Double = 2.5

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
      ForEach(Array(box.threads.enumerated()), id: \.element.id) { position, thread in
        Divider()
        row(thread)
      }
    }
    .overlay {
      RoundedRectangle(cornerRadius: 12)
        .strokeBorder(.quaternary, lineWidth: 1)
    }
    .overlay {
      glow(box)
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

  /// The light that travels the card's edge once, when the box arrives or
  /// its top item changes: an arc of the label's tint swept around an
  /// angular gradient. It settles rather than pulsing — a box that glowed
  /// forever would be a distraction rather than a cue. Keyframes drive it
  /// because the angle lives inside a gradient, where an implicit
  /// animation has nothing to interpolate.
  @ViewBuilder
  private func glow(_ box: PinnedBox) -> some View {
    if reduceMotion {
      EmptyView()
    } else {
      KeyframeAnimator(initialValue: 0.0, trigger: pulse) { angle in
        RoundedRectangle(cornerRadius: 12)
          .strokeBorder(
            AngularGradient(
              colors: [.clear, .clear, box.label.tint.color.opacity(0.75), .clear, .clear],
              center: .center,
              angle: .degrees(angle)
            ),
            lineWidth: 1.5
          )
          // Nothing to see before the light sets off, or after it lands.
          .opacity(angle <= 0 || angle >= 360 ? 0 : 1)
      } keyframes: { _ in
        LinearKeyframe(360.0, duration: glowDuration)
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
    return Button {
      model.selectedThreadIds = [thread.id]
      model.selectedMemberId = nil
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          Image(systemName: spec(for: item.provider).symbol(for: item))
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(spec(for: item.provider).color(for: item))
          Text(item.title)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
          Spacer(minLength: 4)
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
    }
    .buttonStyle(.plain)
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
