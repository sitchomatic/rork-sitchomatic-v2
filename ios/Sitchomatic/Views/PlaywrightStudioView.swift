import SwiftUI
import WebKit

struct PlaywrightStudioView: View {
    @State private var session = RecordingSession()
    @State private var urlInput: String = "https://example.com"
    @State private var currentURL: String = ""
    @State private var selectedPanel: CodegenPanel = .actions
    @State private var showCodeSheet: Bool = false
    @State private var copiedToast: Bool = false
    @State private var webViewRef: WKWebView?

    private let darkBg = Color(red: 0.06, green: 0.06, blue: 0.08)
    private let cardBg = Color.white.opacity(0.05)
    private let borderColor = Color.white.opacity(0.06)

    var body: some View {
        VStack(spacing: 0) {
            recorderToolbar
            urlBar
            browserPreview
            modeToolbar
            bottomPanel
        }
        .background(darkBg)
        .navigationTitle("Codegen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                recordingIndicator
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showCodeSheet = true
                    } label: {
                        Label("View Generated Code", systemImage: "doc.text")
                    }
                    .disabled(session.actions.isEmpty)

                    Button {
                        copyCode()
                    } label: {
                        Label("Copy Code", systemImage: "doc.on.clipboard")
                    }
                    .disabled(session.actions.isEmpty)

                    Divider()

                    Button(role: .destructive) {
                        session.clearActions()
                    } label: {
                        Label("Clear All Actions", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.purple)
                }
            }
        }
        .sheet(isPresented: $showCodeSheet) {
            codeSheet
        }
        .overlay(alignment: .top) {
            if copiedToast {
                Text("Copied to Clipboard")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.purple)
                    .clipShape(.capsule)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 8)
            }
        }
        .animation(.spring(duration: 0.3), value: copiedToast)
        .safeAreaInset(edge: .top) {
            UnifiedIPBannerView()
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
        }
    }

    // MARK: - Recording Indicator

    @ViewBuilder
    private var recordingIndicator: some View {
        HStack(spacing: 6) {
            if session.isRecording && !session.isPaused {
                Circle()
                    .fill(.red)
                    .frame(width: 8, height: 8)
                    .shadow(color: .red.opacity(0.6), radius: 4)
                Text("REC")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.red)
            } else if session.isPaused {
                Image(systemName: "pause.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
                Text("PAUSED")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.orange)
            } else {
                Circle()
                    .fill(.white.opacity(0.15))
                    .frame(width: 8, height: 8)
                Text("IDLE")
                    .font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }

            if !session.actions.isEmpty {
                Text("·")
                    .foregroundStyle(.white.opacity(0.15))
                Text("\(session.actionCount)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.purple)
            }
        }
    }

    // MARK: - Recorder Toolbar (Record / Pause / Stop / Clear)

    @ViewBuilder
    private var recorderToolbar: some View {
        HStack(spacing: 12) {
            if !session.isRecording {
                Button {
                    session.startRecording()
                    session.mode = .recording
                    if !urlInput.isEmpty {
                        session.addNavigationAction(url: urlInput)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.red)
                            .frame(width: 10, height: 10)
                        Text("Record")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.2))
                    .clipShape(.capsule)
                    .overlay(Capsule().strokeBorder(Color.red.opacity(0.4), lineWidth: 1))
                }
            } else {
                if session.isPaused {
                    Button {
                        session.resumeRecording()
                    } label: {
                        toolbarPill(icon: "play.fill", label: "Resume", color: .green)
                    }
                } else {
                    Button {
                        session.pauseRecording()
                    } label: {
                        toolbarPill(icon: "pause.fill", label: "Pause", color: .orange)
                    }
                }

                Button {
                    session.stopRecording()
                } label: {
                    toolbarPill(icon: "stop.fill", label: "Stop", color: .red)
                }
            }

            Spacer()

            if !session.actions.isEmpty {
                Button {
                    copyCode()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.purple)
                        .frame(width: 32, height: 32)
                        .background(Color.purple.opacity(0.12))
                        .clipShape(Circle())
                }

                Text("\(session.actionCount) steps")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func toolbarPill(icon: String, label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(color.opacity(0.12))
        .clipShape(.capsule)
        .overlay(Capsule().strokeBorder(color.opacity(0.3), lineWidth: 1))
    }

    // MARK: - URL Bar

    @ViewBuilder
    private var urlBar: some View {
        HStack(spacing: 8) {
            Button {
                webViewRef?.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .disabled(!(webViewRef?.canGoBack ?? false))

            Button {
                webViewRef?.goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.3))
            }
            .disabled(!(webViewRef?.canGoForward ?? false))

            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(currentURL.hasPrefix("https") ? .green.opacity(0.7) : .white.opacity(0.2))

                TextField("Enter URL...", text: $urlInput)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.white)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { navigateToURL() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.04))
            .clipShape(.rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: 1)
            )

            Button {
                navigateToURL()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.purple)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    // MARK: - Browser Preview (Live WKWebView)

    @ViewBuilder
    private var browserPreview: some View {
        ZStack {
            CodegenWebView(
                session: session,
                urlString: urlInput,
                onNavigated: { url in
                    currentURL = url
                    if !url.isEmpty, url != "about:blank" {
                        urlInput = url
                    }
                },
                onWebViewCreated: { wv in
                    webViewRef = wv
                }
            )
            .clipShape(.rect(cornerRadius: 2))

            if session.mode != .recording {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        modeBadge
                            .padding(10)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .overlay(
            Rectangle()
                .strokeBorder(
                    session.isRecording && !session.isPaused
                        ? Color.red.opacity(0.4)
                        : session.mode == .pickLocator
                            ? Color.cyan.opacity(0.4)
                            : borderColor,
                    lineWidth: session.isRecording && !session.isPaused ? 2 : 1
                )
        )
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var modeBadge: some View {
        let modeColor: Color = switch session.mode {
        case .recording: .red
        case .pickLocator: .cyan
        case .assertVisibility: .yellow
        case .assertText: .orange
        }

        HStack(spacing: 5) {
            Image(systemName: session.mode.iconName)
                .font(.system(size: 10, weight: .bold))
            Text(session.mode.displayName)
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .textCase(.uppercase)
        }
        .foregroundStyle(modeColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(.capsule)
        .overlay(Capsule().strokeBorder(modeColor.opacity(0.5), lineWidth: 1))
    }

    // MARK: - Mode Toolbar (Recording / Pick Locator / Assert)

    @ViewBuilder
    private var modeToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(RecorderMode.allCases, id: \.self) { mode in
                    Button {
                        session.mode = mode
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: mode.iconName)
                                .font(.system(size: 10, weight: .bold))
                            Text(mode.displayName)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                        }
                        .foregroundStyle(session.mode == mode ? .white : .white.opacity(0.35))
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(session.mode == mode ? modeButtonColor(mode).opacity(0.25) : Color.white.opacity(0.04))
                        .clipShape(.capsule)
                        .overlay(
                            Capsule().strokeBorder(
                                session.mode == mode ? modeButtonColor(mode).opacity(0.5) : Color.white.opacity(0.06),
                                lineWidth: 1
                            )
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .contentMargins(.horizontal, 0)
        .padding(.vertical, 8)
        .background(Color(red: 0.07, green: 0.07, blue: 0.09))
        .overlay(alignment: .bottom) {
            Rectangle().fill(borderColor).frame(height: 1)
        }
    }

    private func modeButtonColor(_ mode: RecorderMode) -> Color {
        switch mode {
        case .recording: .red
        case .pickLocator: .cyan
        case .assertVisibility: .yellow
        case .assertText: .orange
        }
    }

    // MARK: - Bottom Panel

    @ViewBuilder
    private var bottomPanel: some View {
        VStack(spacing: 0) {
            panelTabs

            Group {
                switch selectedPanel {
                case .actions:
                    actionsPanel
                case .locator:
                    locatorPanel
                case .code:
                    codePreviewPanel
                }
            }
            .frame(height: 180)
        }
    }

    @ViewBuilder
    private var panelTabs: some View {
        HStack(spacing: 0) {
            ForEach(CodegenPanel.allCases, id: \.self) { panel in
                Button {
                    selectedPanel = panel
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: panel.iconName)
                            .font(.system(size: 10, weight: .semibold))
                        Text(panel.title)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .textCase(.uppercase)
                            .tracking(0.3)
                    }
                    .foregroundStyle(selectedPanel == panel ? .purple : .white.opacity(0.25))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(selectedPanel == panel ? Color.purple.opacity(0.08) : .clear)
                    .overlay(alignment: .bottom) {
                        if selectedPanel == panel {
                            Rectangle()
                                .fill(Color.purple)
                                .frame(height: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .background(cardBg)
    }

    // MARK: - Actions Panel (Recorded Steps)

    @ViewBuilder
    private var actionsPanel: some View {
        if session.actions.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "record.circle")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.1))
                Text("Start recording to capture actions")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(session.actions.enumerated()), id: \.element.id) { index, action in
                            HStack(spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.15))
                                    .frame(width: 20, alignment: .trailing)

                                Image(systemName: action.iconName)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(actionColor(action.kind))
                                    .frame(width: 16)

                                Text(action.displayDescription)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .lineLimit(1)

                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(index % 2 == 0 ? Color.clear : Color.white.opacity(0.015))
                            .id(action.id)
                        }
                    }
                }
                .onChange(of: session.actions.count) { _, _ in
                    if let last = session.actions.last {
                        withAnimation {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func actionColor(_ kind: ActionKind) -> Color {
        switch kind {
        case .navigation: .blue
        case .click: .purple
        case .fill: .green
        case .check, .uncheck: .orange
        case .select: .cyan
        case .pressEnter: .indigo
        case .assertVisible, .assertText, .assertValue: .yellow
        case .waitForTimeout: .gray
        }
    }

    // MARK: - Locator Panel

    @ViewBuilder
    private var locatorPanel: some View {
        VStack(spacing: 12) {
            if let picked = session.pickedLocator {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("PICKED LOCATOR")
                            .font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.cyan)
                            .tracking(1)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = picked
                            showCopiedToast()
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.cyan)
                        }
                    }

                    Text(picked)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.cyan.opacity(0.06))
                        .clipShape(.rect(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.cyan.opacity(0.2), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 14)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "target")
                        .font(.system(size: 28))
                        .foregroundStyle(.white.opacity(0.1))
                    Text("Switch to Pick Locator mode and click an element")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.2))
                        .multilineTextAlignment(.center)
                }
            }

            if let highlighted = session.highlightedSelector {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.purple.opacity(0.5))
                        .frame(width: 6, height: 6)
                    Text(highlighted)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                }
                .padding(.horizontal, 14)
            }

            Spacer()
        }
        .padding(.top, 12)
    }

    // MARK: - Code Preview Panel

    @ViewBuilder
    private var codePreviewPanel: some View {
        if session.actions.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "curlybraces")
                    .font(.system(size: 28))
                    .foregroundStyle(.white.opacity(0.1))
                Text("Generated code will appear here")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                Text(session.generatedCode)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.green.opacity(0.85))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Code Sheet

    @ViewBuilder
    private var codeSheet: some View {
        NavigationStack {
            ScrollView {
                Text(session.generatedCode)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.green)
                    .textSelection(.enabled)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(red: 0.08, green: 0.08, blue: 0.1))
            .navigationTitle("Generated Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        showCodeSheet = false
                    }
                    .foregroundStyle(.purple)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        copyCode()
                        showCodeSheet = false
                    } label: {
                        Label("Copy", systemImage: "doc.on.clipboard")
                    }
                    .foregroundStyle(.purple)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Actions

    private func navigateToURL() {
        guard !urlInput.isEmpty else { return }
        var normalizedURL = urlInput
        if !normalizedURL.hasPrefix("http://") && !normalizedURL.hasPrefix("https://") {
            normalizedURL = "https://" + normalizedURL
            urlInput = normalizedURL
        }

        if let url = URL(string: normalizedURL) {
            webViewRef?.load(URLRequest(url: url))
        }

        if session.isRecording {
            session.addNavigationAction(url: normalizedURL)
        }
    }

    private func copyCode() {
        UIPasteboard.general.string = session.generatedCode
        showCopiedToast()
    }

    private func showCopiedToast() {
        copiedToast = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copiedToast = false
        }
    }
}

// MARK: - Panel Enum

private enum CodegenPanel: String, CaseIterable {
    case actions
    case locator
    case code

    var title: String {
        switch self {
        case .actions: "Actions"
        case .locator: "Locator"
        case .code: "Code"
        }
    }

    var iconName: String {
        switch self {
        case .actions: "list.bullet"
        case .locator: "target"
        case .code: "curlybraces"
        }
    }
}
