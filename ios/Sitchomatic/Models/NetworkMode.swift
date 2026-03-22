import Foundation

nonisolated enum NetworkMode: String, Codable, Sendable, CaseIterable {
    case socks5
    case nord
    case hybrid

    var displayName: String {
        switch self {
        case .socks5: "SOCKS5"
        case .nord: "Nord VPN"
        case .hybrid: "Hybrid"
        }
    }

    var iconName: String {
        switch self {
        case .socks5: "network"
        case .nord: "shield.checkered"
        case .hybrid: "arrow.triangle.branch"
        }
    }

    var tintColor: String {
        switch self {
        case .socks5: "orange"
        case .nord: "blue"
        case .hybrid: "purple"
        }
    }

    var subtitle: String {
        switch self {
        case .socks5: "External SOCKS5 proxy list"
        case .nord: "Nord WireGuard tunnel"
        case .hybrid: "Auto failover: SOCKS5 → Nord"
        }
    }
}

nonisolated enum IPAssignmentMode: String, Codable, Sendable, CaseIterable {
    case separatePerSession
    case appWideUnited

    var displayName: String {
        switch self {
        case .separatePerSession: "Separate IP per Session"
        case .appWideUnited: "App-Wide United IP"
        }
    }

    var iconName: String {
        switch self {
        case .separatePerSession: "square.stack.3d.up"
        case .appWideUnited: "link"
        }
    }
}

nonisolated enum NordIPCount: Int, Codable, Sendable, CaseIterable {
    case five = 5
    case ten = 10
    case twentyFive = 25
    case fifty = 50

    var displayName: String {
        "\(rawValue) IPs"
    }
}

nonisolated struct SOCKS5Proxy: Codable, Sendable, Identifiable, Hashable {
    let id: UUID
    let host: String
    let port: Int
    let username: String?
    let password: String?

    var connectionString: String {
        if let username, let password {
            return "\(username):\(password)@\(host):\(port)"
        }
        return "\(host):\(port)"
    }

    static func parse(from rawList: String) -> [SOCKS5Proxy] {
        rawList
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .compactMap { line -> SOCKS5Proxy? in
                if line.contains("@") {
                    let parts = line.split(separator: "@", maxSplits: 1)
                    guard parts.count == 2 else { return nil }
                    let authParts = parts[0].split(separator: ":", maxSplits: 1)
                    let hostParts = parts[1].split(separator: ":", maxSplits: 1)
                    guard authParts.count == 2, hostParts.count == 2,
                          let port = Int(hostParts[1]) else { return nil }
                    return SOCKS5Proxy(
                        id: UUID(),
                        host: String(hostParts[0]),
                        port: port,
                        username: String(authParts[0]),
                        password: String(authParts[1])
                    )
                } else {
                    let parts = line.split(separator: ":", maxSplits: 1)
                    guard parts.count == 2, let port = Int(parts[1]) else { return nil }
                    return SOCKS5Proxy(
                        id: UUID(),
                        host: String(parts[0]),
                        port: port,
                        username: nil,
                        password: nil
                    )
                }
            }
    }
}

nonisolated struct NordConfiguration: Codable, Sendable {
    var accessKey: String
    var ipCount: NordIPCount

    static let `default` = NordConfiguration(accessKey: "", ipCount: .five)
}

nonisolated enum ConnectionStatus: String, Sendable {
    case disconnected
    case connecting
    case connected
    case rotating
    case failingOver
    case error

    var displayName: String {
        switch self {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting..."
        case .connected: "Connected"
        case .rotating: "Rotating..."
        case .failingOver: "Failing Over..."
        case .error: "Error"
        }
    }

    var iconName: String {
        switch self {
        case .disconnected: "circle"
        case .connecting: "arrow.trianglehead.2.clockwise"
        case .connected: "checkmark.circle.fill"
        case .rotating: "arrow.triangle.2.circlepath"
        case .failingOver: "exclamationmark.arrow.triangle.2.circlepath"
        case .error: "xmark.circle.fill"
        }
    }

    var isActive: Bool {
        self == .connected || self == .rotating
    }
}

nonisolated enum ProxySource: String, Codable, Sendable {
    case socks5
    case nord
}

nonisolated struct ResolvedProxy: Sendable, Identifiable {
    let id: UUID
    let host: String
    let port: Int
    let username: String?
    let password: String?
    let source: ProxySource
    let serverName: String?
}

nonisolated struct ActiveProxy: Sendable {
    let mode: NetworkMode
    let displayIP: String
    let host: String
    let port: Int
    let connectedSince: Date
    let index: Int
    let totalCount: Int
}

nonisolated struct ProxyEndpoint: Sendable {
    let host: String
    let port: Int
    let username: String?
    let password: String?
}

nonisolated struct NetworkSettings: Codable, Sendable {
    var mode: NetworkMode
    var ipAssignment: IPAssignmentMode
    var socks5RawList: String
    var nordConfig: NordConfiguration
    var rotationIntervalSeconds: Int
    var hybridFailoverEnabled: Bool

    static let `default` = NetworkSettings(
        mode: .hybrid,
        ipAssignment: .separatePerSession,
        socks5RawList: "",
        nordConfig: .default,
        rotationIntervalSeconds: 300,
        hybridFailoverEnabled: true
    )
}

nonisolated enum NetworkError: Error, LocalizedError, Sendable {
    case noProxiesConfigured
    case noNordAccessKey
    case noNordKeyPair
    case noNordServersAvailable
    case proxyIndexOutOfBounds
    case connectionFailed(String)
    case allFailoverExhausted
    case tunnelSetupFailed(String)

    var errorDescription: String? {
        switch self {
        case .noProxiesConfigured:
            "No proxies configured. Paste a SOCKS5 list or add a Nord access key."
        case .noNordAccessKey:
            "No Nord access key. Paste your access key in Network Settings."
        case .noNordKeyPair:
            "No Nord WireGuard key pair generated. Check your Nord configuration."
        case .noNordServersAvailable:
            "Could not fetch Nord servers. Check your access key and network."
        case .proxyIndexOutOfBounds:
            "Proxy index out of range. Resetting rotation."
        case .connectionFailed(let detail):
            "Connection failed: \(detail)"
        case .allFailoverExhausted:
            "All failover attempts exhausted. Check your proxy and Nord configuration."
        case .tunnelSetupFailed(let detail):
            "WireGuard tunnel setup failed: \(detail)"
        }
    }
}
