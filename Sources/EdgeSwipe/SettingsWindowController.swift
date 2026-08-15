import AppKit
import ApplicationServices
import EdgeSwipeCore

@MainActor
final class SettingsWindowController: NSWindowController {
    private let store: SettingsStore
    private let runner: ActionRunner
    private var settings: AppSettings
    private var edgeBandSlider: NSSlider!
    private var minTravelSlider: NSSlider!
    private var crossAxisSlider: NSSlider!
    private var cooldownSlider: NSSlider!
    private var debugCheckbox: NSButton!
    private var edgeRows: [Edge: EdgeActionRow] = [:]
    private var probeView: TrackpadProbeView!

    init(store: SettingsStore, runner: ActionRunner) {
        self.store = store
        self.runner = runner
        self.settings = store.load()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "EdgeSwipe Settings"
        window.center()
        super.init(window: window)
        buildContent()
    }

    required init?(coder: NSCoder) {
        nil
    }

    private func buildContent() {
        guard let window else { return }

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 18
        root.edgeInsets = NSEdgeInsets(top: 22, left: 24, bottom: 22, right: 24)
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "EdgeSwipe")
        title.font = .systemFont(ofSize: 26, weight: .bold)

        let subtitle = NSTextField(wrappingLabelWithString: "Closest-system-style recognizer: exactly two active touches, both beginning in a configurable edge band, moving inward far enough with limited drift.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.preferredMaxLayoutWidth = 700

        root.addArrangedSubview(title)
        root.addArrangedSubview(subtitle)
        root.addArrangedSubview(makeThresholdSection())
        root.addArrangedSubview(makeActionsSection())
        root.addArrangedSubview(makeProbeSection())

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = root
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        window.contentView = scrollView

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 760),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 640)
        ])
    }

    private func makeThresholdSection() -> NSView {
        let stack = sectionStack(title: "Recognition")

        edgeBandSlider = slider(value: settings.config.edgeBand, min: 0.03, max: 0.18)
        minTravelSlider = slider(value: settings.config.minTravel, min: 0.08, max: 0.45)
        crossAxisSlider = slider(value: settings.config.maxCrossAxisTravel, min: 0.04, max: 0.35)
        cooldownSlider = slider(value: settings.config.cooldown, min: 0.1, max: 2.0)

        stack.addArrangedSubview(labeledControl("Edge band", detail: "Start zone near an edge", minLabel: "Tighter edge", maxLabel: "Wider edge", control: edgeBandSlider))
        stack.addArrangedSubview(labeledControl("Inward travel", detail: "Required movement toward center", minLabel: "Short swipe", maxLabel: "Long swipe", control: minTravelSlider))
        stack.addArrangedSubview(labeledControl("Drift limit", detail: "Maximum movement across the wrong axis", minLabel: "Strict line", maxLabel: "Loose line", control: crossAxisSlider))
        stack.addArrangedSubview(labeledControl("Cooldown", detail: "Minimum seconds between triggers", minLabel: "More repeat", maxLabel: "Less repeat", control: cooldownSlider))

        debugCheckbox = NSButton(checkboxWithTitle: "Log raw gesture touch counts to Console", target: self, action: #selector(updateSettingsFromControls))
        debugCheckbox.state = settings.debugLogging ? .on : .off
        stack.addArrangedSubview(debugCheckbox)

        return stack
    }

    private func makeActionsSection() -> NSView {
        let stack = sectionStack(title: "Actions")

        for edge in [Edge.left, .top, .bottom, .right] {
            let row = EdgeActionRow(edge: edge, setting: settings.action(for: edge), target: self, runner: runner)
            edgeRows[edge] = row
            stack.addArrangedSubview(row)
        }

        return stack
    }

    private func makeProbeSection() -> NSView {
        let stack = sectionStack(title: "Live Probe")

        let help = NSTextField(wrappingLabelWithString: "Move two fingers from the left, top, or bottom edge while this window is active. The same recognizer is used here and by the menu-bar monitor.")
        help.textColor = .secondaryLabelColor
        help.font = .systemFont(ofSize: 12)
        help.preferredMaxLayoutWidth = 680

        probeView = TrackpadProbeView(config: settings.config) { [weak self] edge in
            guard let self else { return }
            self.runner.test(edge: edge, action: self.settings.action(for: edge))
        }

        stack.addArrangedSubview(help)
        stack.addArrangedSubview(probeView)
        return stack
    }

    private func sectionStack(title: String) -> NSStackView {
        let outer = NSStackView()
        outer.orientation = .vertical
        outer.alignment = .leading
        outer.spacing = 10
        outer.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 15, weight: .semibold)

        outer.addArrangedSubview(label)
        return outer
    }

    private func labeledControl(_ title: String, detail: String, minLabel: String, maxLabel: String, control: NSControl) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        labels.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)

        let detailLabel = NSTextField(labelWithString: detail)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor

        let range = NSStackView()
        range.orientation = .horizontal
        range.alignment = .centerY
        range.spacing = 8
        range.translatesAutoresizingMaskIntoConstraints = false

        let minText = rangeLabel(minLabel, alignment: .right)
        let maxText = rangeLabel(maxLabel, alignment: .left)

        labels.addArrangedSubview(titleLabel)
        labels.addArrangedSubview(detailLabel)
        range.addArrangedSubview(minText)
        range.addArrangedSubview(control)
        range.addArrangedSubview(maxText)
        row.addArrangedSubview(labels)
        row.addArrangedSubview(range)

        NSLayoutConstraint.activate([
            labels.widthAnchor.constraint(equalToConstant: 190),
            minText.widthAnchor.constraint(equalToConstant: 78),
            control.widthAnchor.constraint(equalToConstant: 285),
            maxText.widthAnchor.constraint(equalToConstant: 78),
            range.widthAnchor.constraint(equalToConstant: 465)
        ])

        return row
    }

    private func rangeLabel(_ text: String, alignment: NSTextAlignment) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private func slider(value: Double, min: Double, max: Double) -> NSSlider {
        let slider = NSSlider(value: value, minValue: min, maxValue: max, target: self, action: #selector(updateSettingsFromControls))
        slider.isContinuous = false
        return slider
    }

    @objc func updateSettingsFromControls() {
        settings.config.edgeBand = edgeBandSlider.doubleValue
        settings.config.minTravel = minTravelSlider.doubleValue
        settings.config.maxCrossAxisTravel = crossAxisSlider.doubleValue
        settings.config.cooldown = cooldownSlider.doubleValue
        settings.debugLogging = debugCheckbox.state == .on

        for (edge, row) in edgeRows {
            settings.actions[edge.rawValue] = row.setting
        }

        probeView.updateConfig(settings.config)
        store.save(settings)
    }
}

@MainActor
final class EdgeActionRow: NSStackView {
    private let edge: Edge
    private let popup: ActionPopUpButton
    private let payload: NSTextField
    private let runner: ActionRunner
    private var selectedKind: GestureActionKind
    private weak var settingsTarget: SettingsWindowController?

    var setting: EdgeActionSetting {
        EdgeActionSetting(kind: selectedKind, payload: payload.stringValue)
    }

    init(edge: Edge, setting: EdgeActionSetting, target: SettingsWindowController, runner: ActionRunner) {
        self.edge = edge
        self.popup = ActionPopUpButton()
        self.payload = NSTextField(string: setting.payload)
        self.runner = runner
        self.selectedKind = setting.kind.isSelectable ? setting.kind : .disabled
        self.settingsTarget = target
        super.init(frame: .zero)

        orientation = .horizontal
        alignment = .centerY
        spacing = 10
        translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: edge.displayName)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.alignment = .right

        popup.onOpen = { [weak self] in
            self?.rebuildActionMenu()
        }
        rebuildActionMenu()

        payload.placeholderString = placeholder(for: selectedKind)
        payload.isEnabled = selectedKind.usesPayload
        payload.textColor = selectedKind.usesPayload ? .labelColor : .secondaryLabelColor
        payload.target = self
        payload.action = #selector(payloadChanged)

        let button = NSButton(title: "Test", target: self, action: #selector(testAction))
        button.bezelStyle = .rounded

        addArrangedSubview(label)
        addArrangedSubview(popup)
        addArrangedSubview(payload)
        addArrangedSubview(button)

        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: 72),
            popup.widthAnchor.constraint(equalToConstant: 190),
            payload.widthAnchor.constraint(equalToConstant: 305),
            button.widthAnchor.constraint(equalToConstant: 72)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc private func selectRegularAction(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let kind = GestureActionKind(rawValue: rawValue)
        else {
            return
        }

        selectedKind = kind
        if !kind.usesPayload {
            payload.stringValue = ""
        }
        rebuildActionMenu()
        applySelection()
    }

    @objc private func selectSwitchApplication(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? WindowedApplication else {
            return
        }

        selectedKind = .switchApplication
        payload.stringValue = app.identifier
        rebuildActionMenu()
        applySelection()
    }

    @objc private func payloadChanged() {
        applySelection()
    }

    private func applySelection() {
        payload.placeholderString = placeholder(for: setting.kind)
        payload.isEnabled = setting.kind.usesPayload
        payload.textColor = setting.kind.usesPayload ? .labelColor : .secondaryLabelColor
        settingsTarget?.updateSettingsFromControls()
    }

    @objc private func testAction() {
        settingsTarget?.updateSettingsFromControls()
        runner.test(edge: edge, action: setting)
    }

    private func placeholder(for kind: GestureActionKind) -> String {
        switch kind {
        case .disabled: return ""
        case .showHUD: return "No payload needed"
        case .open: return "https://apple.com or ~/Documents"
        case .runShell: return #"osascript -e 'display notification "Triggered"'"#
        case .controlCenter: return "Clicks Control Center menu bar item"
        case .lockScreen: return "Uses login framework lock"
        case .screenshot: return "Opens Screenshot"
        case .switchApplication: return "Safari or com.apple.Safari"
        case .missionControl, .appExpose, .showDesktop, .launchpad, .notificationCenter, .startScreenSaver:
            return "Removed action"
        }
    }

    private func rebuildActionMenu() {
        let menu = NSMenu()

        for kind in GestureActionKind.allCases where kind != .switchApplication {
            let item = NSMenuItem(title: kind.displayName, action: #selector(selectRegularAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = kind.rawValue
            item.state = selectedKind == kind ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let switchItem = NSMenuItem(title: "Switch App", action: nil, keyEquivalent: "")
        let switchMenu = NSMenu()
        let apps = WindowedApplication.current()

        if apps.isEmpty {
            let emptyItem = NSMenuItem(title: "No windowed apps", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            switchMenu.addItem(emptyItem)
        } else {
            for app in apps {
                let appItem = NSMenuItem(title: app.name, action: #selector(selectSwitchApplication(_:)), keyEquivalent: "")
                appItem.target = self
                appItem.representedObject = app
                appItem.state = selectedKind == .switchApplication && payload.stringValue == app.identifier ? .on : .off
                switchMenu.addItem(appItem)
            }
        }

        switchItem.submenu = switchMenu
        menu.addItem(switchItem)

        popup.menu = menu
        popup.title = selectedPopupTitle(from: apps)
    }

    private func selectedPopupTitle(from apps: [WindowedApplication]) -> String {
        guard selectedKind == .switchApplication else {
            return selectedKind.displayName
        }

        let selectedApp = apps.first { $0.identifier == payload.stringValue }
        return "Switch App: \(selectedApp?.name ?? payload.stringValue)"
    }
}

private final class ActionPopUpButton: NSPopUpButton {
    var onOpen: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onOpen?()
        super.mouseDown(with: event)
    }
}

private struct WindowedApplication: Sendable {
    let name: String
    let identifier: String
    let processIdentifier: pid_t

    @MainActor
    static func current() -> [WindowedApplication] {
        let windowOwners = allWindowOwners()
        var seenIdentifiers = Set<String>()
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> WindowedApplication? in
            let name = app.localizedName ?? ""
            guard app.activationPolicy == .regular,
                  (
                    windowOwners.processIdentifiers.contains(app.processIdentifier) ||
                    windowOwners.names.contains(name) ||
                    hasAccessibilityWindow(processIdentifier: app.processIdentifier)
                  ),
                  !name.isEmpty
            else {
                return nil
            }

            let identifier = app.bundleIdentifier ?? "\(name)-\(app.processIdentifier)"
            guard seenIdentifiers.insert(identifier).inserted else {
                return nil
            }

            return WindowedApplication(
                name: name,
                identifier: identifier,
                processIdentifier: app.processIdentifier
            )
        }

        return apps
            .sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private struct WindowOwners {
        let processIdentifiers: Set<pid_t>
        let names: Set<String>
    }

    private static func allWindowOwners() -> WindowOwners {
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return WindowOwners(processIdentifiers: [], names: [])
        }

        var processIdentifiers = Set<pid_t>()
        var names = Set<String>()

        for info in windowInfo {
            guard let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0
            else {
                continue
            }

            if let pid = info[kCGWindowOwnerPID as String] as? pid_t {
                processIdentifiers.insert(pid)
            }

            if let ownerName = info[kCGWindowOwnerName as String] as? String, !ownerName.isEmpty {
                names.insert(ownerName)
            }
        }

        return WindowOwners(processIdentifiers: processIdentifiers, names: names)
    }

    private static func hasAccessibilityWindow(processIdentifier: pid_t) -> Bool {
        guard AXIsProcessTrusted() else {
            return false
        }

        let axApp = AXUIElementCreateApplication(processIdentifier)
        var windowsValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &windowsValue) == .success,
              let windows = windowsValue as? [AXUIElement]
        else {
            return false
        }

        return !windows.isEmpty
    }
}
