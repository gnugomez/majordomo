// A connected account's face: the provider avatar when it loads, the
// provider mark in a circle otherwise. GitHub avatars are derivable from the
// username alone, so accounts stored before avatar URLs existed still get
// one immediately.

import SwiftUI

struct AccountAvatar: View {
  let account: AccountState
  var size: CGFloat = 22

  private var url: URL? {
    if let avatarUrl = account.avatarUrl, let url = URL(string: avatarUrl) {
      return url
    }
    if let username = account.username {
      return spec(for: account.provider).fallbackAvatarURL(username: username)
    }
    return nil
  }

  var body: some View {
    AsyncImage(url: url) { image in
      image
        .resizable()
        .scaledToFill()
    } placeholder: {
      Circle()
        .fill(.quaternary.opacity(0.7))
        .overlay {
          ProviderMark(provider: account.provider)
            .foregroundStyle(.secondary)
            .frame(width: size * 0.5, height: size * 0.5)
        }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
  }
}
