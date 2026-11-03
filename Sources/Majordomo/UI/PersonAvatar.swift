// Someone's face — in a conversation, or among a board card's assignees:
// the picture the provider linked, or the one its spec derives from the
// login, fetched like a body's images (the environment's BodyImageSource,
// cached on disk); their initial in a steady color until it arrives, or
// when there is none.

import SwiftUI

struct PersonAvatar: View {
  let login: String?
  let avatarUrl: String?
  let provider: ProviderId
  var size: CGFloat = 24

  @Environment(\.bodyImages) private var source
  @Environment(\.displayScale) private var displayScale
  @State private var loaded: BodyImage?

  private var url: URL? {
    if let avatarUrl, let url = source?.resolve(avatarUrl) {
      return url
    }
    return login.flatMap { spec(for: provider).fallbackAvatarURL(username: $0) }
  }

  var body: some View {
    let url = url
    let pixels = size * displayScale
    Group {
      if let shown = loaded ?? url.flatMap({ source?.cachedImage(at: $0, pixelWidth: pixels) }) {
        Image(nsImage: shown.image)
          .resizable()
          .interpolation(.high)
          .scaledToFill()
      } else {
        initial
      }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
    .accessibilityHidden(true)
    .task(id: url) {
      guard let source, let url else {
        return
      }
      loaded = await source.image(at: url, pixelWidth: pixels)
    }
  }

  private var initial: some View {
    Circle()
      .fill(Palette.face(for: login))
      .overlay {
        Text((login?.prefix(1) ?? "?").uppercased())
          .font(.system(size: size * 0.48, weight: .semibold))
          .foregroundStyle(.white)
      }
  }
}
