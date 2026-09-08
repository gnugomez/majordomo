// Token encryption at rest. Tokens live AES-GCM-encrypted in the JSON store;
// the symmetric key is a single Keychain generic-password item for the whole
// app — never one keychain item per token (per-item ACLs re-prompt on every
// rebuild of an app without an Apple-issued certificate; see CONTRIBUTING.md).
// If the Keychain is unavailable the store falls back to plaintext with a
// logged warning.

import CryptoKit
import Foundation
import os
import Security

private let log = Logger(subsystem: "dev.majordomo.app", category: "store")

enum TokenCipher {
  private static let service = "dev.majordomo.app"
  private static let account = "store-key"

  /// The app's one encryption key, created on first use. nil when the
  /// Keychain refused both read and write.
  static func loadOrCreateKey() -> SymmetricKey? {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecSuccess, let data = result as? Data, data.count == 32 {
      return SymmetricKey(data: data)
    }
    if status != errSecItemNotFound {
      log.warning("keychain read failed (\(status)); tokens will be stored in plain text")
      return nil
    }
    let key = SymmetricKey(size: .bits256)
    let keyData = key.withUnsafeBytes { Data($0) }
    query.removeValue(forKey: kSecReturnData as String)
    query[kSecValueData as String] = keyData
    query[kSecAttrLabel as String] = "Majordomo token encryption key"
    let addStatus = SecItemAdd(query as CFDictionary, nil)
    guard addStatus == errSecSuccess else {
      log.warning("keychain write failed (\(addStatus)); tokens will be stored in plain text")
      return nil
    }
    return key
  }

  /// Base64 of nonce+ciphertext+tag, or nil if sealing failed.
  static func encrypt(_ token: String, key: SymmetricKey) -> String? {
    guard let sealed = try? AES.GCM.seal(Data(token.utf8), using: key),
          let combined = sealed.combined else {
      return nil
    }
    return combined.base64EncodedString()
  }

  static func decrypt(_ stored: String, key: SymmetricKey) -> String? {
    guard let combined = Data(base64Encoded: stored),
          let box = try? AES.GCM.SealedBox(combined: combined),
          let plain = try? AES.GCM.open(box, using: key) else {
      return nil
    }
    return String(data: plain, encoding: .utf8)
  }
}
