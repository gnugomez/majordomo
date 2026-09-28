// The Intelligence settings page: one switch over every on-device feature,
// and the pattern-watching that rides on it. Both features — drafting a
// rule from a sentence, and suggesting a label for a pattern — run on
// Apple's on-device model, so the page says plainly that nothing leaves
// the Mac. What the hardware allows and what the user wants are kept
// apart: an unavailable model explains itself and disables the switches,
// which is not the same as being turned off.

import SwiftUI

struct IntelligenceSettingsView: View {
  let model: AppModel

  private var available: Bool {
    model.intelligence.isAvailable
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      VStack(spacing: 0) {
        SettingsRow(symbol: "apple.intelligence", label: "Use Apple Intelligence") {
          Toggle(
            "Use Apple Intelligence",
            isOn: Binding(
              get: { model.intelligenceEnabled },
              set: { model.setIntelligenceEnabled($0) }
            )
          )
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.small)
          .disabled(!available)
        }

        Divider().padding(.leading, 40)

        SettingsRow(symbol: "sparkles", label: "Suggest labels from patterns") {
          Toggle(
            "Suggest labels from patterns",
            isOn: Binding(
              get: { model.suggestionsEnabled },
              set: { model.setSuggestionsEnabled($0) }
            )
          )
          .labelsHidden()
          .toggleStyle(.switch)
          .controlSize(.small)
          .disabled(!available || !model.intelligenceEnabled)
        }
      }
      .settingsCard()

      if let reason = model.intelligence.reason {
        SettingsHint(text: reason)
      } else {
        SettingsHint(
          text: "Describe a rule in your own words on the Rules page and the model drafts it for you to confirm. With suggestions on, it also watches for patterns — a repo or a sender that keeps coming up — and offers a label for them. Both run entirely on this Mac; no notification text is ever sent anywhere."
        )
      }
    }
    .padding(16)
    .task {
      model.refreshIntelligence()
    }
  }
}
