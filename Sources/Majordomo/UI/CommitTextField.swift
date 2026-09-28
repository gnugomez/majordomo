// A text field that hands its text back on submit or when focus leaves —
// never per keystroke. Label and rule edits each re-sweep every item and
// rewrite the store, so the settings pages commit them whole.

import SwiftUI

struct CommitTextField: View {
  /// Placeholder.
  let title: String
  /// The committed value; the draft resyncs to it whenever it changes
  /// while the field isn't being edited.
  let text: String
  let onCommit: (String) -> Void

  @State private var draft: String
  @FocusState private var focused: Bool

  init(_ title: String, text: String, onCommit: @escaping (String) -> Void) {
    self.title = title
    self.text = text
    self.onCommit = onCommit
    _draft = State(initialValue: text)
  }

  var body: some View {
    TextField(title, text: $draft)
      .focused($focused)
      .onSubmit(commit)
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
