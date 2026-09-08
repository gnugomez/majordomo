// User notifications, ported from the notify() half of src/electron/sync.ts.
// UNUserNotificationCenter requires a real app bundle — a bare `swift run`
// executable logs and skips instead of crashing.

import Foundation
import os
import UserNotifications

private let log = Logger(subsystem: "dev.majordomo.app", category: "notify")

final class Notifier: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
  /// The shared openItem action: opens in the browser and marks read.
  private let openItem: @Sendable (String) async -> Void

  init(openItem: @escaping @Sendable (String) async -> Void) {
    self.openItem = openItem
    super.init()
    guard isBundled else {
      log.warning("not running from an app bundle; notifications disabled")
      return
    }
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    center.requestAuthorization(options: [.alert, .sound]) { _, error in
      if let error {
        log.warning("notification authorization failed: \(error)")
      }
    }
  }

  func post(_ item: InboxItem, sound: String) {
    guard isBundled else {
      return
    }
    let content = UNMutableNotificationContent()
    // Repo, with the provider name as fallback (a GitLab todo may carry no
    // project).
    content.title = item.repo.isEmpty ? item.provider.displayName : item.repo
    content.body = item.title
    content.userInfo = ["itemId": item.id]
    // "none" leaves the notification silent; a tone name resolves against
    // the system alert sounds (/System/Library/Sounds).
    switch sound {
    case "none":
      break
    case "default":
      content.sound = .default
    default:
      content.sound = UNNotificationSound(named: UNNotificationSoundName("\(sound).aiff"))
    }
    let request = UNNotificationRequest(identifier: item.id, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request) { error in
      if let error {
        log.warning("notification delivery failed: \(error)")
      }
    }
  }

  // Clicking the notification opens the item, like the Electron app.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    if let id = response.notification.request.content.userInfo["itemId"] as? String {
      await openItem(id)
    }
  }

  // Show banners even while the app is frontmost (an open window shouldn't
  // swallow a mention).
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }
}
