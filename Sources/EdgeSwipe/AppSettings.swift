import Foundation
import EdgeSwipeCore

enum GestureActionKind: String, Codable, CaseIterable, Sendable {
    case disabled
    case showHUD
    case open
    case runShell
    case controlCenter
    case lockScreen
    case screenshot
    case hideFrontWindow
    case restoreHiddenWindow
    case switchApplication
    case switchWindow

    case missionControl
    case appExpose
    case showDesktop
    case launchpad
    case notificationCenter
    case startScreenSaver

    static var allCases: [GestureActionKind] {
        [
            .disabled,
            .showHUD,
            .open,
            .runShell,
            .controlCenter,
            .lockScreen,
            .screenshot,
            .hideFrontWindow,
            .restoreHiddenWindow,
            .switchApplication,
            .switchWindow
        ]
    }

    var displayName: String {
        switch self {
        case .disabled: return "Disabled"
        case .showHUD: return "Show HUD"
        case .open: return "Open URL/File"
        case .runShell: return "Run Shell"
        case .controlCenter: return "Control Center"
        case .lockScreen: return "Lock Screen"
        case .screenshot: return "Screenshot"
        case .hideFrontWindow: return "Hide Front Window"
        case .restoreHiddenWindow: return "Restore Hidden Window"
        case .switchApplication: return "Switch App"
        case .switchWindow: return "Switch Window"
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .showDesktop: return "Show Desktop"
        case .launchpad: return "Launchpad"
        case .notificationCenter: return "Notification Center"
        case .startScreenSaver: return "Start Screen Saver"
        }
    }

    var usesPayload: Bool {
        switch self {
        case .runShell, .open, .switchApplication, .switchWindow:
            return true
        case .disabled, .showHUD, .controlCenter, .lockScreen, .screenshot, .hideFrontWindow, .restoreHiddenWindow, .missionControl, .appExpose, .showDesktop, .launchpad, .notificationCenter, .startScreenSaver:
            return false
        }
    }

    var isSelectable: Bool {
        Self.allCases.contains(self)
    }
}

struct WindowActionTarget: Codable, Sendable {
    var bundleIdentifier: String
    var appName: String
    var title: String
    var windowID: UInt32
    var processIdentifier: Int32

    var payload: String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8)
        else {
            return ""
        }

        return string
    }

    static func parse(_ payload: String) -> WindowActionTarget? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else {
            return nil
        }

        return try? JSONDecoder().decode(WindowActionTarget.self, from: data)
    }
}

struct EdgeActionSetting: Codable, Sendable {
    var kind: GestureActionKind
    var payload: String

    static let disabled = EdgeActionSetting(kind: .disabled, payload: "")
}

struct AppSettings: Codable, Sendable {
    var config: EdgeGestureConfig
    var cornerConfig: EdgeGestureConfig
    var actions: [String: EdgeActionSetting]
    var debugLogging: Bool

    static let defaults = AppSettings(
        config: EdgeGestureConfig(
            edgeBand: 0.05,
            minTravel: 0.17,
            maxCrossAxisTravel: 0.20,
            cooldown: 0.28
        ),
        cornerConfig: EdgeGestureConfig(
            edgeBand: 0.059375260031434916,
            minTravel: 0.14012289663461538,
            maxCrossAxisTravel: 0.20,
            cooldown: 0.28
        ),
        actions: [
            GestureTrigger.left.rawValue: EdgeActionSetting(kind: .switchApplication, payload: "com.google.Chrome"),
            GestureTrigger.top.rawValue: EdgeActionSetting(kind: .switchApplication, payload: "com.openai.codex"),
            GestureTrigger.bottom.rawValue: EdgeActionSetting(kind: .switchApplication, payload: "com.tencent.xinWeChat"),
            GestureTrigger.right.rawValue: EdgeActionSetting(kind: .switchApplication, payload: "com.microsoft.VSCode"),
            GestureTrigger.topLeft.rawValue: EdgeActionSetting(kind: .showHUD, payload: ""),
            GestureTrigger.topRight.rawValue: EdgeActionSetting(kind: .hideFrontWindow, payload: ""),
            GestureTrigger.bottomLeft.rawValue: EdgeActionSetting(kind: .restoreHiddenWindow, payload: ""),
            GestureTrigger.bottomRight.rawValue: EdgeActionSetting(kind: .disabled, payload: "")
        ],
        debugLogging: false
    )

    init(config: EdgeGestureConfig, cornerConfig: EdgeGestureConfig, actions: [String: EdgeActionSetting], debugLogging: Bool) {
        self.config = config
        self.cornerConfig = cornerConfig
        self.actions = actions
        self.debugLogging = debugLogging
    }

    private enum CodingKeys: String, CodingKey {
        case config
        case cornerConfig
        case actions
        case debugLogging
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let edgeConfig = try container.decodeIfPresent(EdgeGestureConfig.self, forKey: .config) ?? EdgeGestureConfig()

        self.config = edgeConfig
        self.cornerConfig = try container.decodeIfPresent(EdgeGestureConfig.self, forKey: .cornerConfig) ?? edgeConfig
        self.actions = try container.decodeIfPresent([String: EdgeActionSetting].self, forKey: .actions) ?? Self.defaults.actions
        self.debugLogging = try container.decodeIfPresent(Bool.self, forKey: .debugLogging) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(config, forKey: .config)
        try container.encode(cornerConfig, forKey: .cornerConfig)
        try container.encode(actions, forKey: .actions)
        try container.encode(debugLogging, forKey: .debugLogging)
    }

    func action(for trigger: GestureTrigger) -> EdgeActionSetting {
        let setting = actions[trigger.rawValue] ?? .disabled
        return setting.kind.isSelectable ? setting : .disabled
    }
}

final class SettingsStore {
    static let didChange = Notification.Name("EdgeSwipeSettingsDidChange")

    private let defaults: UserDefaults
    private let key = "EdgeSwipe.settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        guard let data = defaults.data(forKey: key) else {
            return .defaults
        }

        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            return .defaults
        }
    }

    func save(_ settings: AppSettings) {
        do {
            let data = try JSONEncoder().encode(settings)
            defaults.set(data, forKey: key)
            NotificationCenter.default.post(name: Self.didChange, object: settings)
        } catch {
            NSLog("EdgeSwipe: failed to save settings: \(error)")
        }
    }
}
