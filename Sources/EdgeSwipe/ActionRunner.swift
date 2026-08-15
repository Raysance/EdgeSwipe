import AppKit
import ApplicationServices
import Carbon.HIToolbox
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
        case .missionControl:
            openSystemApp(path: "/System/Applications/Mission Control.app", edge: edge, label: "Mission Control")
        case .appExpose:
            postKey(CGKeyCode(kVK_DownArrow), flags: .maskControl, edge: edge, label: "App Exposé")
        case .showDesktop:
            postKey(CGKeyCode(kVK_F11), flags: [], edge: edge, label: "Show Desktop")
        case .launchpad:
            postKey(CGKeyCode(kVK_F4), flags: [], edge: edge, label: "Launchpad")
        case .notificationCenter:
            toggleNotificationCenter(edge: edge)
        case .lockScreen:
            runShell(#""/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession" -suspend"#, edge: edge, successText: "Lock Screen")
        case .startScreenSaver:
            openSystemApp(path: "/System/Library/CoreServices/ScreenSaverEngine.app", edge: edge, label: "Screen Saver")
        case .runShell:
            runShell(action.payload, edge: edge)
        case .open:
            open(action.payload)
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

    private func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags, edge: Edge, label: String) {
        if !AXIsProcessTrusted() {
            requestAccessibilityPermission()
            showHUD(edge: edge, text: "Allow Accessibility")
            return
        }

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = flags
        keyUp?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        showHUD(edge: edge, text: label)
    }

    private func toggleNotificationCenter(edge: Edge) {
        let script = """
        tell application "System Events"
          try
            tell application process "ControlCenter"
              click menu bar item 1 of menu bar 1
            end tell
          on error
            tell application process "NotificationCenter"
              set frontmost to true
            end tell
          end try
        end tell
        """

        if !AXIsProcessTrusted() {
            requestAccessibilityPermission()
            openSystemApp(path: "/System/Library/CoreServices/NotificationCenter.app", edge: edge, label: "Notification Center")
            return
        }

        runShell("osascript -e " + shellQuoted(script), edge: edge, successText: "Notification Center")
    }

    private func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
