import SwiftUI

struct CommandCenterView: View {
    @State private var engine = ConcurrentAutomationEngine.shared
    @State private var networkManager = SimpleNetworkManager.shared
    @State private var orchestrator = PlaywrightOrchestrator.shared

    @State private var targetURL: String = "https://example.com"
    @State private var sessionCount: Int = 6
    @State private var concurrency: Int = 3
    @State private var waveDelay: Double = 2.0
    @State private var expandedSessionID: UUID?
    @State private var showingLog: Bool = false
    @State private var showingConfig: Bool = false
    @State private var showingCodegen: Bool = false
    @State private var viewMode: SessionViewMode = .grid

    private let darkBg = Color(red: 0.06, green: 0.06, blue: 0.08)
    private let cardBg = Color.white.opacity(0.05)
    private let borderColor = Color.white.opacity(0.06)

    var body: some View {
        VStack(spacing: 0) {
            statusStrip
            ScrollView {
                VStack(spacing: 14) {
                    statsRow
                    if !engine.state.isActive && engine.state != .completed {
                        configPanel
                    }
                    controlBar
                    if !engine.sessions.isEmpty {
                        waveProgressBar
                        sessionGrid
                    } else {
                        emptyState
                    }
                    Color.clear.frame(height: 20)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .background(darkBg)
        .navigationTitle("Command Center")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        showingCodegen = true
                    } label: {
                        Image(systemName: "curlybraces")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.purple)
                    }

                    Button {
                        showingLog = true
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.purple)
                    }

                    Menu {
                        Button {
                            viewMode = viewMode == .grid ? .list : .grid
                        } label: {
                            Label(
                                viewMode == .grid ? "List View" : "Grid View",
                                systemImage: viewMode == .grid ? "list.bullet" : "square.grid.2x2"
                            )
                        }

                        Divider()

                        Button(role: .destructive) {
                            engine.reset()
                        } label: {
                            Label("Reset All", systemImage: "trash")
                        }
                        .disabled(engine.state.isActive)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.purple)
                    }
                }
            }
        }
        .sheet(isPresented: $showingLog) {
            engineLogSheet
        }
        .fullScreenCover(isPresented: $showingCodegen) {
            NavigationStack {
                PlaywrightStudioView()
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                showingCodegen = false
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "chevron.left")
                                        .font(.system(size: 12, weight: .semibold))
                                    Text("Command")
                                        .font(.system(size: 14, weight: .medium))
                                }
                                .foregroundStyle(.purple)
                            }
                        }
                    }
            }
        }
        .safeAreaInset(edge: .top) {
            UnifiedIPBannerView()
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
        }
    }

    // MARK: - Status Strip

    @ViewBuilder
    private var statusStrip: some View {
        HStack(spacing: 8) {
            Image(systemName: engine.state.iconName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(engineStateColor)
                .symbolEffect(.pulse, isActive: engine.state == .running)

            Text(engine.state.displayName.uppercased())
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundStyle(engineStateColor)
                .tracking(1.5)

            Spacer()

            if engine.state.isActive {
                Text(engine.elapsedFormatted)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }

            if engine.totalWaves > 0 {
                Text("WAVE \(engine.currentWave)/\(engine.totalWaves)")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.purple.opacity(0.7))
                    .tracking(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(engineStateColor.opacity(0.05))
        .overlay(alignment: .bottom) {
            Rectangle().fill(borderColor).frame(height: 1)
        }
    }

    // MARK: - Stats Row

    @ViewBuilder
    private var statsRow: some View {
        HStack(spacing: 8) {
            statPill("Active", value: "\(engine.activeCount)", color: .purple, icon: "bolt.fill")
            statPill("Done", value: "\(engine.succeededCount)", color: .green, icon: "checkmark")
            statPill("Failed", value: "\(engine.failedCount)", color: .red, icon: "xmark")
            statPill("Queue", value: "\(engine.queuedCount)", color: .white.opacity(0.3), icon: "clock")
        }
    }

    @ViewBuilder
    private func statPill(_ label: String, value: String, color: Color, icon: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
                Text(value)
                    .font(.system(size: 16, weight: .heavy, design: .monospaced))
            }
            .foregroundStyle(color)

            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
                .textCase(.uppercase)
                .tracking(0.5)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.06))
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(color.opacity(0.12), lineWidth: 1)
        )
    }

    // MARK: - Config Panel

    @ViewBuilder
    private var configPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.purple)
                Text("RUN CONFIG")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(2)
            }

            HStack(spacing: 8) {
                Image(systemName: "globe")
                    .font(.system(size: 11))
                    .foregroundStyle(.blue.opacity(0.5))

                TextField("Target URL...", text: $targetURL)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.4))
            .clipShape(.rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.blue.opacity(0.12), lineWidth: 1)
            )

            HStack(spacing: 16) {
                configField("Sessions", value: "\(sessionCount)", binding: $sessionCount, range: 1...50)
                configField("Concurrency", value: "\(concurrency)", binding: $concurrency, range: 1...12)
            }

            HStack {
                Text("WAVE DELAY")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.25))
                    .tracking(1)
                Spacer()
                Text("\(String(format: "%.1f", waveDelay))s")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.purple)
                Stepper("", value: $waveDelay, in: 0.5...30.0, step: 0.5)
                    .labelsHidden()
                    .frame(width: 94)
            }
        }
        .padding(16)
        .background(cardBg)
        .clipShape(.rect(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func configField(_ label: String, value: String, binding: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white.opacity(0.25))
                .tracking(1)

            HStack {
                Text(value)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(.purple)

                Spacer()

                Stepper("", value: binding, in: range)
                    .labelsHidden()
                    .frame(width: 94)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Control Bar

    @ViewBuilder
    private var controlBar: some View {
        HStack(spacing: 10) {
            switch engine.state {
            case .idle, .completed, .failed:
                Button {
                    launchRun()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("LAUNCH")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .tracking(1)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(
                            colors: [.purple, .purple.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .clipShape(.rect(cornerRadius: 12))
                    .shadow(color: .purple.opacity(0.3), radius: 8, y: 4)
                }
                .buttonStyle(.plain)

            case .running:
                Button {
                    engine.pause()
                } label: {
                    controlPill(icon: "pause.fill", label: "PAUSE", color: .orange)
                }
                .buttonStyle(.plain)

                Button {
                    engine.stop()
                } label: {
                    controlPill(icon: "stop.fill", label: "STOP", color: .red)
                }
                .buttonStyle(.plain)

            case .paused:
                Button {
                    engine.resume()
                } label: {
                    controlPill(icon: "play.fill", label: "RESUME", color: .green)
                }
                .buttonStyle(.plain)

                Button {
                    engine.stop()
                } label: {
                    controlPill(icon: "stop.fill", label: "STOP", color: .red)
                }
                .buttonStyle(.plain)

            case .preparing, .stopping:
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.purple)
                        .scaleEffect(0.8)
                    Text(engine.state.displayName.uppercased())
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .tracking(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(cardBg)
                .clipShape(.rect(cornerRadius: 12))
            }
        }
    }

    @ViewBuilder
    private func controlPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(label)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(1)
        }
        .foregroundStyle(color)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(color.opacity(0.1))
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(color.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Wave Progress Bar

    @ViewBuilder
    private var waveProgressBar: some View {
        VStack(spacing: 6) {
            HStack {
                Text("OVERALL PROGRESS")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
                    .tracking(1)
                Spacer()
                Text("\(Int(engine.overallProgress * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(.purple)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.04))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [.purple, .cyan],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * engine.overallProgress)
                        .animation(.spring(duration: 0.4), value: engine.overallProgress)
                }
            }
            .frame(height: 6)

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 5, height: 5)
                    Text("\(engine.succeededCount) passed")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                }
                HStack(spacing: 4) {
                    Circle().fill(.red).frame(width: 5, height: 5)
                    Text("\(engine.failedCount) failed")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                }
                Spacer()
                Text("\(engine.completedCount)/\(engine.sessions.count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(14)
        .background(cardBg)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    // MARK: - Session Grid

    @ViewBuilder
    private var sessionGrid: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("SESSIONS")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                    .tracking(2)
                Spacer()

                Button {
                    viewMode = viewMode == .grid ? .list : .grid
                } label: {
                    Image(systemName: viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.purple.opacity(0.6))
                }
            }

            switch viewMode {
            case .grid:
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    ForEach(engine.sessions) { session in
                        SessionCardView(
                            session: session,
                            isExpanded: expandedSessionID == session.id,
                            onTap: {
                                withAnimation(.spring(duration: 0.25)) {
                                    expandedSessionID = expandedSessionID == session.id ? nil : session.id
                                }
                            }
                        )
                    }
                }

            case .list:
                LazyVStack(spacing: 6) {
                    ForEach(engine.sessions) { session in
                        SessionCardView(
                            session: session,
                            isExpanded: expandedSessionID == session.id,
                            onTap: {
                                withAnimation(.spring(duration: 0.25)) {
                                    expandedSessionID = expandedSessionID == session.id ? nil : session.id
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.horizontal.circle")
                .font(.system(size: 40))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple.opacity(0.3), .cyan.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 6) {
                Text("Command Center")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                Text("Configure your run and hit Launch to start\nconcurrent Playwright sessions")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 20) {
                featureBadge(icon: "arrow.triangle.branch", label: "Waves")
                featureBadge(icon: "network", label: "Proxied")
                featureBadge(icon: "theatermasks", label: "Stealth")
            }
        }
        .padding(.vertical, 40)
    }

    @ViewBuilder
    private func featureBadge(icon: String, label: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.purple.opacity(0.4))
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.15))
                .textCase(.uppercase)
        }
    }

    // MARK: - Engine Log Sheet

    @ViewBuilder
    private var engineLogSheet: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if engine.engineLog.isEmpty {
                        Text("No log entries yet")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.2))
                            .padding(16)
                    } else {
                        ForEach(engine.engineLog) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Circle()
                                    .fill(logEntryColor(entry.category))
                                    .frame(width: 4, height: 4)
                                    .padding(.top, 5)

                                Text(entry.formatted)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(logEntryColor(entry.category).opacity(0.7))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
            .background(Color(red: 0.06, green: 0.06, blue: 0.08))
            .navigationTitle("Engine Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showingLog = false
                    }
                    .foregroundStyle(.purple)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Actions

    private func launchRun() {
        var url = targetURL
        if !url.hasPrefix("http://") && !url.hasPrefix("https://") {
            url = "https://" + url
            targetURL = url
        }

        let config = WaveConfig(
            concurrency: concurrency,
            delayBetweenWaves: waveDelay,
            targetURL: url,
            script: .recorded([
                RecordedAction(kind: .navigation, selector: nil, value: url, timestamp: Date())
            ]),
            totalSessions: sessionCount,
            captureScreenshots: true
        )

        engine.startRun(config: config)
    }

    // MARK: - Helpers

    private var engineStateColor: Color {
        switch engine.state {
        case .idle: .white.opacity(0.3)
        case .preparing: .orange
        case .running: .purple
        case .paused: .orange
        case .stopping: .red
        case .completed: .green
        case .failed: .red
        }
    }

    private func logEntryColor(_ category: SessionLogLine.Category) -> Color {
        switch category {
        case .phase: .purple
        case .action: .cyan
        case .network: .blue
        case .error: .red
        case .result: .green
        }
    }
}

private enum SessionViewMode: String {
    case grid
    case list
}
