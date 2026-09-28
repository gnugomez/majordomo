// The account sheet, opened from the Accounts settings page. Adding picks a
// provider (any number of accounts per provider) and takes the token — plus
// whatever the provider's spec says it needs — and Connect validates and
// dismisses on success. Updating a token shows the account in place of the
// provider chips and asks only for the new token.

import SwiftUI

struct AddAccountSheet: View {
  let model: AppModel
  /// The connected account whose token is being replaced; nil adds a new
  /// account.
  let updating: AccountState?

  @Environment(\.dismiss) private var dismiss

  @State private var providerId: ProviderId
  @State private var url = ""
  @State private var token = ""
  @State private var localError: String?
  @State private var submitted = false

  init(model: AppModel, updating: AccountState? = nil) {
    self.model = model
    self.updating = updating
    _providerId = State(initialValue: updating?.provider ?? providerSpecs[0].id)
  }

  private var chosenSpec: any ProviderSpec {
    spec(for: providerId)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(updating == nil ? "Add Account" : "Update Token")
        .font(.system(size: 15, weight: .semibold))
        .frame(maxWidth: .infinity)

      if let updating {
        accountRow(updating)
      } else {
        providerChips
        if chosenSpec.needsBaseUrl {
          TextField("https://gitlab.example.com", text: $url)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .disabled(model.connecting)
        }
      }
      SecureField(updating == nil ? "Personal access token" : "New personal access token", text: $token)
        .textFieldStyle(.roundedBorder)
        .disabled(model.connecting)
        .onSubmit(submit)
      Text(chosenSpec.tokenHint)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)

      if let error = displayError {
        Text(error)
          .font(.system(size: 11))
          .foregroundStyle(.red)
      }

      HStack {
        Button("Cancel") {
          dismiss()
        }
        .keyboardShortcut(.cancelAction)
        Spacer()
        Button(submitLabel, action: submit)
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.defaultAction)
          .disabled(model.connecting)
      }
      .padding(.top, 4)
    }
    .padding(20)
    .frame(width: 380)
    // Dismiss the moment the connect lands.
    .onChange(of: model.connecting) {
      if submitted, !model.connecting, model.connectError == nil {
        dismiss()
      }
    }
    // A failure from one provider must not linger over another's form.
    .onChange(of: providerId) {
      localError = nil
      submitted = false
    }
  }

  /// Provider chips with the real marks — a segmented picker can't hold the
  /// custom glyphs.
  private var providerChips: some View {
    HStack(spacing: 8) {
      ForEach(providerSpecs, id: \.id) { candidate in
        Button {
          providerId = candidate.id
        } label: {
          HStack(spacing: 6) {
            ProviderMark(provider: candidate.id)
              .frame(width: 14, height: 14)
            Text(candidate.displayName)
              .font(.system(size: 13, weight: .medium))
          }
          .foregroundStyle(providerId == candidate.id ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
          .padding(.vertical, 7)
          .frame(maxWidth: .infinity)
          .background(
            providerId == candidate.id
              ? AnyShapeStyle(Color.accentColor.opacity(0.12))
              : AnyShapeStyle(.quaternary.opacity(0.5)),
            in: RoundedRectangle(cornerRadius: 8)
          )
          .overlay {
            if providerId == candidate.id {
              RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.connecting)
      }
    }
  }

  /// Whose token is being replaced — the same row the Accounts list shows.
  private func accountRow(_ account: AccountState) -> some View {
    HStack(spacing: 10) {
      AccountAvatar(account: account, size: 26)
      VStack(alignment: .leading, spacing: 1) {
        Text(account.name ?? "@\(account.username ?? "unknown")")
          .font(.system(size: 13, weight: .medium))
        Text(accountDescriptor(account))
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer()
    }
    .padding(10)
    .settingsCard()
  }

  private var submitLabel: String {
    if model.connecting {
      return "Validating…"
    }
    return updating == nil ? "Connect" : "Update"
  }

  private var displayError: String? {
    if model.connecting {
      return nil
    }
    return localError ?? (submitted ? model.connectError : nil)
  }

  private func submit() {
    let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
    var baseUrl: String?
    // An update keeps the account's own instance; only a new account asks.
    if updating == nil, chosenSpec.needsBaseUrl {
      guard let origin = normalizeInstanceOrigin(url) else {
        localError = "Enter your instance URL, e.g. https://gitlab.example.com"
        return
      }
      baseUrl = origin
    }
    guard !trimmedToken.isEmpty else {
      localError = "Enter a personal access token."
      return
    }
    localError = nil
    submitted = true
    if let updating {
      model.updateToken(updating.id, token: trimmedToken)
    } else {
      model.connect(providerId, config: AccountConfig(token: trimmedToken, baseUrl: baseUrl))
    }
  }
}
