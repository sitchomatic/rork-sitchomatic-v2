import Foundation
import Network

@Observable
@MainActor
final class WireProxyBridge {
    private(set) var isConnected: Bool = false
    private(set) var localSOCKSPort: Int = 0
    private(set) var connectedEndpoint: String = ""
    private(set) var bytesSent: UInt64 = 0
    private(set) var bytesReceived: UInt64 = 0
    private(set) var connectedSince: Date?
    private(set) var activeConnectionCount: Int = 0

    private var listener: NWListener?
    private var activeConfig: WireGuardConfig?
    private var activeConnections: [NWConnection] = []
    private static var allocatedPorts: Set<Int> = []
    private static let portRange = 10080...60000

    func connect(config: WireGuardConfig) async throws {
        guard !isConnected else { return }

        activeConfig = config
        let port = Self.allocatePort()
        guard port > 0 else {
            throw WireProxyError.portAllocationFailed
        }

        do {
            let nwPort = NWEndpoint.Port(rawValue: UInt16(port))!
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let newListener = try NWListener(using: params, on: nwPort)

            newListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .failed(let error):
                        self?.handleListenerFailure(error)
                    case .cancelled:
                        self?.handleDisconnect()
                    default:
                        break
                    }
                }
            }

            newListener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleIncomingSOCKS5Connection(connection)
                }
            }

            newListener.start(queue: .global(qos: .userInitiated))

            try await Task.sleep(for: .milliseconds(100))

            guard newListener.state != .cancelled else {
                Self.releasePort(port)
                throw WireProxyError.connectionFailed("Listener failed to start")
            }

            listener = newListener
            localSOCKSPort = port
            isConnected = true
            connectedEndpoint = config.endpoint
            connectedSince = Date()
            bytesSent = 0
            bytesReceived = 0
            activeConnectionCount = 0
        } catch let error as WireProxyError {
            Self.releasePort(port)
            throw error
        } catch {
            Self.releasePort(port)
            throw WireProxyError.connectionFailed(error.localizedDescription)
        }
    }

    func disconnect() {
        listener?.cancel()
        listener = nil

        for connection in activeConnections {
            connection.cancel()
        }
        activeConnections.removeAll()

        if localSOCKSPort > 0 {
            Self.releasePort(localSOCKSPort)
        }

        handleDisconnect()
    }

    var uptimeString: String {
        guard let since = connectedSince else { return "--" }
        let elapsed = Int(Date().timeIntervalSince(since))
        let hours = elapsed / 3600
        let minutes = (elapsed % 3600) / 60
        let seconds = elapsed % 60
        if hours > 0 {
            return String(format: "%dh %02dm %02ds", hours, minutes, seconds)
        }
        return String(format: "%dm %02ds", minutes, seconds)
    }

    var configINI: String? {
        guard let config = activeConfig else { return nil }
        return NordLynxConfigGeneratorService.shared.generateINIString(from: config)
    }

    var trafficSummary: String {
        let sent = formatBytes(bytesSent)
        let received = formatBytes(bytesReceived)
        return "\(sent) ↑ / \(received) ↓"
    }

    // MARK: - Private

    private func handleDisconnect() {
        isConnected = false
        localSOCKSPort = 0
        connectedEndpoint = ""
        connectedSince = nil
        activeConfig = nil
        activeConnectionCount = 0
    }

    private func handleListenerFailure(_ error: NWError) {
        disconnect()
    }

    private func handleIncomingSOCKS5Connection(_ connection: NWConnection) {
        activeConnections.append(connection)
        activeConnectionCount = activeConnections.count

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .cancelled, .failed:
                    self?.removeConnection(connection)
                default:
                    break
                }
            }
        }

        connection.start(queue: .global(qos: .userInitiated))
        performSOCKS5Handshake(connection)
    }

    private func performSOCKS5Handshake(_ clientConnection: NWConnection) {
        clientConnection.receive(minimumIncompleteLength: 3, maximumLength: 257) { [weak self] data, _, _, error in
            Task { @MainActor in
                guard let self, let data, data.count >= 3 else {
                    clientConnection.cancel()
                    return
                }

                guard data[0] == 0x05 else {
                    clientConnection.cancel()
                    return
                }

                let authResponse = Data([0x05, 0x00])
                clientConnection.send(content: authResponse, completion: .contentProcessed { _ in })

                self.receiveSOCKS5ConnectRequest(clientConnection)
            }
        }
    }

    private func receiveSOCKS5ConnectRequest(_ clientConnection: NWConnection) {
        clientConnection.receive(minimumIncompleteLength: 4, maximumLength: 512) { [weak self] data, _, _, error in
            Task { @MainActor in
                guard let self, let data, data.count >= 7 else {
                    clientConnection.cancel()
                    return
                }

                guard data[0] == 0x05, data[1] == 0x01 else {
                    let failResponse = Data([0x05, 0x07, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
                    clientConnection.send(content: failResponse, completion: .contentProcessed { _ in
                        clientConnection.cancel()
                    })
                    return
                }

                var targetHost: String?
                var targetPort: UInt16 = 0
                var consumed = 4

                switch data[3] {
                case 0x01:
                    guard data.count >= 10 else { clientConnection.cancel(); return }
                    let ip = "\(data[4]).\(data[5]).\(data[6]).\(data[7])"
                    targetHost = ip
                    targetPort = UInt16(data[8]) << 8 | UInt16(data[9])
                    consumed = 10

                case 0x03:
                    let domainLen = Int(data[4])
                    guard data.count >= 5 + domainLen + 2 else { clientConnection.cancel(); return }
                    let domainData = data[5..<(5 + domainLen)]
                    targetHost = String(data: Data(domainData), encoding: .utf8)
                    let portOffset = 5 + domainLen
                    targetPort = UInt16(data[portOffset]) << 8 | UInt16(data[portOffset + 1])
                    consumed = portOffset + 2

                case 0x04:
                    guard data.count >= 22 else { clientConnection.cancel(); return }
                    var parts: [String] = []
                    for i in stride(from: 4, to: 20, by: 2) {
                        let segment = String(format: "%02x%02x", data[i], data[i+1])
                        parts.append(segment)
                    }
                    targetHost = parts.joined(separator: ":")
                    targetPort = UInt16(data[20]) << 8 | UInt16(data[21])
                    consumed = 22

                default:
                    clientConnection.cancel()
                    return
                }

                guard let host = targetHost, targetPort > 0 else {
                    clientConnection.cancel()
                    return
                }

                self.connectToRemoteAndRelay(
                    clientConnection: clientConnection,
                    targetHost: host,
                    targetPort: targetPort
                )
            }
        }
    }

    private func connectToRemoteAndRelay(
        clientConnection: NWConnection,
        targetHost: String,
        targetPort: UInt16
    ) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(targetHost),
            port: NWEndpoint.Port(rawValue: targetPort)!
        )

        let remoteConnection = NWConnection(to: endpoint, using: .tcp)

        remoteConnection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    let successResponse = Data([0x05, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
                    clientConnection.send(content: successResponse, completion: .contentProcessed { _ in })

                    self?.relay(from: clientConnection, to: remoteConnection, direction: .upload)
                    self?.relay(from: remoteConnection, to: clientConnection, direction: .download)

                case .failed, .cancelled:
                    let failResponse = Data([0x05, 0x05, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
                    clientConnection.send(content: failResponse, completion: .contentProcessed { _ in
                        clientConnection.cancel()
                    })

                default:
                    break
                }
            }
        }

        remoteConnection.start(queue: .global(qos: .userInitiated))
        activeConnections.append(remoteConnection)
    }

    private enum RelayDirection {
        case upload
        case download
    }

    private func relay(from source: NWConnection, to destination: NWConnection, direction: RelayDirection) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                if let data, !data.isEmpty {
                    switch direction {
                    case .upload:
                        self?.bytesSent += UInt64(data.count)
                    case .download:
                        self?.bytesReceived += UInt64(data.count)
                    }

                    destination.send(content: data, completion: .contentProcessed { sendError in
                        if sendError != nil {
                            source.cancel()
                            destination.cancel()
                            return
                        }

                        if !isComplete {
                            Task { @MainActor in
                                self?.relay(from: source, to: destination, direction: direction)
                            }
                        }
                    })
                }

                if isComplete || error != nil {
                    destination.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
                        destination.cancel()
                    })
                    source.cancel()
                }
            }
        }
    }

    private func removeConnection(_ connection: NWConnection) {
        activeConnections.removeAll { $0 === connection }
        activeConnectionCount = activeConnections.count
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024.0
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024.0
        return String(format: "%.1f MB", mb)
    }

    private static func allocatePort() -> Int {
        for _ in 0..<100 {
            let candidate = Int.random(in: portRange)
            if !allocatedPorts.contains(candidate) {
                allocatedPorts.insert(candidate)
                return candidate
            }
        }
        return 0
    }

    private static func releasePort(_ port: Int) {
        allocatedPorts.remove(port)
    }
}

nonisolated enum WireProxyError: Error, LocalizedError, Sendable {
    case portAllocationFailed
    case connectionFailed(String)
    case tunnelNotRunning
    case configurationMissing

    var errorDescription: String? {
        switch self {
        case .portAllocationFailed:
            "Failed to allocate a local SOCKS5 port"
        case .connectionFailed(let detail):
            "WireProxy connection failed: \(detail)"
        case .tunnelNotRunning:
            "WireGuard tunnel is not running"
        case .configurationMissing:
            "WireGuard configuration is missing"
        }
    }
}
