// A multi-line field that hands its text back when focus leaves — never
// per keystroke, for the same reason as CommitTextField: a rule edit
// re-sweeps every item and rewrites the store. A rule's question is the one
// thing in settings worth several lines, so it gets its own editor rather
// than a text field that scrolls sideways.

import SwiftUI

struct CommitTextEditor: View {
  /// Shown while the text is empty.
  let prompt: String
  /// The committed value; the draft resyncs to it whenever it changes
  /// while the editor isn't being edited.
  let text: String
  let onCommit: (String) -> Void

  @State private var draft: String
  @FocusState private var focused: Bool

  init(prompt: String, text: String, onCommit: @escaping (String) -> Void) {
    self.prompt = prompt
    self.text = text
    self.onCommit = onCommit
    _draft = State(initialValue: text)
  }

  var body: some View {
    TextEditor(text: $draft)
      .font(.system(size: 12))
      .scrollContentBackground(.hidden)
      .padding(6)
      .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
      .overlay(alignment: .topLeading) {
        if draft.isEmpty {
          Text(prompt)
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 11)
            .padding(.vertical, 14)
            // The placeholder is a backdrop, never a click target that
            // would keep the caret out of the editor underneath.
            .allowsHitTesting(false)
        }
      }
      .focused($focused)
      .onChange(of: focused) {
        if !focused {
          commit()
        }
      }
      .onChange(of: text) {
        if !focused {
          draft = text
        }
      }
  }

  private func commit() {
    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed != text {
      onCommit(trimmed)
    }
  }
}
