import Foundation
import ServiceManagement

@MainActor
enum LoginItemController {
    static var isSupported: Bool {
        if #available(macOS 13.0, *) {
            return true
        }
        return false
    }

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    static var statusText: String {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled:
                return "Enabled"
            case .notRegistered:
                return "Disabled"
            case .requiresApproval:
                return "Needs approval in Login Items"
            case .notFound:
                return "App bundle not found"
            @unknown default:
                return "Unknown"
            }
        }
        return "Requires macOS 13 or later"
    }

    static func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                try SMAppService.mainApp.unregister()
            }
        }
    }
}
