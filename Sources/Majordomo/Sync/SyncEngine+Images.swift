// The images previews show, fetched through the provider clients.

import Foundation

extension SyncEngine {
  /// An image a preview's body shows, fetched through the account the
  /// previewed item came through — its client decides what, if anything,
  /// the account's token may unlock — or anonymously once that account is
  /// gone. `page` is the item's url. nil when the image can't be had; demo
  /// mode serves its fixtures' own and never touches the network.
  func image(_ url: URL, account: AccountId, page: String) async -> Data? {
    if offline {
      return DemoData.image(url)
    }
    guard let stored = store.getAccount(account), let config = stored.config,
          let client = clients[stored.provider] else {
      return try? await fetchPublicImage(url)
    }
    return try? await client.fetchImage(config, url: url, page: page)
  }
}
