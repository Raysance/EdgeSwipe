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
    case switchApplication

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
            .switchApplication
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
        case .switchApplication: return "Switch App"
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
        case .runShell, .open, .switchApplication:
            return true
        case .disabled, .showHUD, .controlCenter, .lockScreen, .screenshot, .missionControl, .appExpose, .showDesktop, .launchpad, .notificationCenter, .startScreenSaver:
            return false
        }
    }

    var isSelectable: Bool {
        Self.allCases.contains(self)
    }
}

struct EdgeActionSetting: Codable, Sendable {
    var kind: GestureActionKind
    var payload: String

    static let disabled = EdgeActionSetting(kind: .disabled, payload: "")
}

struct AppSettings: Codable, Sendable {
    var config: EdgeGestureConfig
    var actions: [String: EdgeActionSetting]
    var debugLogging: Bool

    static let defaults = AppSettings(
        config: EdgeGestureConfig(),
        actions: [
            Edge.left.rawValue: EdgeActionSetting(kind: .showHUD, payload: ""),
            Edge.top.rawValue: EdgeActionSetting(kind: .showHUD, payload: ""),
            Edge.bottom.rawValue: EdgeActionSetting(kind: .showHUD, payload: ""),
            Edge.right.rawValue: EdgeActionSetting(kind: .disabled, payload: "")
        ],
        debugLogging: false
    )

    func action(for edge: Edge) -> EdgeActionSetting {
        let setting = actions[edge.rawValue] ?? .disabled
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
