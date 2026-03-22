import Foundation

@Observable
@MainActor
final class SimpleNetworkManager {

    // MARK: - Published State

    var connectionStatus: ConnectionStatus = .disconnected
    var activeProxy: ActiveProxy?
    var statusMessage: String = "Not connected"
    var resolvedProxies: [ResolvedProxy] = []
    var settings: NetworkSettings

    // MARK: - Dependencies

    private let nordService: NordVPNService
    private let nordConfigGenerator: NordLynxConfigGeneratorService
    private let nordKeyStore: NordVPNKeyStore

    // MARK: - Internal State

    private(set) var wireProxyBridges: [WireProxyBridge] = []
    private var generatedWireGuardConfigs: [WireGuardConfig] = []
    private var parsedSOCKS5Proxies: [SOCKS5Proxy] = []
    private var currentIndex: Int = 0
    private var rotationTask: Task<Void, Never>?
    private var failoverAttempts: Int = 0
    private let maxFailoverAttempts: Int = 3
    private let settingsKey = "SimpleNetworkManager.settings"

    // MARK: - Singleton

    static let shared = SimpleNetworkManager()

    // MARK: - Init

    init(
        nordService: NordVPNService = .shared,
        nordConfigGenerator: NordLynxConfigGeneratorService = .shared,
        nordKeyStore: NordVPNKeyStore = .shared
    ) {
        self.nordService = nordService
        self.nordConfigGenerator = nordConfigGenerator
        self.nordKeyStore = nordKeyStore
        self.settings = Self.loadPersistedSettings()
        self.parsedSOCKS5Proxies = SOCKS5Proxy.parse(from: settings.socks5RawList)

        if let storedToken = nordKeyStore.accessToken, !storedToken.isEmpty,
           settings.nordConfig.accessKey.isEmpty {
            settings.nordConfig.accessKey = storedToken
            persistSettings()
        }
    }

    // MARK: - Connection Lifecycle

    func connect() async {
        guard connectionStatus != .connected && connectionStatus != .connecting else { return }
        connectionStatus = .connecting
        statusMessage = "Connecting..."
        failoverAttempts = 0

        do {
            switch settings.mode {
            case .socks5:
                try await connectSOCKS5()
            case .nord:
                try await connectNord()
            case .hybrid:
                try await connectHybrid()
            }
            connectionStatus = .connected
            startRotationTimer()
        } catch {
            connectionStatus = .error
            statusMessage = error.localizedDescription
        }
    }

    func disconnect() {
        rotationTask?.cancel()
        rotationTask = nil

        for bridge in wireProxyBridges {
            bridge.disconnect()
        }
        wireProxyBridges.removeAll()
        generatedWireGuardConfigs.removeAll()
        resolvedProxies.removeAll()

        activeProxy = nil
        connectionStatus = .disconnected
        statusMessage = "Disconnected"
        currentIndex = 0
        failoverAttempts = 0
    }

    func rotateToNextProxy() async {
        guard !resolvedProxies.isEmpty else { return }
        let previousStatus = connectionStatus
        connectionStatus = .rotating
        statusMessage = "Rotating to next proxy..."

        currentIndex = (currentIndex + 1) % resolvedProxies.count

        do {
            try await activateProxy(at: currentIndex)
            connectionStatus = .connected
        } catch {
            if settings.mode == .hybrid && settings.hybridFailoverEnabled {
                await failoverToNextMode()
            } else {
                connectionStatus = previousStatus.isActive ? previousStatus : .error
                statusMessage = "Rotation failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - WebView Proxy Assignment

    func proxyEndpoint(forSessionID sessionID: String) -> ProxyEndpoint? {
        switch settings.ipAssignment {
        case .appWideUnited:
            guard let active = activeProxy else { return nil }
            return ProxyEndpoint(host: active.host, port: active.port, username: nil, password: nil)
        case .separatePerSession:
            guard !resolvedProxies.isEmpty else { return nil }
            let stableHash = sessionID.utf8.reduce(0) { ($0 &+ UInt64($1)) &* 31 }
            let index = Int(stableHash % UInt64(resolvedProxies.count))
            let proxy = resolvedProxies[index]
            return ProxyEndpoint(host: proxy.host, port: proxy.port, username: proxy.username, password: proxy.password)
        }
    }

    // MARK: - SOCKS5 Configuration

    func updateSOCKS5List(_ rawText: String) {
        settings.socks5RawList = rawText
        parsedSOCKS5Proxies = SOCKS5Proxy.parse(from: rawText)
        resolvedProxies = parsedSOCKS5Proxies.map { proxy in
            ResolvedProxy(
                id: proxy.id,
                host: proxy.host,
                port: proxy.port,
                username: proxy.username,
                password: proxy.password,
                source: .socks5,
                serverName: nil
            )
        }
        persistSettings()
        statusMessage = "Parsed \(parsedSOCKS5Proxies.count) SOCKS5 proxies"
    }

    // MARK: - Nord Configuration

    func updateNordAccessKey(_ key: String) async throws {
        settings.nordConfig.accessKey = key
        nordKeyStore.saveAccessToken(key)
        persistSettings()

        if connectionStatus.isActive {
            disconnect()
            try await generateNordConfigs()
        }
    }

    func updateNordIPCount(_ count: NordIPCount) async throws {
        settings.nordConfig.ipCount = count
        persistSettings()

        if connectionStatus.isActive {
            disconnect()
            try await generateNordConfigs()
        }
    }

    // MARK: - Mode Switching

    func updateMode(_ mode: NetworkMode) {
        guard mode != settings.mode else { return }
        disconnect()
        settings.mode = mode
        persistSettings()
        statusMessage = "\(mode.displayName) mode selected"
    }

    func updateIPAssignment(_ assignment: IPAssignmentMode) {
        settings.ipAssignment = assignment
        persistSettings()
    }

    func updateHybridFailover(_ enabled: Bool) {
        settings.hybridFailoverEnabled = enabled
        persistSettings()
    }

    func updateRotationInterval(_ seconds: Int) {
        settings.rotationIntervalSeconds = max(30, seconds)
        persistSettings()

        if connectionStatus == .connected {
            rotationTask?.cancel()
            startRotationTimer()
        }
    }

    // MARK: - Quick Status

    var quickStatusLine: String {
        guard let active = activeProxy else {
            return settings.mode.displayName + " · " + connectionStatus.displayName
        }
        let indexDisplay = "\(active.index + 1)/\(active.totalCount)"
        return "\(active.mode.displayName) · \(active.displayIP) · \(indexDisplay)"
    }

    var proxyCount: Int {
        switch settings.mode {
        case .socks5:
            return parsedSOCKS5Proxies.count
        case .nord:
            return generatedWireGuardConfigs.count
        case .hybrid:
            return parsedSOCKS5Proxies.count + generatedWireGuardConfigs.count
        }
    }

    var activeBridgeCount: Int {
        wireProxyBridges.filter { $0.isConnected }.count
    }

    var totalBridgeTraffic: (sent: UInt64, received: UInt64) {
        let sent = wireProxyBridges.reduce(UInt64(0)) { $0 + $1.bytesSent }
        let received = wireProxyBridges.reduce(UInt64(0)) { $0 + $1.bytesReceived }
        return (sent, received)
    }

    var nordConfigCount: Int {
        generatedWireGuardConfigs.count
    }

    // MARK: - Private: SOCKS5 Connection

    private func connectSOCKS5() async throws {
        guard !parsedSOCKS5Proxies.isEmpty else {
            throw NetworkError.noProxiesConfigured
        }

        resolvedProxies = parsedSOCKS5Proxies.map { proxy in
            ResolvedProxy(
                id: proxy.id,
                host: proxy.host,
                port: proxy.port,
                username: proxy.username,
                password: proxy.password,
                source: .socks5,
                serverName: nil
            )
        }

        if currentIndex >= resolvedProxies.count {
            currentIndex = 0
        }

        try await activateProxy(at: currentIndex)
    }

    // MARK: - Private: Nord Connection

    private func connectNord() async throws {
        guard !settings.nordConfig.accessKey.isEmpty else {
            throw NetworkError.noNordAccessKey
        }

        _ = nordKeyStore.generateKeyPairIfNeeded()

        if generatedWireGuardConfigs.isEmpty {
            try await generateNordConfigs()
        }

        guard !generatedWireGuardConfigs.isEmpty else {
            throw NetworkError.noNordServersAvailable
        }

        if currentIndex >= generatedWireGuardConfigs.count {
            currentIndex = 0
        }

        let config = generatedWireGuardConfigs[currentIndex]
        let bridge = WireProxyBridge()

        do {
            try await bridge.connect(config: config)
        } catch {
            throw NetworkError.tunnelSetupFailed(error.localizedDescription)
        }

        wireProxyBridges.append(bridge)

        let proxy = ResolvedProxy(
            id: UUID(),
            host: "127.0.0.1",
            port: bridge.localSOCKSPort,
            username: nil,
            password: nil,
            source: .nord,
            serverName: config.serverName
        )

        if resolvedProxies.isEmpty || resolvedProxies.allSatisfy({ $0.source == .nord }) {
            resolvedProxies = generatedWireGuardConfigs.enumerated().map { i, cfg in
                ResolvedProxy(
                    id: UUID(),
                    host: i == currentIndex ? "127.0.0.1" : cfg.endpoint,
                    port: i == currentIndex ? bridge.localSOCKSPort : 51820,
                    username: nil,
                    password: nil,
                    source: .nord,
                    serverName: cfg.serverName
                )
            }
        }

        activeProxy = ActiveProxy(
            mode: .nord,
            displayIP: config.endpoint,
            host: "127.0.0.1",
            port: bridge.localSOCKSPort,
            connectedSince: Date(),
            index: currentIndex,
            totalCount: generatedWireGuardConfigs.count
        )
        statusMessage = "Connected via Nord WireGuard (\(config.serverName ?? config.endpoint))"
    }

    // MARK: - Private: Hybrid Connection

    private func connectHybrid() async throws {
        if !parsedSOCKS5Proxies.isEmpty {
            do {
                try await connectSOCKS5()
                return
            } catch {
                statusMessage = "SOCKS5 failed, trying Nord WireGuard..."
            }
        }

        if !settings.nordConfig.accessKey.isEmpty {
            do {
                try await connectNord()
                return
            } catch {
                statusMessage = "Nord WireGuard failed: \(error.localizedDescription)"
            }
        }

        throw NetworkError.noProxiesConfigured
    }

    // MARK: - Private: Proxy Activation

    private func activateProxy(at index: Int) async throws {
        guard index < resolvedProxies.count else {
            throw NetworkError.proxyIndexOutOfBounds
        }

        let proxy = resolvedProxies[index]

        switch proxy.source {
        case .socks5:
            activeProxy = ActiveProxy(
                mode: .socks5,
                displayIP: "\(proxy.host):\(proxy.port)",
                host: proxy.host,
                port: proxy.port,
                connectedSince: Date(),
                index: index,
                totalCount: resolvedProxies.count
            )
            statusMessage = "Connected via SOCKS5 (\(proxy.host):\(proxy.port))"

        case .nord:
            for bridge in wireProxyBridges {
                bridge.disconnect()
            }
            wireProxyBridges.removeAll()

            guard index < generatedWireGuardConfigs.count else {
                throw NetworkError.proxyIndexOutOfBounds
            }

            let config = generatedWireGuardConfigs[index]
            let bridge = WireProxyBridge()

            do {
                try await bridge.connect(config: config)
            } catch {
                throw NetworkError.tunnelSetupFailed(error.localizedDescription)
            }

            wireProxyBridges.append(bridge)

            activeProxy = ActiveProxy(
                mode: .nord,
                displayIP: config.endpoint,
                host: "127.0.0.1",
                port: bridge.localSOCKSPort,
                connectedSince: Date(),
                index: index,
                totalCount: generatedWireGuardConfigs.count
            )
            statusMessage = "Connected via Nord WireGuard (\(config.serverName ?? config.endpoint))"
        }
    }

    // MARK: - Private: Failover

    private func failoverToNextMode() async {
        failoverAttempts += 1
        guard failoverAttempts <= maxFailoverAttempts else {
            connectionStatus = .error
            statusMessage = "All failover attempts exhausted"
            failoverAttempts = 0
            return
        }

        connectionStatus = .failingOver
        statusMessage = "Failing over (attempt \(failoverAttempts)/\(maxFailoverAttempts))..."

        let currentMode = activeProxy?.mode

        do {
            if currentMode == .socks5 && !settings.nordConfig.accessKey.isEmpty {
                for bridge in wireProxyBridges { bridge.disconnect() }
                wireProxyBridges.removeAll()
                currentIndex = 0
                try await connectNord()
            } else if currentMode == .nord && !parsedSOCKS5Proxies.isEmpty {
                for bridge in wireProxyBridges { bridge.disconnect() }
                wireProxyBridges.removeAll()
                currentIndex = 0
                try await connectSOCKS5()
            } else if !parsedSOCKS5Proxies.isEmpty {
                currentIndex = 0
                try await connectSOCKS5()
            } else if !settings.nordConfig.accessKey.isEmpty {
                currentIndex = 0
                try await connectNord()
            } else {
                throw NetworkError.noProxiesConfigured
            }

            connectionStatus = .connected
            failoverAttempts = 0
            startRotationTimer()
        } catch {
            connectionStatus = .error
            statusMessage = "Failover failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Private: Nord Config Generation

    private func generateNordConfigs() async throws {
        let keyPair = nordKeyStore.generateKeyPairIfNeeded()

        let servers = try await nordService.fetchRecommendedServers(
            count: settings.nordConfig.ipCount.rawValue,
            accessKey: settings.nordConfig.accessKey
        )

        guard !servers.isEmpty else {
            throw NetworkError.noNordServersAvailable
        }

        generatedWireGuardConfigs = servers.compactMap { server in
            try? nordConfigGenerator.generateConfig(server: server, privateKey: keyPair.privateKey)
        }

        statusMessage = "Generated \(generatedWireGuardConfigs.count) Nord WireGuard configs"
    }

    // MARK: - Private: Rotation Timer

    private func startRotationTimer() {
        let interval = settings.rotationIntervalSeconds
        guard interval > 0 else { return }

        rotationTask?.cancel()
        rotationTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { break }
                await self?.rotateToNextProxy()
            }
        }
    }

    // MARK: - Private: Persistence

    private func persistSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: settingsKey)
    }

    private static func loadPersistedSettings() -> NetworkSettings {
        guard let data = UserDefaults.standard.data(forKey: "SimpleNetworkManager.settings"),
              let decoded = try? JSONDecoder().decode(NetworkSettings.self, from: data) else {
            return .default
        }
        return decoded
    }
}
