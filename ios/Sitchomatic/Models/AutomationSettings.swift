import Foundation
import CoreGraphics

nonisolated struct AutomationSettings: Codable, Sendable {

    var stealth: StealthSettings
    var viewport: ViewportSettings
    var screenshot: ScreenshotSettings
    var playwright: PlaywrightSettings

    static let `default` = AutomationSettings(
        stealth: .default,
        viewport: .default,
        screenshot: .default,
        playwright: .default
    )

    private static let storageKey = "AutomationSettings.v2"

    static func load() -> AutomationSettings {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(AutomationSettings.self, from: data) else {
            return .default
        }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

nonisolated struct StealthSettings: Codable, Sendable, Equatable {
    var spoofWebGL: Bool
    var spoofCanvas: Bool
    var spoofAudioContext: Bool
    var maskWebRTC: Bool
    var randomizeNavigatorProperties: Bool
    var blockCDPDetection: Bool

    static let `default` = StealthSettings(
        spoofWebGL: true,
        spoofCanvas: true,
        spoofAudioContext: true,
        maskWebRTC: true,
        randomizeNavigatorProperties: true,
        blockCDPDetection: true
    )
}

nonisolated struct ViewportSettings: Codable, Sendable, Equatable {
    var width: Int
    var height: Int
    var deviceScaleFactor: Double
    var isMobile: Bool

    static let `default` = ViewportSettings(
        width: 390,
        height: 844,
        deviceScaleFactor: 3.0,
        isMobile: true
    )

    var cgSize: CGSize {
        CGSize(width: width, height: height)
    }
}

nonisolated struct ScreenshotSettings: Codable, Sendable, Equatable {
    var captureOnNavigation: Bool
    var captureOnError: Bool
    var deduplicationEnabled: Bool
    var maxStoredScreenshots: Int

    static let `default` = ScreenshotSettings(
        captureOnNavigation: false,
        captureOnError: true,
        deduplicationEnabled: true,
        maxStoredScreenshots: 50
    )
}

nonisolated struct PlaywrightSettings: Codable, Sendable, Equatable {
    var usePlaywrightEngine: Bool
    var defaultTimeout: TimeInterval
    var autoWaitEnabled: Bool
    var tracingEnabledByDefault: Bool
    var maxConcurrentPages: Int

    static let `default` = PlaywrightSettings(
        usePlaywrightEngine: true,
        defaultTimeout: 30.0,
        autoWaitEnabled: true,
        tracingEnabledByDefault: false,
        maxConcurrentPages: 6
    )
}
