// The icon sheet for a label or a sidebar folder: a curated symbol grid, a
// free symbol-name field for anything the grid lacks, and — for a label —
// the tint swatches. Done hands the choice back; nothing is stored until
// then.

import AppKit
import SwiftUI

/// Symbols that suit folders, tags, priorities, and areas — filtered at
/// launch to those this macOS actually ships.
private let curatedSymbols: [String] = [
  "tag", "flag", "flame", "bolt", "star", "exclamationmark.triangle", "bell", "clock",
  "calendar", "server.rack", "shippingbox", "wrench", "hammer", "ladybug", "shield", "lock",
  "key", "doc", "folder", "tray", "envelope", "bubble", "person", "person.2",
  "building.2", "globe", "network", "cloud", "terminal", "chevron.left.forwardslash.chevron.right", "gearshape", "testtube.2",
  "chart.bar", "book", "lightbulb", "moon.zzz", "leaf", "paintbrush", "cpu", "memorychip",
  "externaldrive", "antenna.radiowaves.left.and.right", "creditcard", "cart", "gift", "heart", "eye", "pin",
].filter { symbolExists($0) }

private func symbolExists(_ name: String) -> Bool {
  NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
}

struct IconPickerSheet: View {
  /// What the preview names.
  let name: String
  /// nil for a folder: no swatches, a plain symbol in the preview.
  let initialTint: LabelTint?
  let onDone: (_ symbol: String, _ tint: LabelTint?) -> Void

  @Environment(\.dismiss) private var dismiss

  @State private var symbol: String
  @State private var tint: LabelTint
  @State private var customSymbol: String

  init(name: String, symbol: String, tint: LabelTint?, onDone: @escaping (_ symbol: String, _ tint: LabelTint?) -> Void) {
    self.name = name
    initialTint = tint
    self.onDone = onDone
    _symbol = State(initialValue: symbol)
    _tint = State(initialValue: tint ?? .accent)
    _customSymbol = State(initialValue: curatedSymbols.contains(symbol) ? "" : symbol)
  }

  /// The sheet for a label: symbol and tint, handed back on the label.
  init(label: InboxLabel, onDone: @escaping (InboxLabel) -> Void) {
    self.init(name: label.name, symbol: label.symbol, tint: label.tint) { symbol, tint in
      var updated = label
      updated.symbol = symbol
      updated.tint = tint ?? label.tint
      onDone(updated)
    }
  }

  private let columns = Array(repeating: GridItem(.fixed(36), spacing: 6), count: 8)

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Choose an Icon")
        .font(.system(size: 15, weight: .semibold))
        .frame(maxWidth: .infinity)

      // The label or folder as the sidebar will show it.
      HStack(spacing: 10) {
        if initialTint != nil {
          LabelGlyph(symbol: symbol, tint: tint, size: 32)
        } else {
          Image(systemName: symbol)
            .font(.system(size: 20))
            .foregroundStyle(.secondary)
            .frame(width: 32, height: 32)
        }
        Text(name)
          .font(.system(size: 13, weight: .medium))
        Spacer()
      }
      .padding(10)
      .settingsCard()

      if initialTint != nil {
        HStack(spacing: 8) {
          ForEach(LabelTint.allCases, id: \.self) { candidate in
            Button {
              tint = candidate
            } label: {
              Circle()
                .fill(candidate.color)
                .frame(width: 20, height: 20)
                .overlay {
                  if candidate == tint {
                    Circle().strokeBorder(.primary, lineWidth: 2)
                  }
                }
            }
            .buttonStyle(.plain)
            .help(candidate.rawValue.capitalized)
          }
          Spacer()
        }
      }

      LazyVGrid(columns: columns, spacing: 6) {
        ForEach(curatedSymbols, id: \.self) { candidate in
          Button {
            symbol = candidate
            customSymbol = ""
          } label: {
            Image(systemName: candidate)
              .font(.system(size: 15))
              .frame(width: 36, height: 32)
              .foregroundStyle(candidate == symbol ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.primary))
              .background(
                candidate == symbol
                  ? AnyShapeStyle(Color.accentColor.opacity(0.15))
                  : AnyShapeStyle(.quaternary.opacity(0.4)),
                in: RoundedRectangle(cornerRadius: 6)
              )
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .help(candidate)
        }
      }

      // Anything SF Symbols has and the grid doesn't.
      HStack(spacing: 8) {
        TextField("Any SF Symbol name", text: $customSymbol)
          .textFieldStyle(.roundedBorder)
          .autocorrectionDisabled()
          .onChange(of: customSymbol) {
            let trimmed = customSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, symbolExists(trimmed) {
              symbol = trimmed
            }
          }
        Image(systemName: customSymbolValid ? "checkmark.circle" : "questionmark.circle")
          .foregroundStyle(customSymbolValid ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tertiary))
          .help(customSymbolValid ? "Symbol found" : "Type an SF Symbol name, e.g. “bolt.horizontal”")
      }

      HStack {
        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        Spacer()
        Button("Done") {
          onDone(symbol, initialTint == nil ? nil : tint)
          dismiss()
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
        .disabled(!symbolExists(symbol))
      }
      .padding(.top, 4)
    }
    .padding(20)
    .frame(width: 380)
  }

  private var customSymbolValid: Bool {
    let trimmed = customSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
    return !trimmed.isEmpty && symbolExists(trimmed)
  }
}

/// A label's mark: its symbol on a disc of its tint — the Labels list, the
/// icon sheet, and anywhere else a label is named.
struct LabelGlyph: View {
  let symbol: String
  let tint: LabelTint
  /// The list-row size every settings page and the outline share; inline
  /// uses inside a card pass something smaller.
  var size: CGFloat = 18

  var body: some View {
    Circle()
      .fill(tint.color)
      .frame(width: size, height: size)
      .overlay {
        Image(systemName: symbol)
          .font(.system(size: size * 0.48, weight: .semibold))
          .foregroundStyle(.white)
      }
  }
}
