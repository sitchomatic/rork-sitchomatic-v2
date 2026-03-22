import SwiftUI

struct SessionCardView: View {
    let session: ConcurrentSession
    let isExpanded: Bool
    let onTap: () -> Void

    private let cardBg = Color.white.opacity(0.05)
    private let borderColor = Color.white.opacity(0.06)

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                if isExpanded {
                    expandedContent
                }
            }
            .background(cardBg)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(phaseBorderColor.opacity(0.3), lineWidth: session.phase.isActive ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(phaseGradient)
                    .frame(width: 32, height: 32)
                    .shadow(color: phaseGlowColor.opacity(0.3), radius: 4)

                Image(systemName: session.phase.iconName)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, isActive: session.phase.isActive)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("S\(session.index + 1)")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.white)

                    Text("W\(session.waveIndex + 1)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.25))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.06))
                        .clipShape(.capsule)
                }

                Text(session.phase.displayName)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(phaseTextColor)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if session.totalSteps > 0 {
                    Text("\(session.stepsCompleted)/\(session.totalSteps)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.purple)
                }

                Text(session.elapsedFormatted)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)

        if session.totalSteps > 0 {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.white.opacity(0.03))
                    Rectangle()
                        .fill(progressGradient)
                        .frame(width: geo.size.width * session.progress)
                }
            }
            .frame(height: 2)
        }
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().background(Color.white.opacity(0.04))

            if !session.currentURL.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.blue.opacity(0.6))
                    Text(session.currentURL)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
            }

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: "network")
                        .font(.system(size: 8))
                        .foregroundStyle(.cyan.opacity(0.5))
                    Text(session.proxyInfo)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.cyan.opacity(0.6))
                }

                if let error = session.errorMessage {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.red.opacity(0.7))
                        Text(error)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.red.opacity(0.7))
                            .lineLimit(2)
                    }
                }
            }

            if !session.logEntries.isEmpty {
                let recentLogs = session.logEntries.suffix(4)
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(recentLogs)) { entry in
                        Text(entry.formatted)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(logColor(entry.category).opacity(0.5))
                            .lineLimit(1)
                    }
                }
            }

            if let screenshot = session.lastScreenshot, let uiImage = UIImage(data: screenshot) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 80)
                    .clipShape(.rect(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var phaseGradient: LinearGradient {
        LinearGradient(
            colors: [phaseGlowColor, phaseGlowColor.opacity(0.5)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var progressGradient: LinearGradient {
        LinearGradient(
            colors: [.purple, .cyan],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var phaseGlowColor: Color {
        switch session.phase {
        case .queued: .white.opacity(0.15)
        case .launching, .navigating: .orange
        case .running, .fillingForm, .waitingForElement: .purple
        case .asserting: .yellow
        case .screenshotting: .cyan
        case .succeeded: .green
        case .failed: .red
        case .cancelled: .gray
        }
    }

    private var phaseBorderColor: Color {
        session.phase.isActive ? phaseGlowColor : borderColor
    }

    private var phaseTextColor: Color {
        switch session.phase {
        case .succeeded: .green
        case .failed: .red
        case .cancelled: .gray
        default: phaseGlowColor
        }
    }

    private func logColor(_ category: SessionLogLine.Category) -> Color {
        switch category {
        case .phase: .purple
        case .action: .cyan
        case .network: .blue
        case .error: .red
        case .result: .green
        }
    }
}

struct CompactSessionCard: View {
    let session: ConcurrentSession

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(phaseColor.opacity(0.2))
                    .frame(width: 36, height: 36)

                Image(systemName: session.phase.iconName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(phaseColor)
                    .symbolEffect(.pulse, isActive: session.phase.isActive)
            }

            Text("S\(session.index + 1)")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))

            if session.totalSteps > 0 {
                Text("\(session.stepsCompleted)/\(session.totalSteps)")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.purple.opacity(0.6))
            }
        }
        .frame(width: 56)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.03))
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(phaseColor.opacity(session.phase.isActive ? 0.3 : 0.08), lineWidth: 1)
        )
    }

    private var phaseColor: Color {
        switch session.phase {
        case .queued: .white.opacity(0.2)
        case .launching, .navigating: .orange
        case .running, .fillingForm, .waitingForElement: .purple
        case .asserting: .yellow
        case .screenshotting: .cyan
        case .succeeded: .green
        case .failed: .red
        case .cancelled: .gray
        }
    }
}
