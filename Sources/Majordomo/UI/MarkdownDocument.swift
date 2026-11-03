// A body's Markdown, parsed once into the blocks MarkdownBody lays out.
// Foundation's parser reports block structure as PresentationIntent runs;
// grouping those into blocks is this file's job: paragraphs, headings,
// code, quotes, list items and task checkboxes at their depth, whole
// tables, dividers, images, and `<details>` folds. The parser hands raw
// HTML through as text, so its tags are read here — an `<img>` becomes an
// image, `<br>` a line break, `<details>`/`<summary>` a fold — and the
// rest are dropped, their text kept. Real forge content is full of fenced
// code, template HTML, and pasted screenshots, so inline-only parsing reads
// as broken — and a rendering dependency stays off the table.
//
// Parsing a long thread's bodies on every redraw would be felt, so each
// body is parsed once and kept (MarkdownDocument.parsed).

import SwiftUI

/// An image a body shows, as it wrote it.
struct MarkdownImage: Hashable {
  /// Where the body points, as written — possibly relative to the target,
  /// for the provider to resolve (BodyImageSource.resolve).
  let source: String
  let alt: String
  /// The size the body asks for, in points; nil for the image's own.
  var width: CGFloat?
  var height: CGFloat?

  /// A status badge (shields and the like), drawn at text height in a row
  /// rather than as a picture of its own.
  var isBadge: Bool {
    if let height, height <= 24 {
      return true
    }
    guard let url = URL(string: source), let host = url.host()?.lowercased() else {
      return false
    }
    let path = url.path().lowercased()
    return host.hasSuffix("shields.io") || host.hasSuffix("badgen.net") || host.hasSuffix("badge.fury.io")
      || path.hasSuffix("badge.svg") || path.contains("/badge/") || path.contains("/badges/")
  }
}

/// A table, header first, a cell per column; a short row leaves its last
/// cells empty.
struct MarkdownTable {
  var alignments: [HorizontalAlignment] = []
  var header: [AttributedString] = []
  var rows: [[AttributedString]] = []

  var columnCount: Int {
    max(header.count, rows.map(\.count).max() ?? 0, alignments.count)
  }
}

struct MarkdownBlock: Identifiable {
  enum Kind {
    case paragraph
    case heading(level: Int)
    case code
    case quote
    /// Depth 1 is a top-level list.
    case listItem(marker: String, depth: Int)
    case task(done: Bool, depth: Int)
    case table(MarkdownTable)
    case divider
    /// Images standing on their own, in order.
    case images([MarkdownImage])
    /// A `<details>` fold: its summary, and what opens beneath it.
    case details(summary: AttributedString, blocks: [MarkdownBlock])
  }

  let id: Int
  let kind: Kind
  /// The text, for the kinds that have one.
  let content: AttributedString
}

/// A parsed body: its blocks, and its words alone for a one-line excerpt.
@MainActor
final class MarkdownDocument {
  let blocks: [MarkdownBlock]
  let plainText: String

  /// Bodies parsed so far, by their text — a preview redraws far more
  /// often than its bodies change.
  private static let parsedBodies: NSCache<NSString, MarkdownDocument> = {
    let cache = NSCache<NSString, MarkdownDocument>()
    cache.countLimit = 400
    return cache
  }()

  static func parsed(_ text: String) -> MarkdownDocument {
    if let held = parsedBodies.object(forKey: text as NSString) {
      return held
    }
    let document = MarkdownDocument(blocks: MarkdownParser.blocks(of: text))
    parsedBodies.setObject(document, forKey: text as NSString)
    return document
  }

  private init(blocks: [MarkdownBlock]) {
    self.blocks = blocks
    plainText = Self.words(of: blocks).joined(separator: " ")
  }

  private static func words(of blocks: [MarkdownBlock]) -> [String] {
    blocks.flatMap { block -> [String] in
      switch block.kind {
      case .details(let summary, let inner):
        [String(summary.characters)] + words(of: inner)
      case .images, .divider, .table:
        []
      default:
        [String(block.content.characters).replacingOccurrences(of: "\n", with: " ")]
      }
    }
  }
}

/// One pass over the parser's runs, gathering blocks.
private struct MarkdownParser {
  /// Blocks in order, with `<details>` openings and closings among them,
  /// before they nest.
  private enum Entry {
    case block(MarkdownBlock.Kind, AttributedString)
    case detailsStart(summary: AttributedString)
    case detailsEnd
  }

  /// What groups runs into one block: their intent — except that a
  /// table's cells, each with an intent of its own, share their table's.
  private enum BlockKey: Equatable {
    case intent(PresentationIntent?)
    case table(Int)
  }

  /// Where a table cell's run sits.
  private struct CellPosition {
    let row: Int
    let header: Bool
    let column: Int
  }

  /// The block being gathered.
  private struct OpenBlock {
    let key: BlockKey
    var kind: MarkdownBlock.Kind
    var content = AttributedString()
    /// A table's cells, gathered under its columns' alignments.
    var table = MarkdownTable()
    /// The table row being filled, by identity.
    var row: Int?

    init(key: BlockKey, kind: MarkdownBlock.Kind) {
      self.key = key
      self.kind = kind
      if case .table(let columns) = kind {
        table = columns
      }
    }
  }

  private var entries: [Entry] = []
  private var open: OpenBlock?
  /// Images written inside the open block's text, shown after it.
  private var trailingImages: [MarkdownImage] = []
  /// A `<summary>`'s text while it is being read.
  private var summary: AttributedString?

  static func blocks(of text: String) -> [MarkdownBlock] {
    var parser = MarkdownParser()
    parser.read(text)
    var nextId = 0
    return nest(parser.entries, nextId: &nextId)
  }

  private mutating func read(_ text: String) {
    // HTML comments are template boilerplate ("Describe your change…"),
    // written for whoever fills the template in, never for its readers.
    let source = text.replacing(/<!--[\s\S]*?-->/, with: "")
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
    guard let parsed = try? AttributedString(markdown: source, options: options) else {
      entries.append(.block(.paragraph, AttributedString(source)))
      return
    }
    for run in parsed.runs {
      let intent = run.presentationIntent
      let key = blockKey(intent)
      if key != open?.key {
        close()
        open = OpenBlock(key: key, kind: kind(of: intent))
      }
      let cell = cellPosition(intent)
      if let image = run.imageURL {
        // The parser hands the alt text as the run's text.
        addImage(MarkdownImage(source: image.relativeString, alt: String(parsed[run.range].characters)))
        continue
      }
      var piece = AttributedString(parsed[run.range])
      piece.presentationIntent = nil
      let inline = run.inlinePresentationIntent ?? []
      let inCode = open.map { isCode($0.kind) } ?? false
      if !inCode, intent == nil || inline.contains(.inlineHTML) || inline.contains(.blockHTML) {
        readHTML(String(piece.characters), block: intent == nil, cell: cell)
        continue
      }
      if inline.contains(.code) {
        piece.backgroundColor = ConversationShades.code
      }
      add(piece, cell: cell)
    }
    close()
  }

  // MARK: Text and images

  private mutating func add(_ piece: AttributedString, cell: CellPosition?) {
    if summary != nil {
      summary? += piece
      return
    }
    if open == nil {
      open = OpenBlock(key: .intent(nil), kind: .paragraph)
    }
    if case .table = open?.kind, let cell {
      addCell(piece, at: cell)
    } else {
      open?.content += piece
    }
  }

  private mutating func addCell(_ piece: AttributedString, at cell: CellPosition) {
    guard var block = open else {
      return
    }
    if block.row != cell.row {
      block.row = cell.row
      if !cell.header {
        block.table.rows.append([])
      }
    }
    if cell.header {
      while block.table.header.count <= cell.column {
        block.table.header.append(AttributedString())
      }
      block.table.header[cell.column] += piece
    } else if let last = block.table.rows.indices.last {
      while block.table.rows[last].count <= cell.column {
        block.table.rows[last].append(AttributedString())
      }
      block.table.rows[last][cell.column] += piece
    }
    open = block
  }

  /// An image in its place: on its own when nothing has been written in
  /// the open block yet, after the block's text otherwise.
  private mutating func addImage(_ image: MarkdownImage) {
    guard summary == nil else {
      return
    }
    if let open, hasText(open) {
      trailingImages.append(image)
    } else {
      appendImage(image)
    }
  }

  /// Joins the images just before it, so a row of badges or a pair of
  /// screenshots stays one group.
  private mutating func appendImage(_ image: MarkdownImage) {
    if case .block(.images(var images), let content)? = entries.last {
      images.append(image)
      entries[entries.count - 1] = .block(.images(images), content)
    } else {
      entries.append(.block(.images([image]), AttributedString()))
    }
  }

  private func hasText(_ block: OpenBlock) -> Bool {
    if case .table = block.kind {
      return !block.table.header.isEmpty || !block.table.rows.isEmpty
    }
    return block.content.characters.contains { !$0.isWhitespace }
  }

  // MARK: HTML

  /// Raw HTML, read for what it means here: images, line breaks, and
  /// folds; every other tag goes, its text stays.
  private mutating func readHTML(_ raw: String, block: Bool, cell: CellPosition?) {
    var rest = raw[...]
    while let tag = rest.firstMatch(of: /<(\/?)([A-Za-z][A-Za-z0-9]*)[^<>]*>/) {
      addHTMLText(rest[..<tag.range.lowerBound], block: block, cell: cell)
      let closing = !tag.output.1.isEmpty
      switch tag.output.2.lowercased() {
      case "img" where !closing:
        if let image = MarkdownImage(htmlTag: tag.output.0) {
          addImage(image)
        }
      case "br":
        add(AttributedString("\n"), cell: cell)
      case "details":
        close()
        entries.append(closing ? .detailsEnd : .detailsStart(summary: AttributedString("Details")))
      case "summary":
        if closing {
          endSummary()
        } else {
          summary = AttributedString()
        }
      default:
        break
      }
      rest = rest[tag.range.upperBound...]
    }
    addHTMLText(rest, block: block, cell: cell)
  }

  /// Text between tags. In an HTML block the line breaks around tags are
  /// layout, not content.
  private mutating func addHTMLText(_ text: Substring, block: Bool, cell: CellPosition?) {
    guard !text.isEmpty, !block || text.contains(where: { !$0.isWhitespace }) else {
      return
    }
    add(AttributedString(decodeEntities(String(text))), cell: cell)
  }

  /// A finished `<summary>` names the fold it opens; one outside a fold
  /// reads as plain text.
  private mutating func endSummary() {
    guard let text = summary.map(trimmed) else {
      return
    }
    summary = nil
    if case .detailsStart? = entries.last {
      entries[entries.count - 1] = .detailsStart(summary: text)
    } else {
      add(text, cell: nil)
    }
  }

  // MARK: Blocks

  /// Ends the open block, and sets down the images written inside it.
  private mutating func close() {
    defer {
      open = nil
      let images = trailingImages
      trailingImages = []
      for image in images {
        appendImage(image)
      }
    }
    guard let block = open else {
      return
    }
    switch block.kind {
    case .table:
      if hasText(block) {
        entries.append(.block(.table(block.table), AttributedString()))
      }
    case .divider:
      entries.append(.block(.divider, AttributedString()))
    case .code:
      // Code keeps its inner newlines; the trailing one just pads.
      var content = block.content
      while content.characters.last == "\n" {
        content.characters.removeLast()
      }
      if !content.characters.isEmpty {
        entries.append(.block(.code, content))
      }
    default:
      let content = trimmed(block.content)
      if !content.characters.isEmpty {
        let (kind, text) = taskItem(block.kind, content)
        entries.append(.block(kind, text))
      }
    }
  }

  /// A list item written as a task ("[ ] ", "[x] ") reads as a checkbox.
  private func taskItem(_ kind: MarkdownBlock.Kind, _ content: AttributedString) -> (MarkdownBlock.Kind, AttributedString) {
    guard case .listItem(_, let depth) = kind else {
      return (kind, content)
    }
    let text = String(content.characters.prefix(4))
    let done: Bool
    switch text {
    case "[ ] ": done = false
    case "[x] ", "[X] ": done = true
    default: return (kind, content)
    }
    var rest = content
    rest.characters.removeFirst(4)
    return (.task(done: done, depth: depth), rest)
  }

  private func trimmed(_ text: AttributedString) -> AttributedString {
    var text = text
    while let first = text.characters.first, first.isWhitespace {
      text.characters.removeFirst()
    }
    while let last = text.characters.last, last.isWhitespace {
      text.characters.removeLast()
    }
    return text
  }

  /// Folds the entries between each `<details>` and its close into the
  /// fold; one left open closes at the end, a stray close is dropped.
  private static func nest(_ entries: [Entry], nextId: inout Int) -> [MarkdownBlock] {
    var levels: [(summary: AttributedString, blocks: [MarkdownBlock])] = [(AttributedString(), [])]
    func closeLevel() {
      let level = levels.removeLast()
      levels[levels.count - 1].blocks.append(
        MarkdownBlock(id: nextId, kind: .details(summary: level.summary, blocks: level.blocks), content: AttributedString())
      )
      nextId += 1
    }
    for entry in entries {
      switch entry {
      case .block(let kind, let content):
        levels[levels.count - 1].blocks.append(MarkdownBlock(id: nextId, kind: kind, content: content))
        nextId += 1
      case .detailsStart(let summary):
        levels.append((summary, []))
      case .detailsEnd:
        if levels.count > 1 {
          closeLevel()
        }
      }
    }
    while levels.count > 1 {
      closeLevel()
    }
    return levels[0].blocks
  }

  // MARK: Intents

  private func blockKey(_ intent: PresentationIntent?) -> BlockKey {
    let table = intent?.components.first { component in
      if case .table = component.kind {
        return true
      }
      return false
    }
    return table.map { .table($0.identity) } ?? .intent(intent)
  }

  private func cellPosition(_ intent: PresentationIntent?) -> CellPosition? {
    var row: Int?
    var header = false
    var column: Int?
    for component in intent?.components ?? [] {
      switch component.kind {
      case .tableHeaderRow:
        row = component.identity
        header = true
      case .tableRow:
        row = component.identity
      case .tableCell(let index):
        column = index
      default:
        break
      }
    }
    guard let row, let column else {
      return nil
    }
    return CellPosition(row: row, header: header, column: column)
  }

  private func isCode(_ kind: MarkdownBlock.Kind) -> Bool {
    if case .code = kind {
      return true
    }
    return false
  }

  /// Components run innermost first, and the innermost meaningful one
  /// wins: code and headings over list nesting, list markers over the
  /// quote that may hold them. A list item's marker follows its own list.
  private func kind(of intent: PresentationIntent?) -> MarkdownBlock.Kind {
    guard let components = intent?.components else {
      return .paragraph
    }
    var ordinal: Int?
    var ordered: Bool?
    var depth = 0
    var quoted = false
    for component in components {
      switch component.kind {
      case .codeBlock:
        return .code
      case .header(let level):
        return .heading(level: level)
      case .table(let columns):
        return .table(MarkdownTable(alignments: columns.map(alignment)))
      case .thematicBreak:
        return .divider
      case .listItem(let number):
        depth += 1
        ordinal = ordinal ?? number
      case .orderedList where ordinal != nil && ordered == nil:
        ordered = true
      case .unorderedList where ordinal != nil && ordered == nil:
        ordered = false
      case .blockQuote:
        quoted = true
      default:
        break
      }
    }
    if let ordinal {
      return .listItem(marker: ordered == true ? "\(ordinal)." : "•", depth: depth)
    }
    return quoted ? .quote : .paragraph
  }

  private func alignment(_ column: PresentationIntent.TableColumn) -> HorizontalAlignment {
    switch column.alignment {
    case .center: .center
    case .right: .trailing
    default: .leading
    }
  }
}

// MARK: HTML attributes

extension MarkdownImage {
  /// An `<img>` tag's image: its src, alt, and the width and height it
  /// asks for in plain pixels (a percentage is left to the layout).
  init?(htmlTag tag: Substring) {
    let attributes = htmlAttributes(tag)
    guard let source = attributes["src"], !source.isEmpty else {
      return nil
    }
    self.init(
      source: source, alt: attributes["alt"] ?? "",
      width: pixels(attributes["width"]), height: pixels(attributes["height"])
    )
  }
}

/// A tag's attributes by lowercased name, values unquoted and decoded.
private func htmlAttributes(_ tag: Substring) -> [String: String] {
  var attributes: [String: String] = [:]
  var index = tag.startIndex
  func advance() {
    index = tag.index(after: index)
  }
  func skip(while test: (Character) -> Bool) {
    while index < tag.endIndex, test(tag[index]) {
      advance()
    }
  }
  // The "<" and the tag's name.
  advance()
  skip { !$0.isWhitespace && $0 != ">" && $0 != "/" }
  while index < tag.endIndex {
    skip { $0.isWhitespace || $0 == "/" }
    guard index < tag.endIndex, tag[index] != ">" else {
      break
    }
    let nameStart = index
    skip { !$0.isWhitespace && $0 != "=" && $0 != ">" && $0 != "/" }
    let name = tag[nameStart ..< index].lowercased()
    skip(while: \.isWhitespace)
    guard index < tag.endIndex, tag[index] == "=" else {
      continue
    }
    advance()
    skip(while: \.isWhitespace)
    guard index < tag.endIndex else {
      break
    }
    let value: Substring
    let quote = tag[index]
    if quote == "\"" || quote == "'" {
      advance()
      let start = index
      skip { $0 != quote }
      value = tag[start ..< index]
      if index < tag.endIndex {
        advance()
      }
    } else {
      let start = index
      skip { !$0.isWhitespace && $0 != ">" }
      value = tag[start ..< index]
    }
    if attributes[name] == nil {
      attributes[name] = decodeEntities(String(value))
    }
  }
  return attributes
}

/// "382" or "382px" as points; nil for anything else.
private func pixels(_ value: String?) -> CGFloat? {
  guard var value = value?.trimmingCharacters(in: .whitespaces).lowercased() else {
    return nil
  }
  if value.hasSuffix("px") {
    value.removeLast(2)
  }
  return Double(value).flatMap { $0 > 0 ? CGFloat($0) : nil }
}

/// The handful of entities forge HTML actually carries.
private func decodeEntities(_ text: String) -> String {
  guard text.contains("&") else {
    return text
  }
  return text
    .replacingOccurrences(of: "&quot;", with: "\"")
    .replacingOccurrences(of: "&#39;", with: "'")
    .replacingOccurrences(of: "&apos;", with: "'")
    .replacingOccurrences(of: "&lt;", with: "<")
    .replacingOccurrences(of: "&gt;", with: ">")
    .replacingOccurrences(of: "&nbsp;", with: "\u{00A0}")
    .replacingOccurrences(of: "&amp;", with: "&")
}
