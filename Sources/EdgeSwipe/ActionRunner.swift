import AppKit
import ApplicationServices
import Foundation
import EdgeSwipeCore

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

@MainActor
final class ActionRunner {
    private var hudWindow: NSWindow?
    private var lastHiddenWindow: FrontWindowInfo?

    func run(trigger: GestureTrigger, action: EdgeActionSetting) {
        switch action.kind {
        case .disabled:
            return
        case .showHUD:
            showHUD(trigger: trigger)
        case .open:
            open(action.payload, trigger: trigger)
        case .runShell:
            runShell(action.payload, trigger: trigger)
        case .controlCenter:
            toggleControlCenter(trigger: trigger)
        case .lockScreen:
            lockScreen(trigger: trigger)
        case .screenshot:
            openSystemApp(path: "/System/Applications/Utilities/Screenshot.app", trigger: trigger, label: "Screenshot")
        case .hideFrontWindow:
            hideFrontWindow(trigger: trigger)
        case .restoreHiddenWindow:
            restoreHiddenWindow(trigger: trigger)
        case .switchApplication:
            switchApplication(action.payload, trigger: trigger)
        case .switchWindow:
            switchWindow(action.payload, trigger: trigger)
        case .missionControl, .appExpose, .showDesktop, .launchpad, .notificationCenter, .startScreenSaver:
            showHUD(trigger: trigger, text: "Action removed")
        }
    }

    func test(trigger: GestureTrigger, action: EdgeActionSetting) {
        if action.kind == .disabled {
            showHUD(trigger: trigger, text: "\(trigger.shortDisplayName) is disabled")
        } else {
            run(trigger: trigger, action: action)
        }
    }

    private func showHUD(trigger: GestureTrigger, text: String? = nil) {
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

        let label = NSTextField(labelWithString: text ?? "EdgeSwipe: \(trigger.displayName)")
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

    private func runShell(_ command: String, trigger: GestureTrigger, successText: String = "Command started") {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showHUD(trigger: trigger, text: "No shell command")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", trimmed]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            showHUD(trigger: trigger, text: successText)
        } catch {
            showHUD(trigger: trigger, text: "Command failed")
            NSLog("EdgeSwipe: shell action failed: \(error)")
        }
    }

    private func open(_ target: String, trigger: GestureTrigger) {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showHUD(trigger: trigger, text: "No URL or file")
            return
        }

        if let url = URL(string: trimmed), url.scheme != nil {
            NSWorkspace.shared.open(url)
            return
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath))
    }

    private func openSystemApp(path: String, trigger: GestureTrigger, label: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            showHUD(trigger: trigger, text: "\(label) unavailable")
            return
        }

        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            Task { @MainActor in
                if let error {
                    self?.showHUD(trigger: trigger, text: "\(label) failed")
                    NSLog("EdgeSwipe: failed to open \(label): \(error)")
                } else {
                    self?.showHUD(trigger: trigger, text: label)
                }
            }
        }
    }

    private func toggleControlCenter(trigger: GestureTrigger) {
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
            noteMissingAccessibility(trigger: trigger)
            return
        }

        runShell("osascript -e " + shellQuoted(script), trigger: trigger, successText: "Control Center")
    }

    private typealias SACLockScreenImmediate = @convention(c) () -> Void

    private func lockScreen(trigger: GestureTrigger) {
        if callSACLockScreenImmediate() {
            showHUD(trigger: trigger, text: "Lock Screen")
            return
        }

        runShell("/usr/bin/pmset displaysleepnow", trigger: trigger, successText: "Display Sleep")
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

    private func switchApplication(_ target: String, trigger: GestureTrigger) {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showHUD(trigger: trigger, text: "No app target")
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
            showHUD(trigger: trigger, text: "App not running")
            return
        }

        if AXIsProcessTrusted() {
            restoreMinimizedWindows(for: runningApp)
        } else {
            noteMissingAccessibility(trigger: trigger)
        }

        runningApp.unhide()
        runningApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        showHUD(trigger: trigger, text: runningApp.localizedName ?? "Switch App")
    }

    private func switchWindow(_ payload: String, trigger: GestureTrigger) {
        guard AXIsProcessTrusted() else {
            noteMissingAccessibility(trigger: trigger)
            return
        }

        guard let target = WindowActionTarget.parse(payload) else {
            showHUD(trigger: trigger, text: "No window target")
            return
        }

        guard let runningApp = runningApplication(for: target) else {
            showHUD(trigger: trigger, text: "App not running")
            return
        }

        let axApp = AXUIElementCreateApplication(runningApp.processIdentifier)
        AXUIElementSetAttributeValue(axApp, kAXHiddenAttribute as CFString, kCFBooleanFalse)
        runningApp.unhide()
        runningApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])

        guard let window = matchingWindow(in: axApp, target: target) else {
            showHUD(trigger: trigger, text: "Window not found")
            return
        }

        restoreMinimizedWindow(window)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, window)
        showHUD(trigger: trigger, text: target.title.isEmpty ? target.appName : target.title)
    }

    private func runningApplication(for target: WindowActionTarget) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { app in
            app.bundleIdentifier == target.bundleIdentifier
        } ?? NSRunningApplication(processIdentifier: pid_t(target.processIdentifier))
    }

    private func hideFrontWindow(trigger: GestureTrigger) {
        guard AXIsProcessTrusted() else {
            noteMissingAccessibility(trigger: trigger)
            return
        }

        guard let windowInfo = frontWindowInfoOnActiveScreen() else {
            showHUD(trigger: trigger, text: "No window found")
            return
        }

        let axApp = AXUIElementCreateApplication(windowInfo.processIdentifier)
        let result = AXUIElementSetAttributeValue(axApp, kAXHiddenAttribute as CFString, kCFBooleanTrue)
        lastHiddenWindow = windowInfo
        if result == .success {
            showHUD(trigger: trigger, text: "Window Hidden")
        } else {
            lastHiddenWindow = nil
            showHUD(trigger: trigger, text: "Hide failed")
            NSLog("EdgeSwipe: failed to hide app for window \(windowInfo.windowID): \(result.rawValue)")
        }
    }

    private func restoreHiddenWindow(trigger: GestureTrigger) {
        guard let windowInfo = lastHiddenWindow else {
            showHUD(trigger: trigger, text: "No hidden window")
            return
        }

        guard let runningApp = NSRunningApplication(processIdentifier: windowInfo.processIdentifier) else {
            lastHiddenWindow = nil
            showHUD(trigger: trigger, text: "App unavailable")
            return
        }

        guard AXIsProcessTrusted() else {
            noteMissingAccessibility(trigger: trigger)
            return
        }

        let axApp = AXUIElementCreateApplication(windowInfo.processIdentifier)
        let result = AXUIElementSetAttributeValue(axApp, kAXHiddenAttribute as CFString, kCFBooleanFalse)
        if result != .success {
            showHUD(trigger: trigger, text: "Restore failed")
            NSLog("EdgeSwipe: failed to restore hidden app for window \(windowInfo.windowID): \(result.rawValue)")
            return
        }

        runningApp.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        if let window = matchingWindow(in: axApp, windowInfo: windowInfo) {
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, window)
        }

        lastHiddenWindow = nil
        showHUD(trigger: trigger, text: runningApp.localizedName ?? "Window Restored")
    }

    private struct FrontWindowInfo {
        let processIdentifier: pid_t
        let windowID: CGWindowID
        let title: String?
        let bounds: CGRect
    }

    private func frontWindowInfoOnActiveScreen() -> FrontWindowInfo? {
        guard let activeScreenBounds = activeScreenBounds(),
              let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else {
            return nil
        }

        let ownProcessIdentifier = NSRunningApplication.current.processIdentifier

        for info in windowList {
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let processIdentifier = info[kCGWindowOwnerPID as String] as? pid_t,
                  processIdentifier != ownProcessIdentifier,
                  let windowIDNumber = info[kCGWindowNumber as String] as? NSNumber,
                  let boundsDictionary = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  bounds.intersects(activeScreenBounds)
            else {
                continue
            }

            let title = info[kCGWindowName as String] as? String
            return FrontWindowInfo(
                processIdentifier: processIdentifier,
                windowID: CGWindowID(windowIDNumber.uint32Value),
                title: title?.isEmpty == true ? nil : title,
                bounds: bounds
            )
        }

        return nil
    }

    private func activeScreenBounds() -> CGRect? {
        let screen = screenContainingMouse() ?? NSScreen.main
        guard let displayID = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
            return screen?.frame
        }

        return CGDisplayBounds(displayID)
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }

    private func matchingWindow(in axApp: AXUIElement, windowInfo: FrontWindowInfo) -> AXUIElement? {
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement]
        else {
            return nil
        }

        let titledMatch = windows.first { window in
            guard let expectedTitle = windowInfo.title,
                  let title = axStringAttribute(kAXTitleAttribute, from: window)
            else {
                return false
            }

            return title == expectedTitle && windowFrame(window).map { $0.intersects(windowInfo.bounds) } == true
        }

        if let titledMatch {
            return titledMatch
        }

        return windows.first { window in
            windowFrame(window).map { $0.intersects(windowInfo.bounds) } == true
        }
    }

    private func matchingWindow(in axApp: AXUIElement, target: WindowActionTarget) -> AXUIElement? {
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement]
        else {
            return nil
        }

        if let window = windows.first(where: { axWindowID($0) == target.windowID }) {
            return window
        }

        if !target.title.isEmpty,
           let window = windows.first(where: { axStringAttribute(kAXTitleAttribute, from: $0) == target.title })
        {
            return window
        }

        return windows.first
    }

    private func axWindowID(_ window: AXUIElement) -> UInt32? {
        var id = CGWindowID(0)
        guard _AXUIElementGetWindow(window, &id) == .success else {
            return nil
        }

        return id
    }

    private func axStringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return value as? String
    }

    private func windowFrame(_ window: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let position = positionValue,
              let size = sizeValue
        else {
            return nil
        }

        guard CFGetTypeID(position) == AXValueGetTypeID(),
              CFGetTypeID(size) == AXValueGetTypeID()
        else {
            return nil
        }

        let positionAXValue = position as! AXValue
        let sizeAXValue = size as! AXValue
        var point = CGPoint.zero
        var windowSize = CGSize.zero
        guard AXValueGetValue(positionAXValue, .cgPoint, &point),
              AXValueGetValue(sizeAXValue, .cgSize, &windowSize)
        else {
            return nil
        }

        return CGRect(origin: point, size: windowSize)
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

    @discardableResult
    private func restoreMinimizedWindow(_ window: AXUIElement) -> Bool {
        var minimizedValue: CFTypeRef?
        let isMinimized = AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue) == .success &&
            (minimizedValue as? Bool == true)

        guard isMinimized else {
            return false
        }

        return AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success
    }

    private func noteMissingAccessibility(trigger: GestureTrigger) {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": false] as CFDictionary)
        showHUD(trigger: trigger, text: "Accessibility Needed")
    }

    private func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
