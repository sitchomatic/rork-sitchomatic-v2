import Foundation

@MainActor
final class NordLynxConfigGeneratorService {
    static let shared = NordLynxConfigGeneratorService()

    private let defaultDNS = "103.86.96.100, 103.86.99.100"
    private let defaultAllowedIPs = "0.0.0.0/0, ::/0"
    private let defaultEndpointPort = 51820
    private let interfaceAddressIPv4 = "10.5.0.2/32"

    func generateConfig(server: NordServer, privateKey: String) throws -> WireGuardConfig {
        guard !privateKey.isEmpty else {
            throw ConfigGeneratorError.missingPrivateKey
        }

        guard !server.ip.isEmpty else {
            throw ConfigGeneratorError.invalidServerData("Missing server IP")
        }

        let serverPublicKey: String
        if !server.publicKey.isEmpty {
            serverPublicKey = server.publicKey
        } else {
            throw ConfigGeneratorError.invalidServerData("Missing server public key for \(server.hostname)")
        }

        return WireGuardConfig(
            privateKey: privateKey,
            address: interfaceAddressIPv4,
            dns: defaultDNS,
            publicKey: serverPublicKey,
            endpoint: "\(server.ip):\(defaultEndpointPort)",
            allowedIPs: defaultAllowedIPs,
            serverName: server.hostname
        )
    }

    func generateConfigs(servers: [NordServer], privateKey: String) -> [WireGuardConfig] {
        servers.compactMap { server in
            try? generateConfig(server: server, privateKey: privateKey)
        }
    }

    func generateINIString(from config: WireGuardConfig) -> String {
        var lines: [String] = []

        lines.append("[Interface]")
        lines.append("PrivateKey = \(config.privateKey)")
        lines.append("Address = \(config.address)")
        lines.append("DNS = \(config.dns)")
        lines.append("")
        lines.append("[Peer]")
        lines.append("PublicKey = \(config.publicKey)")
        lines.append("AllowedIPs = \(config.allowedIPs)")
        lines.append("Endpoint = \(config.endpoint)")
        lines.append("PersistentKeepalive = 25")

        return lines.joined(separator: "\n")
    }
}

nonisolated enum ConfigGeneratorError: Error, LocalizedError, Sendable {
    case missingPrivateKey
    case invalidServerData(String)

    var errorDescription: String? {
        switch self {
        case .missingPrivateKey:
            "WireGuard private key is missing. Regenerate keys in Network Settings."
        case .invalidServerData(let detail):
            "Invalid server data: \(detail)"
        }
    }
}
