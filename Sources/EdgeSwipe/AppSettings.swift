import Foundation
import EdgeSwipeCore

enum GestureActionKind: String, Codable, CaseIterable, Sendable {
    case disabled
    case showHUD
    case missionControl
    case appExpose
    case showDesktop
    case launchpad
    case notificationCenter
    case lockScreen
    case startScreenSaver
    case runShell
    case open

    var displayName: String {
        switch self {
        case .disabled: return "Disabled"
        case .showHUD: return "Show HUD"
        case .missionControl: return "Mission Control"
        case .appExpose: return "App Exposé"
        case .showDesktop: return "Show Desktop"
        case .launchpad: return "Launchpad"
        case .notificationCenter: return "Notification Center"
        case .lockScreen: return "Lock Screen"
        case .startScreenSaver: return "Start Screen Saver"
        case .runShell: return "Run Shell"
        case .open: return "Open URL/File"
        }
    }

    var usesPayload: Bool {
        switch self {
        case .runShell, .open:
            return true
        case .disabled, .showHUD, .missionControl, .appExpose, .showDesktop, .launchpad, .notificationCenter, .lockScreen, .startScreenSaver:
            return false
        }
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
        actions[edge.rawValue] ?? .disabled
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
