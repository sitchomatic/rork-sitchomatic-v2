import SwiftUI

struct SimpleNetworkSettingsView: View {
    @State private var networkManager = SimpleNetworkManager.shared
    @State private var socks5Text: String = ""
    @State private var nordAccessKey: String = ""
    @State private var showingNordKeyField: Bool = false

    private let darkBg = Color(red: 0.06, green: 0.06, blue: 0.08)
    private let cardBg = Color.white.opacity(0.05)
    private let borderColor = Color.white.opacity(0.06)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                connectionCard
                modeSelector
                configurationCards
                advancedCard
                tunnelDiagnosticsCard
                actionButtons
                Color.clear.frame(height: 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(darkBg)
        .navigationTitle("Network")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            socks5Text = networkManager.settings.socks5RawList
            nordAccessKey = networkManager.settings.nordConfig.accessKey
        }
    }

    // MARK: - Connection Status Card

    @ViewBuilder
    private var connectionCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(statusGradient)
                    .frame(width: 44, height: 44)
                    .shadow(color: statusGlowColor.opacity(0.4), radius: 8)

                Image(systemName: networkManager.connectionStatus.iconName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, isActive: networkManager.connectionStatus == .connecting || networkManager.connectionStatus == .rotating)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(networkManager.quickStatusLine)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(networkManager.statusMessage)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }

            Spacer()

            Button {
                Task {
                    if networkManager.connectionStatus.isActive {
                        networkManager.disconnect()
                    } else {
                        await networkManager.connect()
                    }
                }
            } label: {
                Text(networkManager.connectionStatus.isActive ? "STOP" : "CONNECT")
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(
                        networkManager.connectionStatus.isActive
                        ? LinearGradient(colors: [.red, .red.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [.purple, .purple.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                    )
                    .clipShape(.capsule)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(cardBg)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    // MARK: - Mode Selector

    @ViewBuilder
    private var modeSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MODE")
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white.opacity(0.3))
                .tracking(2)
                .padding(.leading, 4)

            HStack(spacing: 8) {
                ForEach(NetworkMode.allCases, id: \.self) { mode in
                    Button {
                        networkManager.updateMode(mode)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: mode.iconName)
                                .font(.system(size: 18, weight: .semibold))
                            Text(mode.displayName)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .textCase(.uppercase)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(networkManager.settings.mode == mode ? .white : .white.opacity(0.3))
                        .background(
                            networkManager.settings.mode == mode
                            ? modeColor(mode).opacity(0.2)
                            : Color.white.opacity(0.03)
                        )
                        .clipShape(.rect(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(
                                    networkManager.settings.mode == mode ? modeColor(mode).opacity(0.5) : borderColor,
                                    lineWidth: networkManager.settings.mode == mode ? 1.5 : 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Configuration Cards

    @ViewBuilder
    private var configurationCards: some View {
        let mode = networkManager.settings.mode

        if mode == .socks5 || mode == .hybrid {
            darkCard("SOCKS5 PROXIES", icon: "network", iconColor: .orange) {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $socks5Text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.green.opacity(0.9))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 80)
                        .padding(10)
                        .background(Color.black.opacity(0.4))
                        .clipShape(.rect(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.green.opacity(0.15), lineWidth: 1)
                        )

                    HStack {
                        Text("ip:port or user:pass@ip:port")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.2))

                        Spacer()

                        if !networkManager.resolvedProxies.filter({ $0.source == .socks5 }).isEmpty {
                            let ct = networkManager.resolvedProxies.filter { $0.source == .socks5 }.count
                            Text("\(ct) LOADED")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(.green)
                        }

                        Button {
                            networkManager.updateSOCKS5List(socks5Text)
                        } label: {
                            Text("APPLY")
                                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                                .background(Color.orange.opacity(0.15))
                                .clipShape(.capsule)
                        }
                        .disabled(socks5Text == networkManager.settings.socks5RawList)
                    }
                }
            }
        }

        if mode == .nord || mode == .hybrid {
            darkCard("NORD VPN", icon: "shield.checkered", iconColor: .blue) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "key.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.blue)
                        Text("Access Key")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        if !nordAccessKey.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.green)
                        }
                    }

                    if showingNordKeyField || nordAccessKey.isEmpty {
                        SecureField("Paste Nord access key...", text: $nordAccessKey)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Color.black.opacity(0.4))
                            .clipShape(.rect(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Color.blue.opacity(0.15), lineWidth: 1)
                            )
                            .onSubmit {
                                Task {
                                    try? await networkManager.updateNordAccessKey(nordAccessKey)
                                    showingNordKeyField = false
                                }
                            }
                    } else {
                        Button {
                            showingNordKeyField = true
                        } label: {
                            HStack {
                                Text(String(repeating: "*", count: 24))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.2))
                                Spacer()
                                Text("CHANGE")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.blue)
                            }
                            .padding(10)
                            .background(Color.black.opacity(0.3))
                            .clipShape(.rect(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("IP COUNT")
                                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.25))
                                .tracking(1)
                            Picker("", selection: Binding(
                                get: { networkManager.settings.nordConfig.ipCount },
                                set: { newValue in Task { try? await networkManager.updateNordIPCount(newValue) } }
                            )) {
                                ForEach(NordIPCount.allCases, id: \.self) { count in
                                    Text(count.displayName).tag(count)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }

                    HStack {
                        Text("PROTOCOL")
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.25))
                            .tracking(1)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.blue)
                            Text("WireGuard")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Advanced Card

    @ViewBuilder
    private var advancedCard: some View {
        darkCard("ADVANCED", icon: "slider.horizontal.3", iconColor: .white.opacity(0.5)) {
            VStack(spacing: 0) {
                HStack {
                    Text("IP Assignment")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Picker("", selection: Binding(
                        get: { networkManager.settings.ipAssignment },
                        set: { networkManager.updateIPAssignment($0) }
                    )) {
                        ForEach(IPAssignmentMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(.purple)
                }
                .padding(.vertical, 8)

                Divider().background(Color.white.opacity(0.06))

                HStack {
                    Text("Rotation")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text("\(networkManager.settings.rotationIntervalSeconds / 60) min")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.purple)
                    Stepper("", value: Binding(
                        get: { networkManager.settings.rotationIntervalSeconds / 60 },
                        set: { networkManager.updateRotationInterval($0 * 60) }
                    ), in: 1...60)
                    .labelsHidden()
                    .frame(width: 94)
                }
                .padding(.vertical, 6)

                if networkManager.settings.mode == .hybrid {
                    Divider().background(Color.white.opacity(0.06))
                    HStack {
                        Text("Auto Failover")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.6))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { networkManager.settings.hybridFailoverEnabled },
                            set: { networkManager.updateHybridFailover($0) }
                        ))
                        .labelsHidden()
                        .tint(.purple)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    // MARK: - Tunnel Diagnostics Card

    @ViewBuilder
    private var tunnelDiagnosticsCard: some View {
        let bridges = networkManager.wireProxyBridges.filter { $0.isConnected }
        if !bridges.isEmpty {
            darkCard("WIREPROXY TUNNELS", icon: "lock.shield.fill", iconColor: .cyan) {
                VStack(spacing: 0) {
                    ForEach(Array(bridges.enumerated()), id: \.offset) { index, bridge in
                        if index > 0 {
                            Divider().background(Color.white.opacity(0.06))
                        }
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bridge.connectedEndpoint)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.8))
                                HStack(spacing: 8) {
                                    Text("localhost:\(bridge.localSOCKSPort)")
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.cyan.opacity(0.6))
                                    Text(bridge.uptimeString)
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.25))
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(bridge.trafficSummary)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.green.opacity(0.6))
                                Text("\(bridge.activeConnectionCount) conn")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.25))
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        if networkManager.connectionStatus.isActive {
            HStack(spacing: 10) {
                Button {
                    Task { await networkManager.rotateToNextProxy() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 11, weight: .bold))
                        Text("ROTATE")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .tracking(1)
                    }
                    .foregroundStyle(.purple)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.purple.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.purple.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button {
                    networkManager.disconnect()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 11, weight: .bold))
                        Text("DISCONNECT")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .tracking(1)
                    }
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Dark Card Helper

    @ViewBuilder
    private func darkCard<Content: View>(_ title: String, icon: String, iconColor: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(2)
            }

            content()
        }
        .padding(16)
        .background(cardBg)
        .clipShape(.rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    // MARK: - Helpers

    private var statusGradient: LinearGradient {
        let colors: [Color]
        switch networkManager.connectionStatus {
        case .connected: colors = [.green, .green.opacity(0.6)]
        case .connecting, .rotating: colors = [.orange, .yellow.opacity(0.6)]
        case .failingOver: colors = [.yellow, .orange.opacity(0.6)]
        case .error: colors = [.red, .red.opacity(0.6)]
        case .disconnected: colors = [.white.opacity(0.15), .white.opacity(0.08)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var statusGlowColor: Color {
        switch networkManager.connectionStatus {
        case .connected: .green
        case .connecting, .rotating: .orange
        case .error: .red
        default: .clear
        }
    }

    private func modeColor(_ mode: NetworkMode) -> Color {
        switch mode {
        case .socks5: .orange
        case .nord: .blue
        case .hybrid: .purple
        }
    }
}
