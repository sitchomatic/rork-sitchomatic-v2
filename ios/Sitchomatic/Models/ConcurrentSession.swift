import Foundation
import WebKit

nonisolated enum SessionPhase: String, Sendable, CaseIterable {
    case queued
    case launching
    case navigating
    case running
    case waitingForElement
    case fillingForm
    case asserting
    case screenshotting
    case succeeded
    case failed
    case cancelled

    var isTerminal: Bool {
        self == .succeeded || self == .failed || self == .cancelled
    }

    var isActive: Bool {
        !isTerminal && self != .queued
    }

    var iconName: String {
        switch self {
        case .queued: "clock"
        case .launching: "bolt.fill"
        case .navigating: "globe"
        case .running: "play.fill"
        case .waitingForElement: "eye"
        case .fillingForm: "character.cursor.ibeam"
        case .asserting: "checkmark.shield"
        case .screenshotting: "camera.fill"
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .cancelled: "slash.circle"
        }
    }

    var displayName: String {
        switch self {
        case .queued: "Queued"
        case .launching: "Launching"
        case .navigating: "Navigating"
        case .running: "Running"
        case .waitingForElement: "Waiting"
        case .fillingForm: "Filling"
        case .asserting: "Asserting"
        case .screenshotting: "Screenshot"
        case .succeeded: "Done"
        case .failed: "Failed"
        case .cancelled: "Cancelled"
        }
    }
}

@Observable
@MainActor
final class ConcurrentSession: Identifiable {
    let id: UUID
    let index: Int
    let waveIndex: Int
    let targetURL: String

    private(set) var phase: SessionPhase = .queued
    private(set) var currentURL: String = ""
    private(set) var stepsCompleted: Int = 0
    private(set) var totalSteps: Int = 0
    private(set) var errorMessage: String?
    private(set) var startTime: Date?
    private(set) var endTime: Date?
    private(set) var lastScreenshot: Data?
    private(set) var proxyInfo: String = "Direct"
    private(set) var logEntries: [SessionLogLine] = []
    private(set) var page: PlaywrightPage?

    var elapsedTime: TimeInterval {
        guard let start = startTime else { return 0 }
        let end = endTime ?? Date()
        return end.timeIntervalSince(start)
    }

    var elapsedFormatted: String {
        let elapsed = Int(elapsedTime)
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var progress: Double {
        guard totalSteps > 0 else { return phase.isTerminal ? 1.0 : 0.0 }
        return Double(stepsCompleted) / Double(totalSteps)
    }

    init(index: Int, waveIndex: Int, targetURL: String) {
        self.id = UUID()
        self.index = index
        self.waveIndex = waveIndex
        self.targetURL = targetURL
    }

    func updatePhase(_ newPhase: SessionPhase) {
        phase = newPhase
        if newPhase.isActive && startTime == nil {
            startTime = Date()
        }
        if newPhase.isTerminal {
            endTime = Date()
        }
        log(newPhase.isTerminal ? .result : .phase, newPhase.displayName)
    }

    func updateURL(_ url: String) {
        currentURL = url
    }

    func updateProgress(completed: Int, total: Int) {
        stepsCompleted = completed
        totalSteps = total
    }

    func updateProxy(_ info: String) {
        proxyInfo = info
    }

    func setError(_ message: String) {
        errorMessage = message
        log(.error, message)
    }

    func setScreenshot(_ data: Data) {
        lastScreenshot = data
    }

    func attachPage(_ page: PlaywrightPage) {
        self.page = page
    }

    func log(_ category: SessionLogLine.Category, _ message: String) {
        logEntries.append(SessionLogLine(
            timestamp: Date(),
            category: category,
            message: message
        ))
    }
}

nonisolated struct SessionLogLine: Identifiable, Sendable {
    let id: UUID = UUID()
    let timestamp: Date
    let category: Category
    let message: String

    nonisolated enum Category: String, Sendable {
        case phase
        case action
        case network
        case error
        case result

        var color: String {
            switch self {
            case .phase: "purple"
            case .action: "cyan"
            case .network: "blue"
            case .error: "red"
            case .result: "green"
            }
        }
    }

    var formatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return "[\(formatter.string(from: timestamp))] \(message)"
    }
}
