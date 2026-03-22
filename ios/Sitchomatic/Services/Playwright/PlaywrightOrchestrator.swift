import Foundation
import WebKit
import Network

@Observable
@MainActor
final class PlaywrightOrchestrator {

    private(set) var pages: [PlaywrightPage] = []
    private(set) var isReady: Bool = false
    private(set) var statusMessage: String = "Idle"
    private(set) var globalTracingEnabled: Bool = false
    private(set) var sessionLog: [SessionLogEntry] = []

    private let networkManager: SimpleNetworkManager
    private let defaultViewportSize: CGSize = CGSize(width: 390, height: 844)
    private let maxConcurrentPages: Int = 6
    private var sessionStartTime: Date?
    private var pageCounter: Int = 0

    static let shared = PlaywrightOrchestrator()

    init(networkManager: SimpleNetworkManager = .shared) {
        self.networkManager = networkManager
    }

    // MARK: - Session Lifecycle

    func startSession() async throws {
        guard !isReady else { return }
        statusMessage = "Starting session..."
        sessionStartTime = Date()
        sessionLog.removeAll()
        pages.removeAll()
        pageCounter = 0

        log(.system, "Session started")

        if networkManager.connectionStatus == .disconnected {
            statusMessage = "Connecting network..."
            await networkManager.connect()
        }

        isReady = true
        statusMessage = "Ready"
        log(.system, "Orchestrator ready — network: \(networkManager.connectionStatus.displayName)")
    }

    func endSession() {
        log(.system, "Session ending — \(pages.count) pages open")

        for page in pages {
            if page.tracingEnabled {
                _ = page.stopTracing()
            }
            page.webView.stopLoading()
            page.webView.loadHTMLString("", baseURL: nil)
        }

        pages.removeAll()
        pageCounter = 0
        isReady = false
        statusMessage = "Session ended"

        if let start = sessionStartTime {
            let duration = Date().timeIntervalSince(start)
            log(.system, "Session duration: \(String(format: "%.1f", duration))s")
        }
        sessionStartTime = nil
    }

    // MARK: - Page Management

    func newPage(viewport: CGSize? = nil) async throws -> PlaywrightPage {
        guard isReady else {
            throw PlaywrightError.pageDisposed
        }

        guard pages.count < maxConcurrentPages else {
            throw OrchestratorError.maxPagesReached(maxConcurrentPages)
        }

        let effectiveViewport = viewport ?? defaultViewportSize
        statusMessage = "Creating new page..."

        let sessionID = "page-\(pageCounter)"
        let config = ProxyConfigurationHelper.configuredWebViewConfiguration(
            forSessionID: sessionID,
            networkManager: networkManager
        )

        let webView = WKWebView(frame: CGRect(origin: .zero, size: effectiveViewport), configuration: config)
        webView.isInspectable = true
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = generateUserAgent()

        if let proxyEndpoint = networkManager.proxyEndpoint(forSessionID: sessionID) {
            log(.network, "Page \(pageCounter) routed via proxy \(proxyEndpoint.host):\(proxyEndpoint.port)")
        } else {
            log(.network, "Page \(pageCounter) using direct connection (no proxy configured)") 
        }

        let pageID = UUID()
        let page = PlaywrightPage(webView: webView, id: pageID, defaultTimeout: 30.0, orchestrator: self)

        if globalTracingEnabled {
            page.startTracing()
        }

        pages.append(page)
        pageCounter += 1
        statusMessage = "Ready — \(pages.count) page(s)"
        log(.page, "New page created (id: \(pageID.uuidString.prefix(8)), viewport: \(Int(effectiveViewport.width))×\(Int(effectiveViewport.height)))")

        return page
    }

    func closePage(_ page: PlaywrightPage) {
        if page.tracingEnabled {
            let trace = page.stopTracing()
            log(.page, "Page closed with \(trace.count) trace entries")
        }

        pages.removeAll { $0.id == page.id }
        statusMessage = pages.isEmpty ? "Ready — no pages" : "Ready — \(pages.count) page(s)"
        log(.page, "Page closed (id: \(page.id.uuidString.prefix(8)))")
    }

    func closeAllPages() {
        for page in pages {
            if page.tracingEnabled {
                _ = page.stopTracing()
            }
            page.webView.stopLoading()
            page.webView.loadHTMLString("", baseURL: nil)
        }
        pages.removeAll()
        pageCounter = 0
        statusMessage = "Ready — no pages"
        log(.page, "All pages closed")
    }

    // MARK: - Tracing

    func enableGlobalTracing() {
        globalTracingEnabled = true
        for page in pages {
            if !page.tracingEnabled {
                page.startTracing()
            }
        }
        log(.system, "Global tracing enabled")
    }

    func disableGlobalTracing() -> [[TraceEntry]] {
        globalTracingEnabled = false
        var allTraces: [[TraceEntry]] = []
        for page in pages {
            if page.tracingEnabled {
                allTraces.append(page.stopTracing())
            }
        }
        log(.system, "Global tracing disabled — collected \(allTraces.flatMap { $0 }.count) entries")
        return allTraces
    }

    // MARK: - Network Status

    var networkStatusSummary: String {
        networkManager.quickStatusLine
    }

    var activeProxyCount: Int {
        networkManager.proxyCount
    }

    var connectionStatus: ConnectionStatus {
        networkManager.connectionStatus
    }

    // MARK: - Convenience: Quick Script

    func quickRun(_ block: (PlaywrightPage) async throws -> Void) async throws {
        let wasReady = isReady
        if !wasReady {
            try await startSession()
        }

        let page = try await newPage()

        do {
            try await block(page)
        } catch {
            page.close()
            if !wasReady { endSession() }
            throw error
        }

        page.close()
        if !wasReady {
            endSession()
        }
    }

    // MARK: - Internal: User Agent

    private func generateUserAgent() -> String {
        let safariVersion = "605.1.15"
        let webkitVersion = "605.1.15"
        let osVersions = ["17_5_1", "17_6", "18_0", "18_1", "18_2"]
        let osVersion = osVersions[pageCounter % osVersions.count]
        return "Mozilla/5.0 (iPhone; CPU iPhone OS \(osVersion) like Mac OS X) AppleWebKit/\(webkitVersion) (KHTML, like Gecko) Version/\(osVersion.replacingOccurrences(of: "_", with: ".").components(separatedBy: ".").prefix(2).joined(separator: ".")) Mobile/15E148 Safari/\(safariVersion)"
    }

    // MARK: - Internal: Logging

    private func log(_ category: SessionLogCategory, _ message: String) {
        sessionLog.append(SessionLogEntry(
            timestamp: Date(),
            category: category,
            message: message
        ))
    }
}

// MARK: - Supporting Types

nonisolated enum OrchestratorError: Error, LocalizedError, Sendable {
    case maxPagesReached(Int)
    case sessionNotStarted
    case pageNotFound

    var errorDescription: String? {
        switch self {
        case .maxPagesReached(let max): "Maximum \(max) concurrent pages reached"
        case .sessionNotStarted: "Session not started — call startSession() first"
        case .pageNotFound: "Page not found in current session"
        }
    }
}

nonisolated enum SessionLogCategory: String, Sendable {
    case system
    case page
    case network
    case error
}

nonisolated struct SessionLogEntry: Sendable, Identifiable {
    let id: UUID = UUID()
    let timestamp: Date
    let category: SessionLogCategory
    let message: String

    var formatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return "[\(formatter.string(from: timestamp))] [\(category.rawValue)] \(message)"
    }
}
