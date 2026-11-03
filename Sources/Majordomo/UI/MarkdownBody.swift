// A rendering helper provider specs can opt into for Markdown body text —
// the bodyView contract itself is arbitrary SwiftUI. MarkdownDocument
// parses a body once into blocks; this lays them out in readable 13-point
// primary text: code in a monospaced card, quotes behind a bar, headings,
// list items and task checkboxes at their depth, tables as a grid, images
// as pictures that fit the column (MarkdownImageView), and `<details>`
// folds closed until clicked. Inline styles, links among them, ride along
// on the text; a link a body writes relative to its target opens resolved
// against it. Search terms are highlighted in every block's text.

import SwiftUI

struct MarkdownBody: View {
  let text: String

  @Environment(\.bodyImages) private var bodyImages

  var body: some View {
    MarkdownBlockList(blocks: MarkdownDocument.parsed(text).blocks)
      .frame(maxWidth: .infinity, alignment: .leading)
      .textSelection(.enabled)
      .environment(\.openURL, OpenURLAction { url in
        guard url.scheme == nil, let resolved = bodyImages?.resolve(url.relativeString) else {
          return .systemAction
        }
        return .systemAction(resolved)
      })
  }
}

/// Blocks one under another — a body's, or a fold's.
private struct MarkdownBlockList: View {
  let blocks: [MarkdownBlock]

  @Environment(\.searchHighlightTerms) private var highlightTerms

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(blocks) { block in
        blockView(block)
      }
    }
  }

  @ViewBuilder
  private func blockView(_ block: MarkdownBlock) -> some View {
    let content = highlighted(block.content, terms: highlightTerms)
    switch block.kind {
    case .paragraph:
      Text(content)
        .font(.system(size: 13))
        .fixedSize(horizontal: false, vertical: true)
    case .heading(let level):
      Text(content)
        .font(.system(size: headingSize(level), weight: .semibold))
        .padding(.top, level <= 2 ? 4 : 0)
    case .code:
      Text(content)
        .font(.system(size: 12, design: .monospaced))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ConversationShades.code, in: RoundedRectangle(cornerRadius: 6))
    case .quote:
      HStack(alignment: .top, spacing: 10) {
        RoundedRectangle(cornerRadius: 1.5)
          .fill(.quaternary)
          .frame(width: 3)
        Text(content)
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    case .listItem(let marker, let depth):
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(marker)
          .font(.system(size: 13).monospacedDigit())
          .foregroundStyle(.secondary)
        Text(content)
          .font(.system(size: 13))
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.leading, CGFloat(depth - 1) * 16)
    case .task(let done, let depth):
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Image(systemName: done ? "checkmark.square.fill" : "square")
          .font(.system(size: 12))
          .foregroundStyle(done ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
        Text(content)
          .font(.system(size: 13))
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.leading, CGFloat(depth - 1) * 16)
    case .table(let table):
      MarkdownTableView(table: table)
    case .divider:
      Divider()
    case .images(let images):
      MarkdownImageGroup(images: images)
    case .details(let summary, let blocks):
      MarkdownFold(summary: highlighted(summary, terms: highlightTerms), blocks: blocks)
    }
  }

  private func headingSize(_ level: Int) -> CGFloat {
    switch level {
    case 1: 17
    case 2: 15
    default: 13
    }
  }
}

/// A table as a grid: the header set apart, rows ruled, the whole framed.
private struct MarkdownTableView: View {
  let table: MarkdownTable

  @Environment(\.searchHighlightTerms) private var highlightTerms

  var body: some View {
    let columns = table.columnCount
    Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
      if !table.header.isEmpty {
        GridRow {
          ForEach(0 ..< columns, id: \.self) { column in
            cell(table.header, column, header: true)
          }
        }
        .background(ConversationShades.code)
      }
      ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
        if index > 0 || !table.header.isEmpty {
          Divider()
        }
        GridRow {
          ForEach(0 ..< columns, id: \.self) { column in
            cell(row, column, header: false)
          }
        }
      }
    }
    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .fixedSize(horizontal: false, vertical: true)
  }

  private func cell(_ cells: [AttributedString], _ column: Int, header: Bool) -> some View {
    let text = column < cells.count ? cells[column] : AttributedString()
    let alignment = column < table.alignments.count ? table.alignments[column] : .leading
    return Text(highlighted(text, terms: highlightTerms))
      .font(.system(size: 12, weight: header ? .semibold : .regular))
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 8)
      .padding(.vertical, 5)
      .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
      .gridColumnAlignment(alignment)
  }
}

/// A `<details>` fold: its summary as a disclosure row, closed until
/// clicked.
private struct MarkdownFold: View {
  let summary: AttributedString
  let blocks: [MarkdownBlock]

  @State private var open = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button {
        withAnimation(.snappy(duration: 0.2)) {
          open.toggle()
        }
      } label: {
        HStack(spacing: 6) {
          Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(open ? 90 : 0))
          Text(summary)
            .font(.system(size: 13, weight: .medium))
            .multilineTextAlignment(.leading)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      if open {
        MarkdownBlockList(blocks: blocks)
          .padding(.leading, 16)
      }
    }
  }
}
