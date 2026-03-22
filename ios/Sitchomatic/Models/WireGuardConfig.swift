import Foundation

nonisolated struct WireGuardConfig: Codable, Sendable, Identifiable {
    var id: String { endpoint }
    let privateKey: String
    let address: String
    let dns: String
    let publicKey: String
    let endpoint: String
    let allowedIPs: String
    let serverName: String?
}
