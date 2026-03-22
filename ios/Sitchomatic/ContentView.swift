import SwiftUI

struct ContentView: View {
    @State private var selectedTab: AppTab = .command
    @State private var networkManager = SimpleNetworkManager.shared
    @State private var automationSettings = AutomationSettings.load()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TabView(selection: $selectedTab) {
                Tab(value: .command) {
                    NavigationStack {
                        CommandCenterView()
                    }
                } label: {
                    Label("Command", systemImage: "bolt.horizontal.fill")
                }

                Tab(value: .network) {
                    NavigationStack {
                        SimpleNetworkSettingsView()
                    }
                } label: {
                    Label("Network", systemImage: "network")
                }

                Tab(value: .settings) {
                    NavigationStack {
                        SettingsView(automationSettings: $automationSettings)
                    }
                } label: {
                    Label("Settings", systemImage: "gearshape.fill")
                }
            }
            .tint(Color.purple)
        }
    }
}

enum AppTab: String, Hashable {
    case command
    case network
    case settings
}

struct SettingsView: View {
    @Binding var automationSettings: AutomationSettings

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                settingsCard("Playwright Engine", icon: "bolt.fill", iconColor: .purple) {
                    VStack(spacing: 0) {
                        darkToggleRow("Use Playwright Engine", isOn: $automationSettings.playwright.usePlaywrightEngine)
                        Divider().background(Color.white.opacity(0.06))
                        darkToggleRow("Auto-Wait", isOn: $automationSettings.playwright.autoWaitEnabled)
                        Divider().background(Color.white.opacity(0.06))
                        darkToggleRow("Tracing by Default", isOn: $automationSettings.playwright.tracingEnabledByDefault)
                        Divider().background(Color.white.opacity(0.06))
                        darkStepperRow("Timeout", value: "\(Int(automationSettings.playwright.defaultTimeout))s", binding: $automationSettings.playwright.defaultTimeout, range: 5...120, step: 5)
                        Divider().background(Color.white.opacity(0.06))
                        darkStepperRow("Max Pages", value: "\(automationSettings.playwright.maxConcurrentPages)", binding: Binding(
                            get: { Double(automationSettings.playwright.maxConcurrentPages) },
                            set: { automationSettings.playwright.maxConcurrentPages = Int($0) }
                        ), range: 1...12, step: 1)
                    }
                }

                settingsCard("Stealth", icon: "eye.slash.fill", iconColor: .green) {
                    VStack(spacing: 0) {
                        darkToggleRow("Spoof WebGL", isOn: $automationSettings.stealth.spoofWebGL)
                        Divider().background(Color.white.opacity(0.06))
                        darkToggleRow("Spoof Canvas", isOn: $automationSettings.stealth.spoofCanvas)
                        Divider().background(Color.white.opacity(0.06))
                        darkToggleRow("Spoof AudioContext", isOn: $automationSettings.stealth.spoofAudioContext)
                        Divider().background(Color.white.opacity(0.06))
                        darkToggleRow("Mask WebRTC", isOn: $automationSettings.stealth.maskWebRTC)
                        Divider().background(Color.white.opacity(0.06))
                        darkToggleRow("Randomize Navigator", isOn: $automationSettings.stealth.randomizeNavigatorProperties)
                        Divider().background(Color.white.opacity(0.06))
                        darkToggleRow("Block CDP Detection", isOn: $automationSettings.stealth.blockCDPDetection)
                    }
                }

                settingsCard("Viewport", icon: "rectangle.dashed", iconColor: .cyan) {
                    VStack(spacing: 0) {
                        darkValueRow("Width", value: "\(automationSettings.viewport.width)px")
                        Divider().background(Color.white.opacity(0.06))
                        darkValueRow("Height", value: "\(automationSettings.viewport.height)px")
                        Divider().background(Color.white.opacity(0.06))
                        darkToggleRow("Mobile", isOn: $automationSettings.viewport.isMobile)
                    }
                }

                settingsCard("Screenshots", icon: "camera.fill", iconColor: .orange) {
                    VStack(spacing: 0) {
                        darkToggleRow("Capture on Navigation", isOn: $automationSettings.screenshot.captureOnNavigation)
                        Divider().background(Color.white.opacity(0.06))
                        darkToggleRow("Capture on Error", isOn: $automationSettings.screenshot.captureOnError)
                        Divider().background(Color.white.opacity(0.06))
                        darkToggleRow("Deduplication", isOn: $automationSettings.screenshot.deduplicationEnabled)
                        Divider().background(Color.white.opacity(0.06))
                        darkStepperRow("Max Stored", value: "\(automationSettings.screenshot.maxStoredScreenshots)", binding: Binding(
                            get: { Double(automationSettings.screenshot.maxStoredScreenshots) },
                            set: { automationSettings.screenshot.maxStoredScreenshots = Int($0) }
                        ), range: 10...200, step: 10)
                    }
                }

                Button {
                    automationSettings = .default
                    automationSettings.save()
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset to Defaults")
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.red.opacity(0.1))
                    .clipShape(.rect(cornerRadius: 12))
                }

                Color.clear.frame(height: 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Color(red: 0.06, green: 0.06, blue: 0.08))
        .navigationTitle("Settings")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onChange(of: automationSettings.playwright) { _, _ in automationSettings.save() }
        .onChange(of: automationSettings.stealth) { _, _ in automationSettings.save() }
        .onChange(of: automationSettings.viewport) { _, _ in automationSettings.save() }
        .onChange(of: automationSettings.screenshot) { _, _ in automationSettings.save() }
    }

    @ViewBuilder
    private func settingsCard<Content: View>(_ title: String, icon: String, iconColor: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .textCase(.uppercase)
                    .tracking(0.5)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            content()
        }
        .background(Color.white.opacity(0.05))
        .clipShape(.rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func darkToggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(.purple)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func darkValueRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.purple)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func darkStepperRow(_ label: String, value: String, binding: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.purple)
                .frame(width: 50, alignment: .trailing)
            Stepper("", value: binding, in: range, step: step)
                .labelsHidden()
                .frame(width: 94)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

#Preview {
    ContentView()
}
