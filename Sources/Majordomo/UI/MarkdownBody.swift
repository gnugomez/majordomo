// A rendering helper provider specs can opt into for Markdown body text —
// the bodyView contract itself is arbitrary SwiftUI. Foundation's parser
// reports block structure as PresentationIntent runs; laying those out is
// this view's job (code blocks in a monospaced card, quotes behind a bar,
// headings, list items) with inline styles riding along on the runs. Real
// forge content is full of fenced code and quotes, so inline-only parsing
// reads as broken — and a rendering dependency stays off the table.

import SwiftUI

struct MarkdownBody: View {
  let text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      ForEach(blocks) { block in
        blockView(block)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .textSelection(.enabled)
  }

  // MARK: Block model

  private struct Block: Identifiable {
    enum Kind {
      case paragraph
      case heading(level: Int)
      case code
      case quote
      case listItem(marker: String)
      case divider
    }

    let id: Int
    let kind: Kind
    var content: AttributedString
  }

  private var blocks: [Block] {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
    guard let parsed = try? AttributedString(markdown: text, options: options) else {
      return [Block(id: 0, kind: .paragraph, content: AttributedString(text))]
    }

    var result: [Block] = []
    var lastIntent: PresentationIntent??
    for run in parsed.runs {
      var piece = AttributedString(parsed[run.range])
      guard !piece.characters.isEmpty else { continue }
      piece.presentationIntent = nil
      // Runs of one block share one intent; a change starts the next block.
      if lastIntent == run.presentationIntent, !result.isEmpty {
        result[result.count - 1].content += piece
      } else {
        lastIntent = run.presentationIntent
        result.append(Block(id: result.count, kind: kind(of: run.presentationIntent), content: piece))
      }
    }
    // Code blocks keep their inner newlines; the trailing one just pads.
    for index in result.indices where isCode(result[index].kind) {
      while result[index].content.characters.last == "\n" {
        result[index].content.characters.removeLast()
      }
    }
    return result
  }

  private func isCode(_ kind: Block.Kind) -> Bool {
    if case .code = kind {
      return true
    }
    return false
  }

  /// Innermost meaningful component wins: code and headings over list
  /// nesting, list markers over the quote that may contain them.
  private func kind(of intent: PresentationIntent?) -> Block.Kind {
    guard let components = intent?.components else {
      return .paragraph
    }
    var ordered = false
    var ordinal: Int?
    var quoted = false
    for component in components {
      switch component.kind {
      case .codeBlock:
        return .code
      case .header(let level):
        return .heading(level: level)
      case .listItem(let n):
        ordinal = n
      case .orderedList:
        ordered = true
      case .blockQuote:
        quoted = true
      case .thematicBreak:
        return .divider
      default:
        break
      }
    }
    if let ordinal {
      return .listItem(marker: ordered ? "\(ordinal)." : "•")
    }
    return quoted ? .quote : .paragraph
  }

  // MARK: Rendering

  @ViewBuilder
  private func blockView(_ block: Block) -> some View {
    switch block.kind {
    case .paragraph:
      Text(block.content)
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    case .heading(let level):
      Text(block.content)
        .font(.system(size: level <= 2 ? 13 : 12, weight: .semibold))
        .foregroundStyle(.secondary)
    case .code:
      Text(block.content)
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
    case .quote:
      HStack(alignment: .top, spacing: 8) {
        RoundedRectangle(cornerRadius: 1)
          .fill(.quaternary)
          .frame(width: 3)
        Text(block.content)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
    case .listItem(let marker):
      HStack(alignment: .firstTextBaseline, spacing: 5) {
        Text(marker)
          .font(.system(size: 12))
          .foregroundStyle(.tertiary)
        Text(block.content)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
      }
    case .divider:
      Divider()
    }
  }
}
