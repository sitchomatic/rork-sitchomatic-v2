import Foundation
import WebKit

nonisolated enum AutomationScript: Sendable {
    case recorded([RecordedAction])
    case custom(@Sendable (PlaywrightPage) async throws -> Void)
}

nonisolated struct WaveConfig: Sendable {
    let concurrency: Int
    let delayBetweenWaves: TimeInterval
    let targetURL: String
    let script: AutomationScript
    let totalSessions: Int
    let captureScreenshots: Bool

    init(
        concurrency: Int = 3,
        delayBetweenWaves: TimeInterval = 2.0,
        targetURL: String = "",
        script: AutomationScript = .recorded([]),
        totalSessions: Int = 6,
        captureScreenshots: Bool = true
    ) {
        self.concurrency = max(1, min(concurrency, 12))
        self.delayBetweenWaves = delayBetweenWaves
        self.targetURL = targetURL
        self.script = script
        self.totalSessions = max(1, totalSessions)
        self.captureScreenshots = captureScreenshots
    }
}

nonisolated enum EngineState: String, Sendable {
    case idle
    case preparing
    case running
    case paused
    case stopping
    case completed
    case failed

    var displayName: String { rawValue.capitalized }

    var iconName: String {
        switch self {
        case .idle: "circle"
        case .preparing: "gearshape"
        case .running: "play.fill"
        case .paused: "pause.fill"
        case .stopping: "stop.fill"
        case .completed: "checkmark.seal.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    var isActive: Bool {
        self == .running || self == .paused || self == .preparing
    }
}

@Observable
@MainActor
final class ConcurrentAutomationEngine {

    private(set) var state: EngineState = .idle
    private(set) var sessions: [ConcurrentSession] = []
    private(set) var currentWave: Int = 0
    private(set) var totalWaves: Int = 0
    private(set) var startTime: Date?
    private(set) var engineLog: [SessionLogLine] = []

    private let orchestrator: PlaywrightOrchestrator
    private let networkManager: SimpleNetworkManager
    private var runTask: Task<Void, Never>?
    private var isPauseRequested: Bool = false

    var succeededCount: Int { sessions.filter { $0.phase == .succeeded }.count }
    var failedCount: Int { sessions.filter { $0.phase == .failed }.count }
    var activeCount: Int { sessions.filter { $0.phase.isActive }.count }
    var queuedCount: Int { sessions.filter { $0.phase == .queued }.count }
    var completedCount: Int { sessions.filter { $0.phase.isTerminal }.count }

    var overallProgress: Double {
        guard !sessions.isEmpty else { return 0 }
        return Double(completedCount) / Double(sessions.count)
    }

    var elapsedFormatted: String {
        guard let start = startTime else { return "0:00" }
        let elapsed = Int(Date().timeIntervalSince(start))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    static let shared = ConcurrentAutomationEngine()

    init(
        orchestrator: PlaywrightOrchestrator = .shared,
        networkManager: SimpleNetworkManager = .shared
    ) {
        self.orchestrator = orchestrator
        self.networkManager = networkManager
    }

    func startRun(config: WaveConfig) {
        guard !state.isActive else { return }

        sessions.removeAll()
        engineLog.removeAll()
        currentWave = 0
        isPauseRequested = false
        startTime = Date()

        let waveCount = Int(ceil(Double(config.totalSessions) / Double(config.concurrency)))
        totalWaves = waveCount

        for i in 0..<config.totalSessions {
            let waveIdx = i / config.concurrency
            let session = ConcurrentSession(
                index: i,
                waveIndex: waveIdx,
                targetURL: config.targetURL
            )
            sessions.append(session)
        }

        state = .preparing
        log(.phase, "Preparing \(config.totalSessions) sessions in \(waveCount) waves (concurrency: \(config.concurrency))")

        runTask = Task { [weak self] in
            await self?.executeWaves(config: config)
        }
    }

    func pause() {
        guard state == .running else { return }
        isPauseRequested = true
        state = .paused
        log(.phase, "Paused — active sessions will finish current step")
    }

    func resume() {
        guard state == .paused else { return }
        isPauseRequested = false
        state = .running
        log(.phase, "Resumed")
    }

    func stop() {
        guard state.isActive else { return }
        state = .stopping
        log(.phase, "Stopping — cancelling remaining sessions")
        runTask?.cancel()

        for session in sessions where !session.phase.isTerminal {
            session.updatePhase(.cancelled)
        }

        orchestrator.closeAllPages()
        state = .idle
        log(.result, "Run stopped")
    }

    func reset() {
        stop()
        sessions.removeAll()
        engineLog.removeAll()
        currentWave = 0
        totalWaves = 0
        startTime = nil
        state = .idle
    }

    private func executeWaves(config: WaveConfig) async {
        state = .running
        log(.phase, "Starting wave execution")

        if !orchestrator.isReady {
            do {
                try await orchestrator.startSession()
            } catch {
                state = .failed
                log(.error, "Failed to start orchestrator: \(error.localizedDescription)")
                return
            }
        }

        if networkManager.connectionStatus == .disconnected {
            log(.network, "Connecting network...")
            await networkManager.connect()
        }

        let waveCount = totalWaves
        for waveIdx in 0..<waveCount {
            guard !Task.isCancelled else { break }

            while isPauseRequested && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
            }
            guard !Task.isCancelled else { break }

            currentWave = waveIdx + 1
            let waveSessions = sessions.filter { $0.waveIndex == waveIdx }
            log(.phase, "Wave \(waveIdx + 1)/\(waveCount) — launching \(waveSessions.count) sessions")

            await withTaskGroup(of: Void.self) { group in
                for session in waveSessions {
                    group.addTask { @MainActor in
                        await self.executeSession(session, config: config)
                    }
                }
            }

            let waveSucceeded = waveSessions.filter { $0.phase == .succeeded }.count
            let waveFailed = waveSessions.filter { $0.phase == .failed }.count
            log(.result, "Wave \(waveIdx + 1) complete — \(waveSucceeded) succeeded, \(waveFailed) failed")

            if waveIdx < waveCount - 1 && !Task.isCancelled {
                log(.phase, "Waiting \(Int(config.delayBetweenWaves))s before next wave")
                try? await Task.sleep(for: .seconds(config.delayBetweenWaves))
            }
        }

        if !Task.isCancelled {
            state = .completed
            log(.result, "Run complete — \(succeededCount)/\(sessions.count) succeeded, \(failedCount) failed")
        }
    }

    private func executeSession(_ session: ConcurrentSession, config: WaveConfig) async {
        session.updatePhase(.launching)

        let proxyEndpoint = networkManager.proxyEndpoint(forSessionID: "session-\(session.index)")
        if let ep = proxyEndpoint {
            session.updateProxy("\(ep.host):\(ep.port)")
        } else {
            session.updateProxy("Direct")
        }

        session.log(.network, "Proxy: \(session.proxyInfo)")

        let page: PlaywrightPage
        do {
            page = try await orchestrator.newPage()
            session.attachPage(page)
        } catch {
            session.setError("Failed to create page: \(error.localizedDescription)")
            session.updatePhase(.failed)
            return
        }

        do {
            switch config.script {
            case .recorded(let actions):
                try await executeRecordedActions(actions, on: page, session: session, config: config)
            case .custom(let block):
                session.updatePhase(.running)
                try await block(page)
                session.updatePhase(.succeeded)
            }
        } catch is CancellationError {
            session.updatePhase(.cancelled)
        } catch {
            session.setError(error.localizedDescription)
            session.updatePhase(.failed)

            if config.captureScreenshots {
                session.updatePhase(session.phase == .failed ? .failed : .screenshotting)
                if let screenshot = try? await page.screenshot() {
                    session.setScreenshot(screenshot)
                }
            }
        }

        page.close()
    }

    private func executeRecordedActions(
        _ actions: [RecordedAction],
        on page: PlaywrightPage,
        session: ConcurrentSession,
        config: WaveConfig
    ) async throws {
        session.updateProgress(completed: 0, total: actions.count)

        for (index, action) in actions.enumerated() {
            guard !Task.isCancelled else { throw CancellationError() }

            while isPauseRequested && !Task.isCancelled {
                try await Task.sleep(for: .milliseconds(200))
            }

            switch action.kind {
            case .navigation:
                session.updatePhase(.navigating)
                if let url = action.value {
                    session.updateURL(url)
                    session.log(.action, "goto(\(url))")
                    try await page.goto(url)
                }

            case .click:
                session.updatePhase(.running)
                if let selector = action.selector {
                    session.log(.action, "click(\(selector))")
                    try await page.locator(selector).click()
                }

            case .fill:
                session.updatePhase(.fillingForm)
                if let selector = action.selector, let value = action.value {
                    session.log(.action, "fill(\(selector), \(String(value.prefix(20))))")
                    try await page.locator(selector).fill(value)
                }

            case .check:
                session.updatePhase(.running)
                if let selector = action.selector {
                    session.log(.action, "check(\(selector))")
                    try await page.locator(selector).check()
                }

            case .uncheck:
                session.updatePhase(.running)
                if let selector = action.selector {
                    session.log(.action, "uncheck(\(selector))")
                    try await page.locator(selector).uncheck()
                }

            case .select:
                session.updatePhase(.running)
                if let selector = action.selector, let value = action.value {
                    session.log(.action, "select(\(selector), \(value))")
                    try await page.locator(selector).selectOption(value)
                }

            case .pressEnter:
                session.updatePhase(.running)
                if let selector = action.selector {
                    session.log(.action, "press Enter on \(selector)")
                    try await page.locator(selector).type("Enter")
                }

            case .assertVisible:
                session.updatePhase(.asserting)
                if let selector = action.selector {
                    session.log(.action, "expect(\(selector)).toBeVisible()")
                    try await page.expect(page.locator(selector)).toBeVisible()
                }

            case .assertText:
                session.updatePhase(.asserting)
                if let selector = action.selector, let value = action.value {
                    session.log(.action, "expect(\(selector)).toContainText(\(value))")
                    try await page.expect(page.locator(selector)).toContainText(value)
                }

            case .assertValue:
                session.updatePhase(.asserting)
                if let selector = action.selector, let value = action.value {
                    session.log(.action, "expect(\(selector)).toHaveValue(\(value))")
                    try await page.expect(page.locator(selector)).toHaveValue(value)
                }

            case .waitForTimeout:
                session.updatePhase(.waitingForElement)
                if let ms = action.value.flatMap({ Int($0) }) {
                    session.log(.action, "wait \(ms)ms")
                    try await page.waitForTimeout(ms)
                }
            }

            session.updateProgress(completed: index + 1, total: actions.count)
            session.updateURL(page.url())

            if config.captureScreenshots && (action.kind == .navigation || index == actions.count - 1) {
                if let screenshot = try? await page.screenshot() {
                    session.setScreenshot(screenshot)
                }
            }
        }

        session.updatePhase(.succeeded)
    }

    private func log(_ category: SessionLogLine.Category, _ message: String) {
        engineLog.append(SessionLogLine(
            timestamp: Date(),
            category: category,
            message: message
        ))
    }
}
