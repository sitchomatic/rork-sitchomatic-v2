import Foundation
import WebKit

@MainActor
final class Locator {

    let selector: String

    private let page: PlaywrightPage
    private let timeout: TimeInterval
    private let pollInterval: TimeInterval = 0.15
    private let maxRetries: Int = 3
    private let parentSelector: String?
    private let nthIndex: Int?
    private let textFilter: String?

    init(
        page: PlaywrightPage,
        selector: String,
        timeout: TimeInterval = 30.0,
        parentSelector: String? = nil,
        nthIndex: Int? = nil,
        textFilter: String? = nil
    ) {
        self.page = page
        self.selector = selector
        self.timeout = timeout
        self.parentSelector = parentSelector
        self.nthIndex = nthIndex
        self.textFilter = textFilter
    }

    // MARK: - Actions

    func click(timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        page.trace(.action, "click(\(selector))")

        try await retryAction(timeout: effectiveTimeout) {
            try await self.waitForActionable(timeout: effectiveTimeout)

            let js = """
            (function() {
                \(self.resolveElementJS())
                if (!el) return JSON.stringify({error: 'not_found'});
                el.scrollIntoView({behavior: 'instant', block: 'center', inline: 'nearest'});
                var rect = el.getBoundingClientRect();
                var cx = rect.left + rect.width / 2;
                var cy = rect.top + rect.height / 2;
                var pointEl = document.elementFromPoint(cx, cy);
                if (pointEl && (pointEl === el || el.contains(pointEl) || pointEl.contains(el))) {
                    el.click();
                    return JSON.stringify({success: true});
                }
                el.click();
                return JSON.stringify({success: true});
            })()
            """

            let result: String = try await self.page.evaluate(js)
            let parsed = try self.parseActionResult(result)
            guard parsed["success"] != nil else {
                throw PlaywrightError.elementNotInteractable(self.selector)
            }
        }
    }

    func fill(_ value: String, timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        page.trace(.action, "fill(\(selector), '\(String(value.prefix(40)))')")

        try await retryAction(timeout: effectiveTimeout) {
            try await self.waitForActionable(timeout: effectiveTimeout)

            let js = """
            (function() {
                \(self.resolveElementJS())
                if (!el) return JSON.stringify({error: 'not_found'});
                el.focus();
                el.select && el.select();
                el.value = '';
                el.dispatchEvent(new Event('input', {bubbles: true}));
                el.value = '\(escaped)';
                el.dispatchEvent(new Event('input', {bubbles: true}));
                el.dispatchEvent(new Event('change', {bubbles: true}));
                el.dispatchEvent(new Event('blur', {bubbles: true}));
                return JSON.stringify({success: true});
            })()
            """

            let result: String = try await self.page.evaluate(js)
            let parsed = try self.parseActionResult(result)
            guard parsed["success"] != nil else {
                throw PlaywrightError.elementNotInteractable(self.selector)
            }
        }
    }

    func clear(timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        page.trace(.action, "clear(\(selector))")

        try await retryAction(timeout: effectiveTimeout) {
            try await self.waitForActionable(timeout: effectiveTimeout)

            let js = """
            (function() {
                \(self.resolveElementJS())
                if (!el) return JSON.stringify({error: 'not_found'});
                el.focus();
                el.select && el.select();
                el.value = '';
                el.dispatchEvent(new Event('input', {bubbles: true}));
                el.dispatchEvent(new Event('change', {bubbles: true}));
                return JSON.stringify({success: true});
            })()
            """

            let result: String = try await self.page.evaluate(js)
            _ = try self.parseActionResult(result)
        }
    }

    func type(_ text: String, delay: Int = 50, timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        page.trace(.action, "type(\(selector), '\(String(text.prefix(40)))', delay: \(delay)ms)")

        try await waitForActionable(timeout: effectiveTimeout)

        let focusJS = """
        (function() {
            \(resolveElementJS())
            if (!el) return JSON.stringify({error: 'not_found'});
            el.focus();
            return JSON.stringify({success: true});
        })()
        """

        let focusResult: String = try await page.evaluate(focusJS)
        let parsed = try parseActionResult(focusResult)
        guard parsed["success"] != nil else {
            throw PlaywrightError.elementNotInteractable(selector)
        }

        let specialKeys: [String: String] = [
            "Enter": "Enter",
            "Tab": "Tab",
            "Escape": "Escape",
            "Backspace": "Backspace",
            "Delete": "Delete",
            "ArrowLeft": "ArrowLeft",
            "ArrowRight": "ArrowRight",
            "ArrowUp": "ArrowUp",
            "ArrowDown": "ArrowDown"
        ]

        for char in text {
            let charStr = String(char)

            if let keyName = specialKeys[charStr] {
                let keyJS = """
                (function() {
                    \(resolveElementJS())
                    if (!el) return;
                    var ev = {key: '\(keyName)', code: '\(keyName)', bubbles: true, cancelable: true};
                    el.dispatchEvent(new KeyboardEvent('keydown', ev));
                    el.dispatchEvent(new KeyboardEvent('keypress', ev));
                    if ('\(keyName)' === 'Backspace') {
                        el.value = el.value.slice(0, -1);
                        el.dispatchEvent(new Event('input', {bubbles: true}));
                    } else if ('\(keyName)' === 'Enter') {
                        var form = el.closest('form');
                        if (form) form.dispatchEvent(new Event('submit', {bubbles: true, cancelable: true}));
                    }
                    el.dispatchEvent(new KeyboardEvent('keyup', ev));
                })()
                """
                try await page.evaluateVoid(keyJS)
            } else {
                let escapedChar = charStr
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "'", with: "\\'")

                let charJS = """
                (function() {
                    \(resolveElementJS())
                    if (!el) return;
                    var key = '\(escapedChar)';
                    el.dispatchEvent(new KeyboardEvent('keydown', {key: key, bubbles: true}));
                    el.dispatchEvent(new KeyboardEvent('keypress', {key: key, bubbles: true}));
                    el.value += key;
                    el.dispatchEvent(new Event('input', {bubbles: true}));
                    el.dispatchEvent(new KeyboardEvent('keyup', {key: key, bubbles: true}));
                })()
                """
                try await page.evaluateVoid(charJS)
            }
            try await Task.sleep(for: .milliseconds(delay))
        }
    }

    func pressSequentially(_ text: String, delay: Int = 50, timeout: TimeInterval? = nil) async throws {
        try await type(text, delay: delay, timeout: timeout)
    }

    func selectOption(_ value: String, timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        let escaped = value.replacingOccurrences(of: "'", with: "\\'")
        page.trace(.action, "selectOption(\(selector), '\(value)')")

        try await retryAction(timeout: effectiveTimeout) {
            try await self.waitForActionable(timeout: effectiveTimeout)

            let js = """
            (function() {
                \(self.resolveElementJS())
                if (!el || el.tagName !== 'SELECT') return JSON.stringify({error: 'not_select'});
                el.value = '\(escaped)';
                el.dispatchEvent(new Event('change', {bubbles: true}));
                el.dispatchEvent(new Event('input', {bubbles: true}));
                return JSON.stringify({success: true});
            })()
            """

            let result: String = try await self.page.evaluate(js)
            let parsed = try self.parseActionResult(result)
            guard parsed["success"] != nil else {
                throw PlaywrightError.elementNotInteractable(self.selector)
            }
        }
    }

    func check(timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        page.trace(.action, "check(\(selector))")

        try await retryAction(timeout: effectiveTimeout) {
            try await self.waitForActionable(timeout: effectiveTimeout)

            let js = """
            (function() {
                \(self.resolveElementJS())
                if (!el) return JSON.stringify({error: 'not_found'});
                if (!el.checked) {
                    el.scrollIntoView({behavior: 'instant', block: 'center'});
                    el.click();
                }
                return JSON.stringify({success: true, checked: el.checked});
            })()
            """

            let result: String = try await self.page.evaluate(js)
            _ = try self.parseActionResult(result)
        }
    }

    func uncheck(timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        page.trace(.action, "uncheck(\(selector))")

        try await retryAction(timeout: effectiveTimeout) {
            try await self.waitForActionable(timeout: effectiveTimeout)

            let js = """
            (function() {
                \(self.resolveElementJS())
                if (!el) return JSON.stringify({error: 'not_found'});
                if (el.checked) {
                    el.scrollIntoView({behavior: 'instant', block: 'center'});
                    el.click();
                }
                return JSON.stringify({success: true, checked: el.checked});
            })()
            """

            let result: String = try await self.page.evaluate(js)
            _ = try self.parseActionResult(result)
        }
    }

    func hover(timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        page.trace(.action, "hover(\(selector))")

        try await retryAction(timeout: effectiveTimeout) {
            try await self.waitForActionable(timeout: effectiveTimeout)

            let js = """
            (function() {
                \(self.resolveElementJS())
                if (!el) return JSON.stringify({error: 'not_found'});
                el.scrollIntoView({behavior: 'instant', block: 'center'});
                var rect = el.getBoundingClientRect();
                var opts = {bubbles: true, clientX: rect.left + rect.width/2, clientY: rect.top + rect.height/2};
                el.dispatchEvent(new MouseEvent('mouseover', opts));
                el.dispatchEvent(new MouseEvent('mouseenter', opts));
                el.dispatchEvent(new MouseEvent('mousemove', opts));
                return JSON.stringify({success: true});
            })()
            """

            let result: String = try await self.page.evaluate(js)
            _ = try self.parseActionResult(result)
        }
    }

    func focus(timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        page.trace(.action, "focus(\(selector))")
        try await waitForActionable(timeout: effectiveTimeout)

        let js = """
        (function() {
            \(resolveElementJS())
            if (!el) return JSON.stringify({error: 'not_found'});
            el.focus();
            return JSON.stringify({success: true});
        })()
        """

        let result: String = try await page.evaluate(js)
        _ = try parseActionResult(result)
    }

    func scrollIntoView(timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        page.trace(.action, "scrollIntoView(\(selector))")
        try await waitForAttached(timeout: effectiveTimeout)

        let js = """
        (function() {
            \(resolveElementJS())
            if (!el) return JSON.stringify({error: 'not_found'});
            el.scrollIntoView({behavior: 'smooth', block: 'center'});
            return JSON.stringify({success: true});
        })()
        """

        let result: String = try await page.evaluate(js)
        _ = try parseActionResult(result)
    }

    func dispatchEvent(_ eventType: String, timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        let escapedType = eventType.replacingOccurrences(of: "'", with: "\\'")
        page.trace(.action, "dispatchEvent(\(selector), '\(eventType)')")
        try await waitForAttached(timeout: effectiveTimeout)

        let js = """
        (function() {
            \(resolveElementJS())
            if (!el) return JSON.stringify({error: 'not_found'});
            el.dispatchEvent(new Event('\(escapedType)', {bubbles: true}));
            return JSON.stringify({success: true});
        })()
        """

        let result: String = try await page.evaluate(js)
        _ = try parseActionResult(result)
    }

    // MARK: - Wait

    func waitFor(state: LocatorState = .visible, timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? self.timeout
        page.trace(.wait, "waitFor(\(selector), state: \(state.rawValue))")

        switch state {
        case .visible:
            try await page.expect(self).toBeVisible(timeout: effectiveTimeout)
        case .hidden:
            try await page.expect(self).toBeHidden(timeout: effectiveTimeout)
        case .attached:
            try await waitForAttached(timeout: effectiveTimeout)
        }
    }

    // MARK: - Queries

    func count() async throws -> Int {
        let js = """
        (function() {
            \(resolveAllElementsJS())
            return els.length;
        })()
        """
        let result: Int = try await page.evaluate(js)
        return result
    }

    func textContent() async throws -> String {
        let js = """
        (function() {
            \(resolveElementJS())
            if (!el) return '';
            return el.textContent || '';
        })()
        """
        return try await page.evaluate(js)
    }

    func innerText() async throws -> String {
        let js = """
        (function() {
            \(resolveElementJS())
            if (!el) return '';
            return el.innerText || '';
        })()
        """
        return try await page.evaluate(js)
    }

    func innerHTML() async throws -> String {
        let js = """
        (function() {
            \(resolveElementJS())
            if (!el) return '';
            return el.innerHTML || '';
        })()
        """
        return try await page.evaluate(js)
    }

    func getAttribute(_ name: String) async throws -> String? {
        let escaped = name.replacingOccurrences(of: "'", with: "\\'")
        let js = """
        (function() {
            \(resolveElementJS())
            if (!el) return '__null__';
            var v = el.getAttribute('\(escaped)');
            return v === null ? '__null__' : v;
        })()
        """
        let result: String = try await page.evaluate(js)
        return result == "__null__" ? nil : result
    }

    func inputValue() async throws -> String {
        let js = """
        (function() {
            \(resolveElementJS())
            if (!el) return '';
            return el.value || '';
        })()
        """
        return try await page.evaluate(js)
    }

    func isVisible() async -> Bool {
        let js = """
        (function() {
            \(resolveElementJS())
            if (!el) return false;
            var rect = el.getBoundingClientRect();
            var style = window.getComputedStyle(el);
            return rect.width > 0 && rect.height > 0
                && style.visibility !== 'hidden'
                && style.display !== 'none'
                && parseFloat(style.opacity) > 0;
        })()
        """
        return (try? await page.evaluate(js) as Bool) ?? false
    }

    func isEnabled() async -> Bool {
        let js = """
        (function() {
            \(resolveElementJS())
            if (!el) return false;
            return !el.disabled;
        })()
        """
        return (try? await page.evaluate(js) as Bool) ?? false
    }

    func isChecked() async -> Bool {
        let js = """
        (function() {
            \(resolveElementJS())
            if (!el) return false;
            return !!el.checked;
        })()
        """
        return (try? await page.evaluate(js) as Bool) ?? false
    }

    func boundingBox() async throws -> (x: Double, y: Double, width: Double, height: Double)? {
        let js = """
        (function() {
            \(resolveElementJS())
            if (!el) return JSON.stringify({error: 'not_found'});
            var rect = el.getBoundingClientRect();
            return JSON.stringify({x: rect.x, y: rect.y, width: rect.width, height: rect.height});
        })()
        """
        let result: String = try await page.evaluate(js)
        guard let data = result.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["error"] == nil,
              let x = dict["x"] as? Double,
              let y = dict["y"] as? Double,
              let w = dict["width"] as? Double,
              let h = dict["height"] as? Double else {
            return nil
        }
        return (x, y, w, h)
    }

    // MARK: - Chaining

    func first() -> Locator {
        Locator(page: page, selector: selector, timeout: timeout, parentSelector: parentSelector, nthIndex: 0, textFilter: textFilter)
    }

    func last() -> Locator {
        Locator(page: page, selector: selector, timeout: timeout, parentSelector: parentSelector, nthIndex: -1, textFilter: textFilter)
    }

    func nth(_ index: Int) -> Locator {
        Locator(page: page, selector: selector, timeout: timeout, parentSelector: parentSelector, nthIndex: index, textFilter: textFilter)
    }

    func locator(_ childSelector: String) -> Locator {
        let fullParent: String
        if let existing = parentSelector {
            fullParent = existing + " " + selector
        } else {
            fullParent = selector
        }
        return Locator(page: page, selector: childSelector, timeout: timeout, parentSelector: fullParent)
    }

    func filter(hasText text: String) -> Locator {
        Locator(page: page, selector: selector, timeout: timeout, parentSelector: parentSelector, nthIndex: nthIndex, textFilter: text)
    }

    // MARK: - Internal: Element Resolution JS

    private func resolveElementJS() -> String {
        let allElsJS = resolveAllElementsJS()
        return """
        \(allElsJS)
        var el = null;
        if (els.length > 0) {
            \(nthSelectionJS())
        }
        """
    }

    private func resolveAllElementsJS() -> String {
        var js = ""

        let effectiveSelector: String
        if let parent = parentSelector {
            if parent.hasPrefix("xpath=") {
                let parentXpath = String(parent.dropFirst(6)).replacingOccurrences(of: "'", with: "\\'")
                js += "var _pxr = document.evaluate('\(parentXpath)', document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null);\n"
                js += "var _pEl = _pxr.singleNodeValue;\n"
                js += "var _scope = _pEl || document;\n"
            } else {
                let escapedParent = parent.replacingOccurrences(of: "'", with: "\\'")
                js += "var _scope = document.querySelector('\(escapedParent)') || document;\n"
            }
            effectiveSelector = selector
        } else {
            js += "var _scope = document;\n"
            effectiveSelector = selector
        }

        if effectiveSelector.hasPrefix("xpath=") {
            let xpath = String(effectiveSelector.dropFirst(6)).replacingOccurrences(of: "'", with: "\\'")
            js += "var _xr = document.evaluate('\(xpath)', _scope, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);\n"
            js += "var els = [];\n"
            js += "for (var _i = 0; _i < _xr.snapshotLength; _i++) { els.push(_xr.snapshotItem(_i)); }\n"
        } else {
            let escaped = effectiveSelector.replacingOccurrences(of: "'", with: "\\'")
            js += "var els = Array.from(_scope.querySelectorAll('\(escaped)'));\n"
        }

        if let text = textFilter {
            let escapedText = text.replacingOccurrences(of: "'", with: "\\'")
            js += "els = els.filter(function(e) { return (e.textContent || '').indexOf('\(escapedText)') !== -1; });\n"
        }

        return js
    }

    private func nthSelectionJS() -> String {
        guard let idx = nthIndex else {
            return "el = els[0];"
        }
        if idx == -1 {
            return "el = els[els.length - 1];"
        }
        return "el = \(idx) < els.length ? els[\(idx)] : null;"
    }

    // MARK: - Internal: Auto-Wait

    private func waitForActionable(timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let js = """
            (function() {
                \(resolveElementJS())
                if (!el) return JSON.stringify({state: 'detached'});
                var rect = el.getBoundingClientRect();
                var style = window.getComputedStyle(el);
                var visible = rect.width > 0 && rect.height > 0
                    && style.visibility !== 'hidden'
                    && style.display !== 'none'
                    && parseFloat(style.opacity) > 0;
                var enabled = !el.disabled;
                if (visible && enabled) return JSON.stringify({state: 'actionable'});
                if (visible) return JSON.stringify({state: 'visible'});
                return JSON.stringify({state: 'hidden'});
            })()
            """

            if let result: String = try? await page.evaluate(js),
               let data = result.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               dict["state"] == "actionable" {
                return
            }

            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        throw PlaywrightError.timeout("Waiting for \(selector) to be actionable timed out after \(Int(timeout))s")
    }

    private func waitForAttached(timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let js = """
            (function() {
                \(resolveElementJS())
                return el !== null && el !== undefined;
            })()
            """

            if let attached: Bool = try? await page.evaluate(js), attached {
                return
            }

            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        throw PlaywrightError.elementNotFound(selector)
    }

    // MARK: - Internal: Retry

    private func retryAction(timeout: TimeInterval, action: @escaping () async throws -> Void) async throws {
        var lastError: Error?
        var backoff = 100

        for attempt in 0..<maxRetries {
            do {
                try await action()
                return
            } catch let error as PlaywrightError {
                switch error {
                case .elementNotFound, .elementNotVisible, .elementNotInteractable:
                    lastError = error
                    if attempt < maxRetries - 1 {
                        page.trace(.action, "retry \(attempt + 1)/\(maxRetries) after \(backoff)ms — \(error.localizedDescription)")
                        try await Task.sleep(for: .milliseconds(backoff))
                        backoff *= 2
                    }
                default:
                    throw error
                }
            }
        }

        throw lastError ?? PlaywrightError.elementNotInteractable(selector)
    }

    // MARK: - Internal: Parse Result

    private func parseActionResult(_ json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PlaywrightError.javaScriptError("Failed to parse action result: \(String(json.prefix(100)))")
        }
        if let error = dict["error"] as? String {
            switch error {
            case "not_found": throw PlaywrightError.elementNotFound(selector)
            case "not_select": throw PlaywrightError.elementNotInteractable("\(selector) is not a <select>")
            default: throw PlaywrightError.javaScriptError(error)
            }
        }
        return dict
    }
}
