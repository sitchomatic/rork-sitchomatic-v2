import Foundation
import Security
import CryptoKit

@MainActor
final class NordVPNKeyStore {
    static let shared = NordVPNKeyStore()

    private let service = "com.sitchomatic.nordvpn"

    var privateKey: String? {
        keychainRead(account: "wireguard.privateKey")
    }

    var publicKey: String? {
        keychainRead(account: "wireguard.publicKey")
    }

    var accessToken: String? {
        keychainRead(account: "accessToken")
    }

    func saveAccessToken(_ token: String) {
        keychainWrite(account: "accessToken", value: token)
    }

    func saveKeyPair(privateKey: String, publicKey: String) {
        keychainWrite(account: "wireguard.privateKey", value: privateKey)
        keychainWrite(account: "wireguard.publicKey", value: publicKey)
    }

    func generateKeyPairIfNeeded() -> (privateKey: String, publicKey: String) {
        if let existingPrivate = privateKey, let existingPublic = publicKey,
           !existingPrivate.isEmpty, !existingPublic.isEmpty {
            return (existingPrivate, existingPublic)
        }

        let newPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let privateKeyBase64 = newPrivateKey.rawRepresentation.base64EncodedString()
        let publicKeyBase64 = newPrivateKey.publicKey.rawRepresentation.base64EncodedString()

        saveKeyPair(privateKey: privateKeyBase64, publicKey: publicKeyBase64)
        return (privateKeyBase64, publicKeyBase64)
    }

    func deleteAllKeys() {
        keychainDelete(account: "wireguard.privateKey")
        keychainDelete(account: "wireguard.publicKey")
        keychainDelete(account: "accessToken")
    }

    // MARK: - Keychain Operations

    private func keychainWrite(account: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        keychainDelete(account: account)

        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    private func keychainRead(account: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private func keychainDelete(account: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]

        SecItemDelete(query as CFDictionary)
    }
}
