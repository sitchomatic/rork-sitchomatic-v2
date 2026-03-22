import Foundation
import WebKit

@Observable
@MainActor
final class PlaywrightPage {

    private(set) var currentURL: String = ""
    private(set) var isLoading: Bool = false
    private(set) var isNavigating: Bool = false
    private(set) var tracingEnabled: Bool = false
    private(set) var traceLog: [TraceEntry] = []

    let id: UUID
    let webView: WKWebView

    private let defaultTimeout: TimeInterval
    private let autoWaitStabilityDelay: TimeInterval = 0.3
    private let navigationDelegate: PageNavigationDelegate
    private var networkIdleInjected: Bool = false
    private weak var orchestrator: PlaywrightOrchestrator?

    init(
        webView: WKWebView,
        id: UUID = UUID(),
        defaultTimeout: TimeInterval = 30.0,
        orchestrator: PlaywrightOrchestrator? = nil
    ) {
        self.webView = webView
        self.id = id
        self.defaultTimeout = defaultTimeout
        self.orchestrator = orchestrator
        self.navigationDelegate = PageNavigationDelegate()
        self.webView.navigationDelegate = navigationDelegate
    }

    // MARK: - Navigation

    func goto(_ url: String, waitUntil: NavigationWaitCondition = .load, timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? defaultTimeout
        guard let requestURL = URL(string: url) else {
            throw PlaywrightError.invalidURL(url)
        }

        trace(.navigation, "goto \(url)")
        isNavigating = true
        isLoading = true

        let request = URLRequest(url: requestURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: effectiveTimeout)
        navigationDelegate.reset()
        webView.load(request)

        do {
            try await waitForNavigation(condition: waitUntil, timeout: effectiveTimeout)
            try await injectNetworkIdleMonitor()
            try await injectStealthScripts()
        } catch {
            isNavigating = false
            isLoading = false
            throw error
        }

        currentURL = webView.url?.absoluteString ?? url
        isNavigating = false
        isLoading = false
        trace(.navigation, "navigated to \(currentURL)")
    }

    func goBack() async throws {
        guard webView.canGoBack else {
            throw PlaywrightError.navigationFailed("Cannot go back — no history")
        }
        trace(.navigation, "goBack")
        navigationDelegate.reset()
        webView.goBack()
        try await waitForNavigation(condition: .load, timeout: defaultTimeout)
        currentURL = webView.url?.absoluteString ?? ""
    }

    func goForward() async throws {
        guard webView.canGoForward else {
            throw PlaywrightError.navigationFailed("Cannot go forward — no history")
        }
        trace(.navigation, "goForward")
        navigationDelegate.reset()
        webView.goForward()
        try await waitForNavigation(condition: .load, timeout: defaultTimeout)
        currentURL = webView.url?.absoluteString ?? ""
    }

    func reload() async throws {
        trace(.navigation, "reload")
        navigationDelegate.reset()
        webView.reload()
        try await waitForNavigation(condition: .load, timeout: defaultTimeout)
        currentURL = webView.url?.absoluteString ?? ""
    }

    // MARK: - Locators

    func locator(_ selector: String) -> Locator {
        Locator(page: self, selector: selector, timeout: defaultTimeout)
    }

    func locatorByText(_ text: String, exact: Bool = false) -> Locator {
        let escapedText = text.replacingOccurrences(of: "'", with: "\\'")
        let xpath: String
        if exact {
            xpath = "xpath=//*[normalize-space(text())='\(escapedText)']"
        } else {
            xpath = "xpath=//*[contains(normalize-space(text()), '\(escapedText)')]"
        }
        return Locator(page: self, selector: xpath, timeout: defaultTimeout)
    }

    func locatorByRole(_ role: String, name: String? = nil) -> Locator {
        var css: String
        let roleAttr = roleAttribute(role)
        if let name {
            let escaped = name.replacingOccurrences(of: "\"", with: "\\\"")
            css = "[\(roleAttr)][aria-label=\"\(escaped)\"], [\(roleAttr)][title=\"\(escaped)\"]"
        } else {
            css = "[\(roleAttr)]"
        }
        return Locator(page: self, selector: css, timeout: defaultTimeout)
    }

    func locatorByPlaceholder(_ placeholder: String) -> Locator {
        let escaped = placeholder.replacingOccurrences(of: "\"", with: "\\\"")
        return Locator(page: self, selector: "[placeholder=\"\(escaped)\"]", timeout: defaultTimeout)
    }

    func locatorByLabel(_ label: String) -> Locator {
        let escaped = label.replacingOccurrences(of: "'", with: "\\'")
        let xpath = "xpath=//label[contains(normalize-space(.), '\(escaped)')]/..//input | //input[@aria-label='\(escaped)']"
        return Locator(page: self, selector: xpath, timeout: defaultTimeout)
    }

    func locatorByTestId(_ testId: String) -> Locator {
        let escaped = testId.replacingOccurrences(of: "\"", with: "\\\"")
        return Locator(page: self, selector: "[data-testid=\"\(escaped)\"]", timeout: defaultTimeout)
    }

    // MARK: - Expectations

    func expect(_ locator: Locator) -> Expectation {
        Expectation(locator: locator, page: self, negated: false)
    }

    // MARK: - JavaScript Evaluation

    func evaluate<T>(_ script: String) async throws -> T {
        trace(.evaluate, String(script.prefix(120)))
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: PlaywrightError.javaScriptError(error.localizedDescription))
                } else if let value = result as? T {
                    continuation.resume(returning: value)
                } else if result == nil || result is NSNull {
                    continuation.resume(throwing: PlaywrightError.javaScriptError("Expression returned null/undefined, expected \(T.self). Script: \(String(script.prefix(80)))"))
                } else {
                    let actualType = type(of: result!)
                    continuation.resume(throwing: PlaywrightError.javaScriptError("Type mismatch: expected \(T.self), got \(actualType) (\(String(describing: result!))). Script: \(String(script.prefix(80)))"))
                }
            }
        }
    }

    func evaluateVoid(_ script: String) async throws {
        trace(.evaluate, String(script.prefix(120)))
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { _, error in
                if let error {
                    continuation.resume(throwing: PlaywrightError.javaScriptError(error.localizedDescription))
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    func evaluateHandle(_ script: String) async throws -> Any? {
        return try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: PlaywrightError.javaScriptError(error.localizedDescription))
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    // MARK: - Screenshots

    func screenshot() async throws -> Data {
        trace(.screenshot, "capture")
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = NSNumber(value: Int(webView.bounds.width))

        return try await withCheckedThrowingContinuation { continuation in
            webView.takeSnapshot(with: config) { image, error in
                if let error {
                    continuation.resume(throwing: PlaywrightError.screenshotFailed(error.localizedDescription))
                } else if let image, let data = image.pngData() {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: PlaywrightError.screenshotFailed("No image data"))
                }
            }
        }
    }

    // MARK: - Page Content

    func title() async throws -> String {
        try await evaluate("document.title")
    }

    func content() async throws -> String {
        try await evaluate("document.documentElement.outerHTML")
    }

    func url() -> String {
        webView.url?.absoluteString ?? currentURL
    }

    // MARK: - Cookies

    func cookies(urls: [String]? = nil) async -> [[String: Any]] {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        let allCookies = await store.allCookies()

        let filtered: [HTTPCookie]
        if let urls, !urls.isEmpty {
            let targetHosts = urls.compactMap { URL(string: $0)?.host }
            filtered = allCookies.filter { cookie in
                targetHosts.contains(where: { host in
                    host == cookie.domain || host.hasSuffix("." + cookie.domain) || cookie.domain.hasPrefix(".")
                        && host.hasSuffix(String(cookie.domain.dropFirst()))
                })
            }
        } else {
            filtered = allCookies
        }

        return filtered.map { cookie in
            var dict: [String: Any] = [
                "name": cookie.name,
                "value": cookie.value,
                "domain": cookie.domain,
                "path": cookie.path
            ]
            if let expires = cookie.expiresDate {
                dict["expires"] = expires.timeIntervalSince1970
            }
            dict["httpOnly"] = cookie.isHTTPOnly
            dict["secure"] = cookie.isSecure
            return dict
        }
    }

    func setCookie(name: String, value: String, domain: String, path: String = "/", secure: Bool = false, httpOnly: Bool = false) async {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path
        ]
        if secure { properties[.secure] = "TRUE" }

        if let cookie = HTTPCookie(properties: properties) {
            await webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie)
            trace(.action, "setCookie(\(name)=\(String(value.prefix(20))))")
        }
    }

    func clearCookies() async {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        for cookie in await store.allCookies() {
            await store.deleteCookie(cookie)
        }
        trace(.action, "clearCookies()")
    }

    // MARK: - Wait Helpers

    func waitForSelector(_ selector: String, state: LocatorState = .visible, timeout: TimeInterval? = nil) async throws {
        let loc = locator(selector)
        try await loc.waitFor(state: state, timeout: timeout ?? defaultTimeout)
    }

    func waitForTimeout(_ milliseconds: Int) async throws {
        trace(.wait, "\(milliseconds)ms")
        try await Task.sleep(for: .milliseconds(milliseconds))
    }

    func waitForLoadState(_ state: NavigationWaitCondition = .load, timeout: TimeInterval? = nil) async throws {
        try await waitForNavigation(condition: state, timeout: timeout ?? defaultTimeout)
    }

    func waitForURL(_ urlPattern: String, exact: Bool = false, timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? defaultTimeout
        trace(.wait, "waitForURL('\(String(urlPattern.prefix(60)))')")
        let deadline = Date().addingTimeInterval(effectiveTimeout)

        while Date() < deadline {
            let current = webView.url?.absoluteString ?? ""
            let matches: Bool
            if exact {
                matches = current == urlPattern
            } else {
                matches = current.contains(urlPattern)
            }
            if matches { return }
            try await Task.sleep(for: .milliseconds(150))
        }

        let actual = webView.url?.absoluteString ?? "<empty>"
        throw PlaywrightError.timeout("Waiting for URL '\(urlPattern)' timed out. Current: '\(actual)'")
    }

    func waitForFunction(_ expression: String, timeout: TimeInterval? = nil) async throws {
        let effectiveTimeout = timeout ?? defaultTimeout
        trace(.wait, "waitForFunction(\(String(expression.prefix(60))))")
        let deadline = Date().addingTimeInterval(effectiveTimeout)

        let wrappedJS = """
        (function() {
            try { return !!(\(expression)); } catch(e) { return false; }
        })()
        """

        while Date() < deadline {
            if let result: Bool = try? await evaluate(wrappedJS), result {
                return
            }
            try await Task.sleep(for: .milliseconds(150))
        }

        throw PlaywrightError.timeout("waitForFunction timed out after \(Int(effectiveTimeout))s: \(String(expression.prefix(80)))")
    }

    // MARK: - Page Lifecycle

    func close() {
        if tracingEnabled {
            _ = stopTracing()
        }
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        orchestrator?.closePage(self)
        trace(.system, "page closed")
    }

    // MARK: - Tracing

    func startTracing() {
        tracingEnabled = true
        traceLog.removeAll()
        trace(.system, "tracing started")
    }

    func stopTracing() -> [TraceEntry] {
        trace(.system, "tracing stopped")
        tracingEnabled = false
        return traceLog
    }

    func trace(_ category: TraceCategory, _ message: String) {
        guard tracingEnabled else { return }
        traceLog.append(TraceEntry(
            timestamp: Date(),
            category: category,
            message: message,
            pageID: id
        ))
    }

    // MARK: - Internal: Stealth Injection

    private func injectStealthScripts() async throws {
        let settings = AutomationSettings.load().stealth

        var scripts: [String] = []

        if settings.blockCDPDetection {
            scripts.append("""
            Object.defineProperty(navigator, 'webdriver', {get: function(){return undefined;}});
            if (window.chrome) { window.chrome.runtime = undefined; }
            delete navigator.__proto__.webdriver;
            """)
        }

        if settings.spoofCanvas {
            scripts.append("""
            (function(){
                var _toDataURL = HTMLCanvasElement.prototype.toDataURL;
                HTMLCanvasElement.prototype.toDataURL = function(type) {
                    var ctx = this.getContext('2d');
                    if (ctx) {
                        var noise = Math.random() * 0.01;
                        var imgData = ctx.getImageData(0, 0, Math.min(this.width, 2), Math.min(this.height, 2));
                        for (var i = 0; i < imgData.data.length; i += 4) {
                            imgData.data[i] = Math.max(0, Math.min(255, imgData.data[i] + noise * 255));
                        }
                        ctx.putImageData(imgData, 0, 0);
                    }
                    return _toDataURL.apply(this, arguments);
                };
                var _toBlob = HTMLCanvasElement.prototype.toBlob;
                HTMLCanvasElement.prototype.toBlob = function() {
                    var ctx = this.getContext('2d');
                    if (ctx) {
                        var noise = Math.random() * 0.01;
                        var imgData = ctx.getImageData(0, 0, Math.min(this.width, 2), Math.min(this.height, 2));
                        imgData.data[0] = Math.max(0, Math.min(255, imgData.data[0] + noise * 255));
                        ctx.putImageData(imgData, 0, 0);
                    }
                    return _toBlob.apply(this, arguments);
                };
            })();
            """)
        }

        if settings.spoofWebGL {
            scripts.append("""
            (function(){
                var _getParam = WebGLRenderingContext.prototype.getParameter;
                WebGLRenderingContext.prototype.getParameter = function(param) {
                    if (param === 37445) return 'Apple Inc.';
                    if (param === 37446) return 'Apple GPU';
                    return _getParam.apply(this, arguments);
                };
                if (typeof WebGL2RenderingContext !== 'undefined') {
                    var _getParam2 = WebGL2RenderingContext.prototype.getParameter;
                    WebGL2RenderingContext.prototype.getParameter = function(param) {
                        if (param === 37445) return 'Apple Inc.';
                        if (param === 37446) return 'Apple GPU';
                        return _getParam2.apply(this, arguments);
                    };
                }
            })();
            """)
        }

        if settings.spoofAudioContext {
            scripts.append("""
            (function(){
                if (typeof AudioContext !== 'undefined') {
                    var _createOsc = AudioContext.prototype.createOscillator;
                    AudioContext.prototype.createOscillator = function() {
                        var osc = _createOsc.apply(this, arguments);
                        var _getFreq = Object.getOwnPropertyDescriptor(OscillatorNode.prototype, 'frequency');
                        return osc;
                    };
                }
                if (typeof OfflineAudioContext !== 'undefined') {
                    var _startRendering = OfflineAudioContext.prototype.startRendering;
                    OfflineAudioContext.prototype.startRendering = function() {
                        return _startRendering.apply(this, arguments).then(function(buffer) {
                            var output = buffer.getChannelData(0);
                            for (var i = 0; i < Math.min(output.length, 10); i++) {
                                output[i] += (Math.random() - 0.5) * 0.0001;
                            }
                            return buffer;
                        });
                    };
                }
            })();
            """)
        }

        if settings.maskWebRTC {
            scripts.append("""
            (function(){
                if (typeof RTCPeerConnection !== 'undefined') {
                    var _createOffer = RTCPeerConnection.prototype.createOffer;
                    RTCPeerConnection.prototype.createOffer = function() {
                        return _createOffer.apply(this, arguments).then(function(offer) {
                            offer.sdp = offer.sdp.replace(/[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}/g, '0.0.0.0');
                            return offer;
                        });
                    };
                }
            })();
            """)
        }

        if settings.randomizeNavigatorProperties {
            scripts.append("""
            (function(){
                Object.defineProperty(navigator, 'hardwareConcurrency', {get: function(){return [4,8,10,12][Math.floor(Math.random()*4)];}});
                Object.defineProperty(navigator, 'deviceMemory', {get: function(){return [4,8,16][Math.floor(Math.random()*3)];}});
                Object.defineProperty(navigator, 'maxTouchPoints', {get: function(){return 5;}});
                Object.defineProperty(navigator, 'plugins', {get: function(){return [];}});
                Object.defineProperty(navigator, 'languages', {get: function(){return ['en-US','en'];}});
            })();
            """)
        }

        if !scripts.isEmpty {
            let combined = scripts.joined(separator: "\n")
            try await evaluateVoid(combined)
            trace(.system, "stealth scripts injected (\(scripts.count) modules)")
        }
    }

    // MARK: - Internal: Network Idle Monitor

    private func injectNetworkIdleMonitor() async throws {
        guard !networkIdleInjected else { return }

        let monitorJS = """
        (function() {
            if (window.__pwNetworkMonitor) return;
            window.__pwNetworkMonitor = {pending: 0, lastActivity: Date.now()};
            var m = window.__pwNetworkMonitor;
            var _fetch = window.fetch;
            window.fetch = function() {
                m.pending++;
                m.lastActivity = Date.now();
                return _fetch.apply(this, arguments).finally(function() {
                    m.pending = Math.max(0, m.pending - 1);
                    m.lastActivity = Date.now();
                });
            };
            var _open = XMLHttpRequest.prototype.open;
            var _send = XMLHttpRequest.prototype.send;
            XMLHttpRequest.prototype.open = function() {
                this.__pw_tracked = true;
                return _open.apply(this, arguments);
            };
            XMLHttpRequest.prototype.send = function() {
                if (this.__pw_tracked) {
                    m.pending++;
                    m.lastActivity = Date.now();
                    this.addEventListener('loadend', function() {
                        m.pending = Math.max(0, m.pending - 1);
                        m.lastActivity = Date.now();
                    });
                }
                return _send.apply(this, arguments);
            };
        })();
        """

        try await evaluateVoid(monitorJS)
        networkIdleInjected = true
    }

    // MARK: - Internal: Navigation Wait

    private func waitForNavigation(condition: NavigationWaitCondition, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        let pollInterval: TimeInterval = 0.1

        while Date() < deadline {
            if let navError = navigationDelegate.navigationError {
                throw PlaywrightError.navigationFailed(navError.localizedDescription)
            }

            let satisfied: Bool
            switch condition {
            case .load:
                satisfied = navigationDelegate.didFinishLoad

            case .domContentLoaded:
                let ready: String = (try? await evaluate("document.readyState")) ?? "loading"
                satisfied = ready == "interactive" || ready == "complete"

            case .networkIdle:
                if !navigationDelegate.didFinishLoad {
                    satisfied = false
                } else {
                    let idleCheck = """
                    (function() {
                        var m = window.__pwNetworkMonitor;
                        if (!m) return true;
                        return m.pending === 0 && (Date.now() - m.lastActivity) > 500;
                    })()
                    """
                    let isIdle: Bool = (try? await evaluate(idleCheck)) ?? true
                    satisfied = isIdle
                }
            }

            if satisfied {
                try await Task.sleep(for: .milliseconds(Int(autoWaitStabilityDelay * 1000)))
                return
            }

            try await Task.sleep(for: .milliseconds(Int(pollInterval * 1000)))
        }

        throw PlaywrightError.timeout("Navigation timed out after \(Int(timeout))s (condition: \(condition))")
    }

    // MARK: - Internal: Role Mapping

    private func roleAttribute(_ role: String) -> String {
        switch role.lowercased() {
        case "button": return "role=\"button\""
        case "link": return "role=\"link\""
        case "textbox": return "role=\"textbox\""
        case "checkbox": return "role=\"checkbox\""
        case "heading": return "role=\"heading\""
        case "img", "image": return "role=\"img\""
        case "navigation": return "role=\"navigation\""
        case "dialog": return "role=\"dialog\""
        case "tab": return "role=\"tab\""
        case "listbox": return "role=\"listbox\""
        case "option": return "role=\"option\""
        case "menuitem": return "role=\"menuitem\""
        case "radio": return "role=\"radio\""
        case "slider": return "role=\"slider\""
        case "switch": return "role=\"switch\""
        case "alert": return "role=\"alert\""
        default: return "role=\"\(role)\""
        }
    }
}

// MARK: - Navigation Delegate

private final class PageNavigationDelegate: NSObject, WKNavigationDelegate {
    var didFinishLoad: Bool = false
    var navigationError: Error?

    func reset() {
        didFinishLoad = false
        navigationError = nil
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            self.didFinishLoad = true
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            self.navigationError = error
            self.didFinishLoad = true
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            self.navigationError = error
            self.didFinishLoad = true
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(.allow)
    }

    nonisolated func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        decisionHandler(.allow)
    }
}

// MARK: - Supporting Types

nonisolated enum NavigationWaitCondition: String, Sendable {
    case load
    case domContentLoaded
    case networkIdle
}

nonisolated enum LocatorState: String, Sendable {
    case visible
    case hidden
    case attached
}

nonisolated enum TraceCategory: String, Sendable {
    case navigation
    case action
    case evaluate
    case screenshot
    case wait
    case assertion
    case system
}

nonisolated struct TraceEntry: Sendable, Identifiable {
    let id: UUID = UUID()
    let timestamp: Date
    let category: TraceCategory
    let message: String
    let pageID: UUID

    var formatted: String {
        let ms = Int(timestamp.timeIntervalSince1970 * 1000) % 100000
        return "[\(ms)] [\(category.rawValue)] \(message)"
    }
}

nonisolated enum PlaywrightError: Error, LocalizedError, Sendable {
    case invalidURL(String)
    case navigationFailed(String)
    case timeout(String)
    case elementNotFound(String)
    case elementNotVisible(String)
    case elementNotInteractable(String)
    case javaScriptError(String)
    case screenshotFailed(String)
    case assertionFailed(String)
    case pageDisposed

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): "Invalid URL: \(url)"
        case .navigationFailed(let reason): "Navigation failed: \(reason)"
        case .timeout(let detail): "Timeout: \(detail)"
        case .elementNotFound(let selector): "Element not found: \(selector)"
        case .elementNotVisible(let selector): "Element not visible: \(selector)"
        case .elementNotInteractable(let selector): "Element not interactable: \(selector)"
        case .javaScriptError(let detail): "JavaScript error: \(detail)"
        case .screenshotFailed(let detail): "Screenshot failed: \(detail)"
        case .assertionFailed(let detail): "Assertion failed: \(detail)"
        case .pageDisposed: "Page has been disposed"
        }
    }
}
