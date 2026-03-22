import Foundation

@Observable
@MainActor
final class RecordingSession {

    private(set) var actions: [RecordedAction] = []
    private(set) var isRecording: Bool = false
    private(set) var isPaused: Bool = false
    private(set) var pickedLocator: String?
    private(set) var highlightedSelector: String?

    var mode: RecorderMode = .recording

    private var startTime: Date?
    private var pauseStartTime: Date?

    func startRecording() {
        actions.removeAll()
        isRecording = true
        isPaused = false
        startTime = Date()
        pauseStartTime = nil
        pickedLocator = nil
    }

    func pauseRecording() {
        isPaused = true
        pauseStartTime = Date()
    }

    func resumeRecording() {
        if let pauseStart = pauseStartTime {
            let pauseDuration = Int(Date().timeIntervalSince(pauseStart) * 1000)
            if pauseDuration >= 500 {
                let rounded = (pauseDuration / 100) * 100
                actions.append(RecordedAction(
                    kind: .waitForTimeout,
                    selector: nil,
                    value: "\(rounded)",
                    timestamp: Date()
                ))
            }
        }
        isPaused = false
        pauseStartTime = nil
    }

    func stopRecording() {
        isRecording = false
        isPaused = false
        pauseStartTime = nil
    }

    func clearActions() {
        actions.removeAll()
        pickedLocator = nil
    }

    func addAction(_ action: RecordedAction) {
        guard isRecording, !isPaused else { return }

        if action.kind == .navigation {
            if let last = actions.last, last.kind == .navigation,
               abs(last.timestamp.timeIntervalSince(action.timestamp)) < 1.0 {
                return
            }
        }

        if let last = actions.last, last.isDuplicate(of: action) { return }
        actions.append(action)
    }

    func addNavigationAction(url: String) {
        let action = RecordedAction(
            kind: .navigation,
            selector: nil,
            value: url,
            timestamp: Date()
        )
        addAction(action)
    }

    func setPickedLocator(_ selector: String) {
        pickedLocator = selector
    }

    func setHighlightedSelector(_ selector: String?) {
        highlightedSelector = selector
    }

    var generatedCode: String {
        var lines: [String] = []
        lines.append("let page = try await orchestrator.newPage()")
        lines.append("")

        var previousAction: RecordedAction?

        for (index, action) in actions.enumerated() {
            if let prev = previousAction {
                let isFormSubmit = prev.kind == .fill && action.kind == .click
                let isPressAfterFill = prev.kind == .fill && action.kind == .pressEnter
                if isFormSubmit || isPressAfterFill {
                    lines.append("// Submit form")
                }
            }

            lines.append(action.toSwiftCode())

            if action.kind == .navigation && index < actions.count - 1 {
                let next = actions[index + 1]
                if next.kind != .navigation && next.kind != .waitForTimeout {
                    lines.append("try await page.waitForLoadState(.networkIdle)")
                }
            }

            previousAction = action
        }

        return lines.joined(separator: "\n")
    }

    var actionCount: Int { actions.count }
}

nonisolated enum RecorderMode: String, Sendable, CaseIterable {
    case recording
    case pickLocator
    case assertVisibility
    case assertText

    var displayName: String {
        switch self {
        case .recording: "Record"
        case .pickLocator: "Pick Locator"
        case .assertVisibility: "Assert Visible"
        case .assertText: "Assert Text"
        }
    }

    var iconName: String {
        switch self {
        case .recording: "record.circle"
        case .pickLocator: "target"
        case .assertVisibility: "eye"
        case .assertText: "text.quote"
        }
    }
}

nonisolated struct RecordedAction: Identifiable, Sendable {
    let id: UUID = UUID()
    let kind: ActionKind
    let selector: String?
    let value: String?
    let timestamp: Date

    func isDuplicate(of other: RecordedAction) -> Bool {
        kind == other.kind && selector == other.selector && value == other.value
            && abs(timestamp.timeIntervalSince(other.timestamp)) < 0.3
    }

    func toSwiftCode() -> String {
        switch kind {
        case .navigation:
            return "try await page.goto(\"\(escapeSwift(value))\")"
        case .click:
            return "try await page.locator(\"\(escapeSwift(selector))\").click()"
        case .fill:
            return "try await page.locator(\"\(escapeSwift(selector))\").fill(\"\(escapeSwift(value))\")"
        case .check:
            return "try await page.locator(\"\(escapeSwift(selector))\").check()"
        case .uncheck:
            return "try await page.locator(\"\(escapeSwift(selector))\").uncheck()"
        case .select:
            return "try await page.locator(\"\(escapeSwift(selector))\").selectOption(\"\(escapeSwift(value))\")"
        case .pressEnter:
            return "try await page.locator(\"\(escapeSwift(selector))\").type(\"Enter\")"
        case .assertVisible:
            return "try await page.expect(page.locator(\"\(escapeSwift(selector))\")).toBeVisible()"
        case .assertText:
            return "try await page.expect(page.locator(\"\(escapeSwift(selector))\")).toContainText(\"\(escapeSwift(value))\")"
        case .assertValue:
            return "try await page.expect(page.locator(\"\(escapeSwift(selector))\")).toHaveValue(\"\(escapeSwift(value))\")"
        case .waitForTimeout:
            return "try await page.waitForTimeout(\(value ?? "1000"))"
        }
    }

    var displayDescription: String {
        switch kind {
        case .navigation: "goto(\"\(truncated(value))\")"
        case .click: "click(\"\(truncated(selector))\")"
        case .fill: "fill(\"\(truncated(selector))\", \"\(truncated(value))\")"
        case .check: "check(\"\(truncated(selector))\")"
        case .uncheck: "uncheck(\"\(truncated(selector))\")"
        case .select: "select(\"\(truncated(selector))\", \"\(truncated(value))\")"
        case .pressEnter: "press Enter on \"\(truncated(selector))\""
        case .assertVisible: "expect(\"\(truncated(selector))\").toBeVisible()"
        case .assertText: "expect(\"\(truncated(selector))\").toContainText(\"\(truncated(value))\")"
        case .assertValue: "expect(\"\(truncated(selector))\").toHaveValue(\"\(truncated(value))\")"
        case .waitForTimeout: "waitForTimeout(\(value ?? "1000")ms)"
        }
    }

    var iconName: String {
        switch kind {
        case .navigation: "globe"
        case .click: "cursorarrow.click"
        case .fill: "character.cursor.ibeam"
        case .check: "checkmark.square"
        case .uncheck: "square"
        case .select: "list.bullet"
        case .pressEnter: "return"
        case .assertVisible: "eye.fill"
        case .assertText: "text.magnifyingglass"
        case .assertValue: "equal.circle"
        case .waitForTimeout: "clock"
        }
    }

    var kindColor: String {
        switch kind {
        case .navigation: "blue"
        case .click: "purple"
        case .fill: "green"
        case .check, .uncheck: "orange"
        case .select: "cyan"
        case .pressEnter: "indigo"
        case .assertVisible, .assertText, .assertValue: "yellow"
        case .waitForTimeout: "gray"
        }
    }

    private func truncated(_ str: String?) -> String {
        guard let str else { return "" }
        return str.count > 50 ? String(str.prefix(47)) + "..." : str
    }

    private func escapeSwift(_ str: String?) -> String {
        guard let str else { return "" }
        return str
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

nonisolated enum ActionKind: String, Sendable {
    case navigation
    case click
    case fill
    case check
    case uncheck
    case select
    case pressEnter
    case assertVisible
    case assertText
    case assertValue
    case waitForTimeout
}
