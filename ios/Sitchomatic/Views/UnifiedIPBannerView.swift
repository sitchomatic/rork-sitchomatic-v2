import SwiftUI

struct UnifiedIPBannerView: View {
    @State private var networkManager = SimpleNetworkManager.shared
    @State private var showingNetworkSettings: Bool = false

    var body: some View {
        Button {
            showingNetworkSettings = true
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(statusGradient)
                        .frame(width: 28, height: 28)
                        .shadow(color: glowColor.opacity(0.4), radius: 6)

                    Image(systemName: networkManager.connectionStatus.iconName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .symbolEffect(.pulse, isActive: networkManager.connectionStatus == .connecting || networkManager.connectionStatus == .rotating)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(networkManager.settings.mode.displayName)
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.9))
                        .textCase(.uppercase)
                        .tracking(0.5)

                    if let active = networkManager.activeProxy {
                        Text(active.displayIP)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.green.opacity(0.8))
                            .lineLimit(1)
                    } else {
                        Text(networkManager.connectionStatus.displayName)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.25))
                    }
                }

                Spacer()

                if networkManager.connectionStatus.isActive {
                    if let active = networkManager.activeProxy {
                        Text("\(active.index + 1)/\(active.totalCount)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15))
                            .clipShape(.capsule)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.15))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.05))
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingNetworkSettings) {
            NavigationStack {
                SimpleNetworkSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showingNetworkSettings = false
                            } label: {
                                Text("Done")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.purple)
                            }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationContentInteraction(.scrolls)
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
    }

    private var statusGradient: LinearGradient {
        let colors: [Color]
        switch networkManager.connectionStatus {
        case .connected: colors = [.green, .green.opacity(0.5)]
        case .connecting, .rotating: colors = [.orange, .yellow.opacity(0.5)]
        case .failingOver: colors = [.yellow, .orange.opacity(0.5)]
        case .error: colors = [.red, .red.opacity(0.5)]
        case .disconnected: colors = [.white.opacity(0.12), .white.opacity(0.06)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var glowColor: Color {
        switch networkManager.connectionStatus {
        case .connected: .green
        case .connecting, .rotating: .orange
        case .error: .red
        default: .clear
        }
    }
}

struct CompactIPBannerView: View {
    @State private var networkManager = SimpleNetworkManager.shared

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(networkManager.connectionStatus.isActive ? Color.green : Color.white.opacity(0.15))
                .frame(width: 5, height: 5)
                .shadow(color: networkManager.connectionStatus.isActive ? .green.opacity(0.5) : .clear, radius: 3)

            Text(networkManager.quickStatusLine)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
                .lineLimit(1)
        }
    }
}
