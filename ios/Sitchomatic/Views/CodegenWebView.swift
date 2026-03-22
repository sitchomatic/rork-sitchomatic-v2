import SwiftUI
import WebKit
import Network

struct CodegenWebView: UIViewRepresentable {

    let session: RecordingSession
    let urlString: String
    let onNavigated: (String) -> Void
    var onWebViewCreated: ((WKWebView) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, onNavigated: onNavigated)
    }

    func makeUIView(context: Context) -> WKWebView {
        let networkManager = SimpleNetworkManager.shared
        let sessionID = "codegen-\(UUID().uuidString.prefix(8))"
        let config = ProxyConfigurationHelper.configuredWebViewConfiguration(
            forSessionID: sessionID,
            networkManager: networkManager
        )

        let controller = config.userContentController
        controller.add(context.coordinator, name: "codegenAction")
        controller.add(context.coordinator, name: "codegenHover")
        controller.add(context.coordinator, name: "codegenPick")

        let recorderJS = WKUserScript(
            source: Self.recorderInjectionJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        controller.addUserScript(recorderJS)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isInspectable = true
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

        context.coordinator.webView = webView
        onWebViewCreated?(webView)

        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.session = session

        let modeJS: String
        switch session.mode {
        case .recording:
            modeJS = "window.__pwCodegenSetMode('recording');"
        case .pickLocator:
            modeJS = "window.__pwCodegenSetMode('pickLocator');"
        case .assertVisibility:
            modeJS = "window.__pwCodegenSetMode('assertVisibility');"
        case .assertText:
            modeJS = "window.__pwCodegenSetMode('assertText');"
        }
        webView.evaluateJavaScript(modeJS, completionHandler: nil)

        let recordingState = session.isRecording && !session.isPaused ? "true" : "false"
        webView.evaluateJavaScript("window.__pwCodegenSetRecording(\(recordingState));", completionHandler: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {

        var session: RecordingSession
        let onNavigated: (String) -> Void
        weak var webView: WKWebView?
        private var lastCommittedURL: String = ""

        init(session: RecordingSession, onNavigated: @escaping (String) -> Void) {
            self.session = session
            self.onNavigated = onNavigated
        }

        nonisolated func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            Task { @MainActor in
                self.handleMessage(message)
            }
        }

        private func handleMessage(_ message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }

            switch message.name {
            case "codegenAction":
                guard let kindStr = body["kind"] as? String else { return }
                let selector = body["selector"] as? String
                let value = body["value"] as? String
                let kind: ActionKind
                switch kindStr {
                case "click": kind = .click
                case "fill": kind = .fill
                case "check": kind = .check
                case "uncheck": kind = .uncheck
                case "select": kind = .select
                case "pressEnter": kind = .pressEnter
                default: return
                }
                session.addAction(RecordedAction(
                    kind: kind,
                    selector: selector,
                    value: value,
                    timestamp: Date()
                ))

            case "codegenHover":
                let selector = body["selector"] as? String
                session.setHighlightedSelector(selector)

            case "codegenPick":
                if let selector = body["selector"] as? String {
                    session.setPickedLocator(selector)

                    switch session.mode {
                    case .assertVisibility:
                        session.addAction(RecordedAction(
                            kind: .assertVisible,
                            selector: selector,
                            value: nil,
                            timestamp: Date()
                        ))
                    case .assertText:
                        let text = body["text"] as? String
                        session.addAction(RecordedAction(
                            kind: .assertText,
                            selector: selector,
                            value: text,
                            timestamp: Date()
                        ))
                    default:
                        break
                    }
                }

            default:
                break
            }
        }

        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                let url = webView.url?.absoluteString ?? ""
                self.onNavigated(url)
                webView.evaluateJavaScript(Self.reInjectJS, completionHandler: nil)
            }
        }

        nonisolated func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            Task { @MainActor in
                let url = webView.url?.absoluteString ?? ""

                if self.session.isRecording && !self.session.isPaused
                    && !url.isEmpty && url != "about:blank"
                    && url != self.lastCommittedURL {
                    self.session.addNavigationAction(url: url)
                }

                self.lastCommittedURL = url
                self.onNavigated(url)
            }
        }

        private static let reInjectJS = CodegenWebView.recorderInjectionJS
    }

    func navigateTo(_ url: String, in webView: WKWebView?) {
        guard let webView, let requestURL = URL(string: url) else { return }
        webView.load(URLRequest(url: requestURL))
    }

    static let recorderInjectionJS: String = """
    (function() {
        if (window.__pwCodegenInjected) return;
        window.__pwCodegenInjected = true;

        var _mode = 'recording';
        var _recording = true;
        var _highlightEl = null;
        var _highlightOverlay = null;
        var _selectorLabel = null;

        window.__pwCodegenSetMode = function(m) { _mode = m; };
        window.__pwCodegenSetRecording = function(r) { _recording = r; };

        function createOverlay() {
            if (_highlightOverlay) return;
            _highlightOverlay = document.createElement('div');
            _highlightOverlay.id = '__pw_highlight';
            _highlightOverlay.style.cssText = 'position:fixed;pointer-events:none;border:2px solid #a855f7;background:rgba(168,85,247,0.08);z-index:2147483646;display:none;transition:all 0.1s ease;border-radius:3px;';
            document.body.appendChild(_highlightOverlay);

            _selectorLabel = document.createElement('div');
            _selectorLabel.id = '__pw_label';
            _selectorLabel.style.cssText = 'position:fixed;pointer-events:none;z-index:2147483647;background:#1e1b4b;color:#c4b5fd;font:11px/1.4 ui-monospace,SFMono-Regular,monospace;padding:3px 8px;border-radius:4px;max-width:350px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;display:none;box-shadow:0 2px 8px rgba(0,0,0,0.3);';
            document.body.appendChild(_selectorLabel);
        }

        function bestSelector(el) {
            if (!el || el === document.body || el === document.documentElement) return null;

            if (el.getAttribute('data-testid')) {
                return '[data-testid="' + el.getAttribute('data-testid') + '"]';
            }

            if (el.id && /^[a-zA-Z][a-zA-Z0-9_-]*$/.test(el.id)) {
                var byId = document.querySelectorAll('#' + CSS.escape(el.id));
                if (byId.length === 1) return '#' + CSS.escape(el.id);
            }

            var ariaLabel = el.getAttribute('aria-label');
            if (ariaLabel && ariaLabel.length < 80) {
                var escaped = ariaLabel.replace(/"/g, '\\\\"');
                var candidates = document.querySelectorAll('[aria-label="' + escaped + '"]');
                if (candidates.length === 1) return '[aria-label="' + escaped + '"]';
            }

            var placeholder = el.getAttribute('placeholder');
            if (placeholder && placeholder.length < 80) {
                var escaped2 = placeholder.replace(/"/g, '\\\\"');
                var candidates2 = document.querySelectorAll('[placeholder="' + escaped2 + '"]');
                if (candidates2.length === 1) return '[placeholder="' + escaped2 + '"]';
            }

            var role = el.getAttribute('role');
            if (role) {
                var name = el.getAttribute('aria-label') || el.getAttribute('title') || '';
                if (name && name.length < 80) {
                    var escapedName = name.replace(/"/g, '\\\\"');
                    var sel = '[role="' + role + '"][aria-label="' + escapedName + '"]';
                    if (document.querySelectorAll(sel).length === 1) return sel;
                }
            }

            var tag = el.tagName.toLowerCase();
            if ((tag === 'button' || tag === 'a') && el.textContent) {
                var text = el.textContent.trim();
                if (text.length > 0 && text.length < 60 && !text.includes('\\n')) {
                    var escapedText = text.replace(/'/g, "\\\\'");
                    return "xpath=//" + tag + "[normalize-space(text())='" + escapedText + "']";
                }
            }

            if (tag === 'input' || tag === 'textarea' || tag === 'select') {
                var nameAttr = el.getAttribute('name');
                if (nameAttr) {
                    var sel2 = tag + '[name="' + nameAttr.replace(/"/g, '\\\\"') + '"]';
                    if (document.querySelectorAll(sel2).length === 1) return sel2;
                }
                var type = el.getAttribute('type');
                if (type && tag === 'input') {
                    var labelEl = el.closest('label') || (el.id && document.querySelector('label[for="' + el.id + '"]'));
                    if (labelEl) {
                        var labelText = labelEl.textContent.trim();
                        if (labelText.length > 0 && labelText.length < 60) {
                            var escapedLabel = labelText.replace(/'/g, "\\\\'");
                            return "xpath=//label[contains(normalize-space(.), '" + escapedLabel + "')]/..//input";
                        }
                    }
                    var typeSel = 'input[type="' + type + '"]';
                    if (document.querySelectorAll(typeSel).length === 1) return typeSel;
                }
            }

            var parent = el.parentElement;
            if (parent) {
                var siblings = Array.from(parent.children).filter(function(c) { return c.tagName === el.tagName; });
                if (siblings.length > 1) {
                    var idx = siblings.indexOf(el);
                    var parentSel = bestSelector(parent);
                    if (parentSel && parentSel !== tag) {
                        return parentSel + ' > ' + tag + ':nth-child(' + (Array.from(parent.children).indexOf(el) + 1) + ')';
                    }
                }
            }

            return tag;
        }

        function showHighlight(el) {
            createOverlay();
            if (!el) {
                _highlightOverlay.style.display = 'none';
                _selectorLabel.style.display = 'none';
                _highlightEl = null;
                return;
            }
            var rect = el.getBoundingClientRect();
            _highlightOverlay.style.left = rect.left + 'px';
            _highlightOverlay.style.top = rect.top + 'px';
            _highlightOverlay.style.width = rect.width + 'px';
            _highlightOverlay.style.height = rect.height + 'px';
            _highlightOverlay.style.display = 'block';

            var sel = bestSelector(el);
            if (sel) {
                _selectorLabel.textContent = sel;
                _selectorLabel.style.left = Math.min(rect.left, window.innerWidth - 360) + 'px';
                _selectorLabel.style.top = Math.max(0, rect.top - 28) + 'px';
                _selectorLabel.style.display = 'block';
            }
            _highlightEl = el;
        }

        document.addEventListener('mouseover', function(e) {
            if (_mode === 'recording' && !_recording) return;
            var el = e.target;
            if (el.id === '__pw_highlight' || el.id === '__pw_label') return;
            showHighlight(el);
            var sel = bestSelector(el);
            if (sel) {
                window.webkit.messageHandlers.codegenHover.postMessage({selector: sel});
            }
        }, true);

        document.addEventListener('mouseout', function(e) {
            showHighlight(null);
        }, true);

        document.addEventListener('click', function(e) {
            var el = e.target;
            if (el.id === '__pw_highlight' || el.id === '__pw_label') return;
            var sel = bestSelector(el);
            if (!sel) return;

            if (_mode === 'pickLocator' || _mode === 'assertVisibility' || _mode === 'assertText') {
                e.preventDefault();
                e.stopPropagation();
                var text = (el.textContent || '').trim().substring(0, 200);
                window.webkit.messageHandlers.codegenPick.postMessage({selector: sel, text: text});
                return;
            }

            if (_mode === 'recording' && _recording) {
                var tag = el.tagName.toLowerCase();
                if (tag === 'input' && (el.type === 'checkbox' || el.type === 'radio')) {
                    window.webkit.messageHandlers.codegenAction.postMessage({
                        kind: el.checked ? 'check' : 'uncheck',
                        selector: sel
                    });
                } else {
                    window.webkit.messageHandlers.codegenAction.postMessage({
                        kind: 'click',
                        selector: sel
                    });
                }
            }
        }, true);

        document.addEventListener('keydown', function(e) {
            if (_mode !== 'recording' || !_recording) return;
            if (e.key === 'Enter') {
                var el = e.target;
                var sel = bestSelector(el);
                if (sel && (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA')) {
                    window.webkit.messageHandlers.codegenAction.postMessage({
                        kind: 'pressEnter',
                        selector: sel
                    });
                }
            }
        }, true);

        document.addEventListener('change', function(e) {
            if (_mode !== 'recording' || !_recording) return;
            var el = e.target;
            var sel = bestSelector(el);
            if (!sel) return;
            var tag = el.tagName.toLowerCase();
            if (tag === 'select') {
                window.webkit.messageHandlers.codegenAction.postMessage({
                    kind: 'select',
                    selector: sel,
                    value: el.value
                });
            } else if (tag === 'input' || tag === 'textarea') {
                if (el.type === 'checkbox' || el.type === 'radio') return;
                window.webkit.messageHandlers.codegenAction.postMessage({
                    kind: 'fill',
                    selector: sel,
                    value: el.value
                });
            }
        }, true);

        var _inputDebounce = {};
        document.addEventListener('input', function(e) {
            if (_mode !== 'recording' || !_recording) return;
            var el = e.target;
            if (el.type === 'checkbox' || el.type === 'radio') return;
            var sel = bestSelector(el);
            if (!sel) return;
            if (_inputDebounce[sel]) clearTimeout(_inputDebounce[sel]);
            _inputDebounce[sel] = setTimeout(function() {
                window.webkit.messageHandlers.codegenAction.postMessage({
                    kind: 'fill',
                    selector: sel,
                    value: el.value
                });
                delete _inputDebounce[sel];
            }, 600);
        }, true);
    })();
    """
}
