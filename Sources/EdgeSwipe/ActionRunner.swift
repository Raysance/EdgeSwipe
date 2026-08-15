import AppKit
import ApplicationServices
import Foundation
import EdgeSwipeCore

@MainActor
final class ActionRunner {
    private var hudWindow: NSWindow?

    func run(edge: Edge, action: EdgeActionSetting) {
        switch action.kind {
        case .disabled:
            return
        case .showHUD:
            showHUD(edge: edge)
        case .open:
            open(action.payload)
        case .runShell:
            runShell(action.payload, edge: edge)
        case .controlCenter:
            toggleControlCenter(edge: edge)
        case .lockScreen:
            lockScreen(edge: edge)
        case .screenshot:
            openSystemApp(path: "/System/Applications/Utilities/Screenshot.app", edge: edge, label: "Screenshot")
        case .switchApplication:
            switchApplication(action.payload, edge: edge)
        case .missionControl, .appExpose, .showDesktop, .launchpad, .notificationCenter, .startScreenSaver:
            showHUD(edge: edge, text: "Action removed")
        }
    }

    func test(edge: Edge, action: EdgeActionSetting) {
        if action.kind == .disabled {
            showHUD(edge: edge, text: "\(edge.displayName) is disabled")
        } else {
            run(edge: edge, action: action)
        }
    }

    private func showHUD(edge: Edge, text: String? = nil) {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 900, height: 600)
        let width: CGFloat = 280
        let height: CGFloat = 96
        let frame = NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.midY - height / 2,
            width: width,
            height: height
        )

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.ignoresMouseEvents = true

        let label = NSTextField(labelWithString: text ?? "EdgeSwipe: \(edge.displayName)")
        label.font = .systemFont(ofSize: 22, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let content = NSVisualEffectView()
        content.material = .hudWindow
        content.blendingMode = .behindWindow
        content.state = .active
        content.wantsLayer = true
        content.layer?.cornerRadius = 14
        content.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(label)

        let root = NSView()
        root.addSubview(content)
        panel.contentView = root

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            label.centerYAnchor.constraint(equalTo: content.centerYAnchor)
        ])

        hudWindow?.orderOut(nil)
        hudWindow = panel
        panel.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self, weak panel] in
            panel?.orderOut(nil)
            if self?.hudWindow === panel {
                self?.hudWindow = nil
            }
        }
    }

    private func runShell(_ command: String, edge: Edge, successText: String = "Command started") {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showHUD(edge: edge, text: "No shell command")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", trimmed]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            showHUD(edge: edge, text: successText)
        } catch {
            showHUD(edge: edge, text: "Command failed")
            NSLog("EdgeSwipe: shell action failed: \(error)")
        }
    }

    private func open(_ target: String) {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showHUD(edge: .left, text: "No URL or file")
            return
        }

        if let url = URL(string: trimmed), url.scheme != nil {
            NSWorkspace.shared.open(url)
            return
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath))
    }

    private func openSystemApp(path: String, edge: Edge, label: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            showHUD(edge: edge, text: "\(label) unavailable")
            return
        }

        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            Task { @MainActor in
                if let error {
                    self?.showHUD(edge: edge, text: "\(label) failed")
                    NSLog("EdgeSwipe: failed to open \(label): \(error)")
                } else {
                    self?.showHUD(edge: edge, text: label)
                }
            }
        }
    }

    private func toggleControlCenter(edge: Edge) {
        let script = """
        tell application "System Events"
          tell application process "SystemUIServer"
            set controlCenterItem to missing value
            repeat with itemRef in menu bar items of menu bar 1
              try
                set itemIdentifier to value of attribute "AXIdentifier" of itemRef
                if itemIdentifier is "com.apple.controlcenter" then
                  set controlCenterItem to itemRef
                  exit repeat
                end if
              end try
            end repeat
            if controlCenterItem is missing value then error "Control Center menu bar item not found"
            click controlCenterItem
          end tell
        end tell
        """

        if !AXIsProcessTrusted() {
            requestAccessibilityPermission()
            showHUD(edge: edge, text: "Allow Accessibility")
            return
        }

        runShell("osascript -e " + shellQuoted(script), edge: edge, successText: "Control Center")
    }

    private typealias SACLockScreenImmediate = @convention(c) () -> Void

    private func lockScreen(edge: Edge) {
        if callSACLockScreenImmediate() {
            showHUD(edge: edge, text: "Lock Screen")
            return
        }

        runShell("/usr/bin/pmset displaysleepnow", edge: edge, successText: "Display Sleep")
    }

    private func callSACLockScreenImmediate() -> Bool {
        let path = "/System/Library/PrivateFrameworks/login.framework/login"
        guard let handle = dlopen(path, RTLD_NOW), let symbol = dlsym(handle, "SACLockScreenImmediate") else {
            return false
        }

        let function = unsafeBitCast(symbol, to: SACLockScreenImmediate.self)
        function()
        return true
    }

    private func switchApplication(_ target: String, edge: Edge) {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showHUD(edge: edge, text: "No app target")
            return
        }

        let lowercasedTarget = trimmed.lowercased()
        let runningApp = NSWorkspace.shared.runningApplications.first { app in
            app.localizedName?.lowercased() == lowercasedTarget ||
                app.bundleIdentifier?.lowercased() == lowercasedTarget
        } ?? NSWorkspace.shared.runningApplications.first { app in
            app.localizedName?.lowercased().contains(lowercasedTarget) == true ||
                app.bundleIdentifier?.lowercased().contains(lowercasedTarget) == true
        }

        guard let runningApp else {
            showHUD(edge: edge, text: "App not running")
            return
        }

        if AXIsProcessTrusted() {
            restoreMinimizedWindows(for: runningApp)
        } else {
            requestAccessibilityPermission()
        }

        runningApp.unhide()
        runningApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        showHUD(edge: edge, text: runningApp.localizedName ?? "Switch App")
    }

    @discardableResult
    private func restoreMinimizedWindows(for app: NSRunningApplication) -> Bool {
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement]
        else {
            return false
        }

        var restored = false
        for window in windows {
            var minimizedValue: CFTypeRef?
            let isMinimized = AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue) == .success &&
                (minimizedValue as? Bool == true)

            if isMinimized {
                let result = AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                restored = restored || result == .success
            }

            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }

        return restored
    }

    private func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
