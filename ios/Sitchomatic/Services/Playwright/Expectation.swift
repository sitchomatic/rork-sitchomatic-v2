import Foundation

@MainActor
final class Expectation {

    private let locator: Locator
    private let page: PlaywrightPage
    private let negated: Bool
    private let pollInterval: TimeInterval = 0.15

    init(locator: Locator, page: PlaywrightPage, negated: Bool) {
        self.locator = locator
        self.page = page
        self.negated = negated
    }

    var not: Expectation {
        Expectation(locator: locator, page: page, negated: !negated)
    }

    // MARK: - Visibility

    func toBeVisible(timeout: TimeInterval = 30.0) async throws {
        page.trace(.assertion, "expect(\(locator.selector)).\(negated ? "not." : "")toBeVisible()")
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let visible = await locator.isVisible()
            if negated ? !visible : visible { return }
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        if negated {
            throw PlaywrightError.assertionFailed("\(locator.selector) was still visible after \(Int(timeout))s")
        } else {
            throw PlaywrightError.assertionFailed("\(locator.selector) was not visible after \(Int(timeout))s")
        }
    }

    func toBeHidden(timeout: TimeInterval = 30.0) async throws {
        page.trace(.assertion, "expect(\(locator.selector)).\(negated ? "not." : "")toBeHidden()")
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let visible = await locator.isVisible()
            let hidden = !visible
            if negated ? !hidden : hidden { return }
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        if negated {
            throw PlaywrightError.assertionFailed("\(locator.selector) was not visible (expected not hidden) after \(Int(timeout))s")
        } else {
            throw PlaywrightError.assertionFailed("\(locator.selector) was still visible after \(Int(timeout))s")
        }
    }

    func toBeAttached(timeout: TimeInterval = 30.0) async throws {
        page.trace(.assertion, "expect(\(locator.selector)).\(negated ? "not." : "")toBeAttached()")
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let count = (try? await locator.count()) ?? 0
            let attached = count > 0
            if negated ? !attached : attached { return }
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        if negated {
            throw PlaywrightError.assertionFailed("\(locator.selector) was still attached after \(Int(timeout))s")
        } else {
            throw PlaywrightError.assertionFailed("\(locator.selector) was not attached after \(Int(timeout))s")
        }
    }

    func toBeDetached(timeout: TimeInterval = 30.0) async throws {
        page.trace(.assertion, "expect(\(locator.selector)).\(negated ? "not." : "")toBeDetached()")
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let count = (try? await locator.count()) ?? 0
            let detached = count == 0
            if negated ? !detached : detached { return }
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        if negated {
            throw PlaywrightError.assertionFailed("\(locator.selector) was still detached after \(Int(timeout))s")
        } else {
            throw PlaywrightError.assertionFailed("\(locator.selector) was still attached after \(Int(timeout))s")
        }
    }

    // MARK: - State

    func toBeEnabled(timeout: TimeInterval = 30.0) async throws {
        page.trace(.assertion, "expect(\(locator.selector)).\(negated ? "not." : "")toBeEnabled()")
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let enabled = await locator.isEnabled()
            if negated ? !enabled : enabled { return }
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        if negated {
            throw PlaywrightError.assertionFailed("\(locator.selector) was still enabled after \(Int(timeout))s")
        } else {
            throw PlaywrightError.assertionFailed("\(locator.selector) was not enabled after \(Int(timeout))s")
        }
    }

    func toBeDisabled(timeout: TimeInterval = 30.0) async throws {
        page.trace(.assertion, "expect(\(locator.selector)).\(negated ? "not." : "")toBeDisabled()")
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let disabled = !(await locator.isEnabled())
            if negated ? !disabled : disabled { return }
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        if negated {
            throw PlaywrightError.assertionFailed("\(locator.selector) was still disabled after \(Int(timeout))s")
        } else {
            throw PlaywrightError.assertionFailed("\(locator.selector) was still enabled after \(Int(timeout))s")
        }
    }

    func toBeChecked(timeout: TimeInterval = 30.0) async throws {
        page.trace(.assertion, "expect(\(locator.selector)).\(negated ? "not." : "")toBeChecked()")
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let checked = await locator.isChecked()
            if negated ? !checked : checked { return }
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        if negated {
            throw PlaywrightError.assertionFailed("\(locator.selector) was still checked after \(Int(timeout))s")
        } else {
            throw PlaywrightError.assertionFailed("\(locator.selector) was not checked after \(Int(timeout))s")
        }
    }

    // MARK: - Text Content

    func toHaveText(_ expected: String, exact: Bool = true, timeout: TimeInterval = 30.0) async throws {
        page.trace(.assertion, "expect(\(locator.selector)).\(negated ? "not." : "")toHaveText('\(String(expected.prefix(40)))')")
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let text = try? await locator.textContent() {
                let matches: Bool
                if exact {
                    matches = text.trimmingCharacters(in: .whitespacesAndNewlines) == expected
                } else {
                    matches = text.localizedStandardContains(expected)
                }
                if negated ? !matches : matches { return }
            }
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        let actual = (try? await locator.textContent()) ?? "<empty>"
        if negated {
            throw PlaywrightError.assertionFailed(
                "\(locator.selector) text unexpectedly matched: '\(String(expected.prefix(60)))'"
            )
        } else {
            throw PlaywrightError.assertionFailed(
                "\(locator.selector) text mismatch — expected: '\(String(expected.prefix(60)))', got: '\(String(actual.prefix(100)))'"
            )
        }
    }

    func toContainText(_ expected: String, timeout: TimeInterval = 30.0) async throws {
        try await toHaveText(expected, exact: false, timeout: timeout)
    }

    // MARK: - Attribute

    func toHaveAttribute(_ name: String, value: String, timeout: TimeInterval = 30.0) async throws {
        page.trace(.assertion, "expect(\(locator.selector)).\(negated ? "not." : "")toHaveAttribute('\(name)', '\(value)')")
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let attrValue = try? await locator.getAttribute(name) {
                let matches = attrValue == value
                if negated ? !matches : matches { return }
            } else if negated {
                return
            }
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        let actual = (try? await locator.getAttribute(name)) ?? "<none>"
        if negated {
            throw PlaywrightError.assertionFailed(
                "\(locator.selector) attribute '\(name)' unexpectedly equals '\(value)'"
            )
        } else {
            throw PlaywrightError.assertionFailed(
                "\(locator.selector) attribute '\(name)' — expected: '\(value)', got: '\(actual)'"
            )
        }
    }

    // MARK: - Value

    func toHaveValue(_ expected: String, timeout: TimeInterval = 30.0) async throws {
        page.trace(.assertion, "expect(\(locator.selector)).\(negated ? "not." : "")toHaveValue('\(String(expected.prefix(40)))')")
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let val = try? await locator.inputValue() {
                let matches = val == expected
                if negated ? !matches : matches { return }
            }
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        let actual = (try? await locator.inputValue()) ?? "<empty>"
        if negated {
            throw PlaywrightError.assertionFailed(
                "\(locator.selector) value unexpectedly equals '\(String(expected.prefix(60)))'"
            )
        } else {
            throw PlaywrightError.assertionFailed(
                "\(locator.selector) value mismatch — expected: '\(String(expected.prefix(60)))', got: '\(actual)'"
            )
        }
    }

    // MARK: - Count

    func toHaveCount(_ expected: Int, timeout: TimeInterval = 30.0) async throws {
        page.trace(.assertion, "expect(\(locator.selector)).\(negated ? "not." : "")toHaveCount(\(expected))")
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let count = try? await locator.count() {
                let matches = count == expected
                if negated ? !matches : matches { return }
            }
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        let actual = (try? await locator.count()) ?? -1
        if negated {
            throw PlaywrightError.assertionFailed(
                "\(locator.selector) count unexpectedly equals \(expected)"
            )
        } else {
            throw PlaywrightError.assertionFailed(
                "\(locator.selector) count mismatch — expected: \(expected), got: \(actual)"
            )
        }
    }

    // MARK: - CSS Class

    func toHaveClass(_ expected: String, timeout: TimeInterval = 30.0) async throws {
        page.trace(.assertion, "expect(\(locator.selector)).\(negated ? "not." : "")toHaveClass('\(expected)')")
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let classAttr = try? await locator.getAttribute("class") {
                let classes = Set(classAttr.components(separatedBy: .whitespaces).filter { !$0.isEmpty })
                let expectedClasses = Set(expected.components(separatedBy: .whitespaces).filter { !$0.isEmpty })
                let matches = expectedClasses.isSubset(of: classes)
                if negated ? !matches : matches { return }
            } else if negated {
                return
            }
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        let actual = (try? await locator.getAttribute("class")) ?? "<none>"
        if negated {
            throw PlaywrightError.assertionFailed(
                "\(locator.selector) unexpectedly has class '\(expected)'"
            )
        } else {
            throw PlaywrightError.assertionFailed(
                "\(locator.selector) class mismatch — expected: '\(expected)', got: '\(actual)'"
            )
        }
    }

    // MARK: - CSS Property

    func toHaveCSS(_ property: String, value: String, timeout: TimeInterval = 30.0) async throws {
        let escapedProp = property.replacingOccurrences(of: "'", with: "\\'")
        page.trace(.assertion, "expect(\(locator.selector)).\(negated ? "not." : "")toHaveCSS('\(property)', '\(value)')")
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let js = """
            (function() {
                var el = document.querySelector('\(locator.selector.replacingOccurrences(of: "'", with: "\\'"))');
                if (!el) return '';
                return window.getComputedStyle(el).getPropertyValue('\(escapedProp)');
            })()
            """
            if let computed: String = try? await page.evaluate(js) {
                let matches = computed.trimmingCharacters(in: .whitespaces) == value
                if negated ? !matches : matches { return }
            }
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        if negated {
            throw PlaywrightError.assertionFailed(
                "\(locator.selector) CSS '\(property)' unexpectedly equals '\(value)'"
            )
        } else {
            throw PlaywrightError.assertionFailed(
                "\(locator.selector) CSS '\(property)' does not equal '\(value)' after \(Int(timeout))s"
            )
        }
    }

    // MARK: - URL (Page-Level)

    func toHaveURL(_ expected: String, exact: Bool = true, timeout: TimeInterval = 30.0) async throws {
        page.trace(.assertion, "expect(page).\(negated ? "not." : "")toHaveURL('\(String(expected.prefix(60)))')")
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let currentURL = page.url()
            let matches: Bool
            if exact {
                matches = currentURL == expected
            } else {
                matches = currentURL.contains(expected)
            }
            if negated ? !matches : matches { return }
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        let actual = page.url()
        if negated {
            throw PlaywrightError.assertionFailed(
                "URL unexpectedly matches '\(String(expected.prefix(60)))'"
            )
        } else {
            throw PlaywrightError.assertionFailed(
                "URL mismatch — expected: '\(String(expected.prefix(60)))', got: '\(actual)'"
            )
        }
    }

    // MARK: - Title (Page-Level)

    func toHaveTitle(_ expected: String, exact: Bool = true, timeout: TimeInterval = 30.0) async throws {
        page.trace(.assertion, "expect(page).\(negated ? "not." : "")toHaveTitle('\(String(expected.prefix(40)))')")
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if let title = try? await page.title() {
                let matches: Bool
                if exact {
                    matches = title == expected
                } else {
                    matches = title.localizedStandardContains(expected)
                }
                if negated ? !matches : matches { return }
            }
            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        let actual = (try? await page.title()) ?? "<empty>"
        if negated {
            throw PlaywrightError.assertionFailed(
                "Title unexpectedly matches '\(String(expected.prefix(40)))'"
            )
        } else {
            throw PlaywrightError.assertionFailed(
                "Title mismatch — expected: '\(String(expected.prefix(40)))', got: '\(actual)'"
            )
        }
    }
}
