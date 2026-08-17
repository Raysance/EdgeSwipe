import AppKit
import ApplicationServices
import EdgeSwipeCore

@MainActor
final class SettingsWindowController: NSWindowController {
    private let store: SettingsStore
    private let runner: ActionRunner
    private var settings: AppSettings
    private var launchAtLoginCheckbox: NSButton!
    private var launchAtLoginStatusLabel: NSTextField!
    private var accessibilityStatusLabel: NSTextField!
    private var accessibilityButton: NSButton!
    private var triggerRows: [GestureTrigger: EdgeActionRow] = [:]
    private var previewView: GesturePreviewView!
    private var selectedPreviewTrigger: GestureTrigger = .left
    private var recognitionWindowController: RecognitionSettingsWindowController?

    init(store: SettingsStore, runner: ActionRunner) {
        self.store = store
        self.runner = runner
        self.settings = store.load()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
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

        root.addArrangedSubview(makeTopBar())
        root.addArrangedSubview(makePreviewSection())
        root.addArrangedSubview(makeActionsSection())
        root.addArrangedSubview(makeSystemSection())

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.documentView = root
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        window.contentView = scrollView

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            scrollView.widthAnchor.constraint(greaterThanOrEqualToConstant: 760),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 620)
        ])
    }

    private func makeTopBar() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false

        let labels = NSStackView()
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2

        let title = NSTextField(labelWithString: "EdgeSwipe")
        title.font = .systemFont(ofSize: 26, weight: .bold)

        let subtitle = NSTextField(labelWithString: "Choose a gesture, assign an action, and preview the result.")
        subtitle.textColor = .secondaryLabelColor
        subtitle.font = .systemFont(ofSize: 13)

        labels.addArrangedSubview(title)
        labels.addArrangedSubview(subtitle)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let settingsButton = NSButton(image: Self.parametersIcon(), target: self, action: #selector(showRecognitionSettings))
        settingsButton.bezelStyle = .texturedRounded
        settingsButton.imagePosition = .imageOnly
        settingsButton.toolTip = "Recognition parameters and Live Probe"

        row.addArrangedSubview(labels)
        row.addArrangedSubview(spacer)
        row.addArrangedSubview(settingsButton)

        NSLayoutConstraint.activate([
            row.widthAnchor.constraint(equalToConstant: 712),
            settingsButton.widthAnchor.constraint(equalToConstant: 34),
            settingsButton.heightAnchor.constraint(equalToConstant: 30)
        ])

        return row
    }

    private func makePreviewSection() -> NSView {
        let stack = sectionStack(title: "Gesture Preview")
        previewView = GesturePreviewView(frame: NSRect(x: 0, y: 0, width: 680, height: 190))
        previewView.show(trigger: selectedPreviewTrigger, action: settings.action(for: selectedPreviewTrigger))
        stack.addArrangedSubview(previewView)
        return stack
    }

    private func makeSystemSection() -> NSView {
        let stack = sectionStack(title: "System")

        let launchRow = NSStackView()
        launchRow.orientation = .horizontal
        launchRow.alignment = .centerY
        launchRow.spacing = 12
        launchRow.translatesAutoresizingMaskIntoConstraints = false

        launchAtLoginCheckbox = NSButton(
            checkboxWithTitle: "Launch at Login",
            target: self,
            action: #selector(toggleLaunchAtLogin)
        )
        launchAtLoginCheckbox.state = LoginItemController.isEnabled ? .on : .off
        launchAtLoginCheckbox.isEnabled = LoginItemController.isSupported

        launchAtLoginStatusLabel = NSTextField(labelWithString: LoginItemController.statusText)
        launchAtLoginStatusLabel.font = .systemFont(ofSize: 12)
        launchAtLoginStatusLabel.textColor = .secondaryLabelColor

        launchRow.addArrangedSubview(launchAtLoginCheckbox)
        launchRow.addArrangedSubview(launchAtLoginStatusLabel)

        let accessibilityRow = NSStackView()
        accessibilityRow.orientation = .horizontal
        accessibilityRow.alignment = .centerY
        accessibilityRow.spacing = 12
        accessibilityRow.translatesAutoresizingMaskIntoConstraints = false

        accessibilityButton = NSButton(title: "Grant Accessibility...", target: self, action: #selector(requestAccessibilityAccess))
        accessibilityButton.bezelStyle = .rounded

        accessibilityStatusLabel = NSTextField(labelWithString: accessibilityStatusText)
        accessibilityStatusLabel.font = .systemFont(ofSize: 12)
        accessibilityStatusLabel.textColor = .secondaryLabelColor

        accessibilityRow.addArrangedSubview(accessibilityButton)
        accessibilityRow.addArrangedSubview(accessibilityStatusLabel)

        NSLayoutConstraint.activate([
            launchAtLoginCheckbox.widthAnchor.constraint(equalToConstant: 190),
            launchAtLoginStatusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 300),
            accessibilityButton.widthAnchor.constraint(equalToConstant: 190),
            accessibilityStatusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 300)
        ])

        stack.addArrangedSubview(launchRow)
        stack.addArrangedSubview(accessibilityRow)
        return stack
    }

    private func makeActionsSection() -> NSView {
        let stack = sectionStack(title: "Actions")

        stack.addArrangedSubview(actionGroupLabel("Two-Finger Edge Swipes"))
        for trigger in GestureTrigger.edgeCases {
            let row = EdgeActionRow(trigger: trigger, setting: settings.action(for: trigger), target: self, runner: runner)
            triggerRows[trigger] = row
            stack.addArrangedSubview(row)
        }

        stack.addArrangedSubview(actionGroupLabel("One-Finger Corner Swipes"))
        for trigger in GestureTrigger.cornerCases {
            let row = EdgeActionRow(trigger: trigger, setting: settings.action(for: trigger), target: self, runner: runner)
            triggerRows[trigger] = row
            stack.addArrangedSubview(row)
        }

        return stack
    }

    private func actionGroupLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    func showPreview(for trigger: GestureTrigger) {
        selectedPreviewTrigger = trigger
        previewView.show(trigger: trigger, action: settings.action(for: trigger))
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

    @objc private func toggleLaunchAtLogin() {
        let shouldEnable = launchAtLoginCheckbox.state == .on

        do {
            try LoginItemController.setEnabled(shouldEnable)
        } catch {
            launchAtLoginStatusLabel.stringValue = "Failed: \(error.localizedDescription)"
            launchAtLoginCheckbox.state = LoginItemController.isEnabled ? .on : .off
            return
        }

        launchAtLoginCheckbox.state = LoginItemController.isEnabled ? .on : .off
        launchAtLoginStatusLabel.stringValue = LoginItemController.statusText
    }

    @objc private func requestAccessibilityAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openAccessibilityPrivacySettings()
        refreshAccessibilityStatusSoon()
    }

    private var accessibilityStatusText: String {
        AXIsProcessTrusted() ? "Accessibility access is granted." : "Required for Control Center, hiding windows, and restoring windows."
    }

    private func refreshAccessibilityStatusSoon() {
        accessibilityStatusLabel.stringValue = accessibilityStatusText
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.accessibilityStatusLabel.stringValue = self?.accessibilityStatusText ?? ""
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.accessibilityStatusLabel.stringValue = self?.accessibilityStatusText ?? ""
        }
    }

    private func openAccessibilityPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        if let url, NSWorkspace.shared.open(url) {
            return
        }

        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func updateSettingsFromControls() {
        var updatedSettings = store.load()

        for (trigger, row) in triggerRows {
            updatedSettings.actions[trigger.rawValue] = row.setting
        }

        settings = updatedSettings
        previewView.show(trigger: selectedPreviewTrigger, action: settings.action(for: selectedPreviewTrigger))
        store.save(updatedSettings)
    }

    @objc private func showRecognitionSettings() {
        if recognitionWindowController == nil {
            recognitionWindowController = RecognitionSettingsWindowController(store: store, runner: runner)
        }

        recognitionWindowController?.showWindow(nil)
        recognitionWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    private static func parametersIcon() -> NSImage {
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24">
          <path fill="none" stroke="#303030" stroke-width="2" stroke-linecap="round" d="M4 7h10M18 7h2M4 17h2M10 17h10"/>
          <circle cx="16" cy="7" r="2.4" fill="#303030"/>
          <circle cx="8" cy="17" r="2.4" fill="#303030"/>
        </svg>
        """

        if let data = svg.data(using: .utf8), let image = NSImage(data: data) {
            image.size = NSSize(width: 18, height: 18)
            return image
        }

        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        NSColor.labelColor.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 2
        path.move(to: CGPoint(x: 3, y: 6))
        path.line(to: CGPoint(x: 11, y: 6))
        path.move(to: CGPoint(x: 15, y: 6))
        path.line(to: CGPoint(x: 16, y: 6))
        path.move(to: CGPoint(x: 3, y: 12))
        path.line(to: CGPoint(x: 4, y: 12))
        path.move(to: CGPoint(x: 8, y: 12))
        path.line(to: CGPoint(x: 16, y: 12))
        path.stroke()
        NSColor.labelColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: 11, y: 3.5, width: 5, height: 5)).fill()
        NSBezierPath(ovalIn: NSRect(x: 4, y: 9.5, width: 5, height: 5)).fill()
        image.unlockFocus()
        return image
    }
}

@MainActor
final class RecognitionSettingsWindowController: NSWindowController {
    private let store: SettingsStore
    private let runner: ActionRunner
    private var settings: AppSettings
    private var edgeBandSlider: NSSlider!
    private var minTravelSlider: NSSlider!
    private var crossAxisSlider: NSSlider!
    private var cooldownSlider: NSSlider!
    private var cornerEdgeBandSlider: NSSlider!
    private var cornerMinTravelSlider: NSSlider!
    private var cornerCrossAxisSlider: NSSlider!
    private var cornerCooldownSlider: NSSlider!
    private var debugCheckbox: NSButton!
    private var probeView: TrackpadProbeView!

    init(store: SettingsStore, runner: ActionRunner) {
        self.store = store
        self.runner = runner
        self.settings = store.load()

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 680),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Recognition Parameters"
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

        let title = NSTextField(labelWithString: "Recognition")
        title.font = .systemFont(ofSize: 24, weight: .bold)

        let subtitle = NSTextField(labelWithString: "Tune edge and corner recognition separately.")
        subtitle.font = .systemFont(ofSize: 13)
        subtitle.textColor = .secondaryLabelColor

        root.addArrangedSubview(title)
        root.addArrangedSubview(subtitle)
        root.addArrangedSubview(makeThresholdSection())
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
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 680)
        ])
    }

    private func makeThresholdSection() -> NSView {
        let stack = sectionStack(title: "Parameters")

        edgeBandSlider = slider(value: settings.config.edgeBand, min: 0.03, max: 0.18)
        minTravelSlider = slider(value: settings.config.minTravel, min: 0.08, max: 0.45)
        crossAxisSlider = slider(value: settings.config.maxCrossAxisTravel, min: 0.04, max: 0.35)
        cooldownSlider = slider(value: settings.config.cooldown, min: 0.1, max: 2.0)
        cornerEdgeBandSlider = slider(value: settings.cornerConfig.edgeBand, min: 0.03, max: 0.18)
        cornerMinTravelSlider = slider(value: settings.cornerConfig.minTravel, min: 0.08, max: 0.45)
        cornerCrossAxisSlider = slider(value: settings.cornerConfig.maxCrossAxisTravel, min: 0.04, max: 0.35)
        cornerCooldownSlider = slider(value: settings.cornerConfig.cooldown, min: 0.1, max: 2.0)

        stack.addArrangedSubview(actionGroupLabel("Two-Finger Edge Recognition"))
        stack.addArrangedSubview(labeledControl("Edge band", detail: "Both fingers must start near an edge", minLabel: "Tighter edge", maxLabel: "Wider edge", control: edgeBandSlider))
        stack.addArrangedSubview(labeledControl("Inward travel", detail: "Required movement toward center", minLabel: "Short swipe", maxLabel: "Long swipe", control: minTravelSlider))
        stack.addArrangedSubview(labeledControl("Drift limit", detail: "Maximum movement across the wrong axis", minLabel: "Strict line", maxLabel: "Loose line", control: crossAxisSlider))
        stack.addArrangedSubview(labeledControl("Cooldown", detail: "Minimum seconds between edge triggers", minLabel: "More repeat", maxLabel: "Less repeat", control: cooldownSlider))

        stack.addArrangedSubview(actionGroupLabel("One-Finger Corner Recognition"))
        stack.addArrangedSubview(labeledControl("Corner band", detail: "Finger must start inside a corner square", minLabel: "Tiny corner", maxLabel: "Wide corner", control: cornerEdgeBandSlider))
        stack.addArrangedSubview(labeledControl("Diagonal travel", detail: "Required inward movement on both axes", minLabel: "Short swipe", maxLabel: "Long swipe", control: cornerMinTravelSlider))
        stack.addArrangedSubview(labeledControl("Diagonal drift", detail: "Allowed imbalance between the two axes", minLabel: "Strict diagonal", maxLabel: "Loose diagonal", control: cornerCrossAxisSlider))
        stack.addArrangedSubview(labeledControl("Cooldown", detail: "Minimum seconds between corner triggers", minLabel: "More repeat", maxLabel: "Less repeat", control: cornerCooldownSlider))

        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 12

        let restoreButton = NSButton(title: "Restore Recognition Defaults", target: self, action: #selector(restoreRecognitionDefaults))
        restoreButton.bezelStyle = .rounded
        debugCheckbox = NSButton(checkboxWithTitle: "Log raw gesture touch counts to Console", target: self, action: #selector(updateSettingsFromControls))
        debugCheckbox.state = settings.debugLogging ? .on : .off

        controls.addArrangedSubview(restoreButton)
        controls.addArrangedSubview(debugCheckbox)
        stack.addArrangedSubview(controls)

        return stack
    }

    private func makeProbeSection() -> NSView {
        let stack = sectionStack(title: "Live Probe")

        let help = NSTextField(wrappingLabelWithString: "Try two fingers from an edge, or one finger from a corner toward the center, while this window is active. The same recognizer is used here and by the menu-bar monitor.")
        help.textColor = .secondaryLabelColor
        help.font = .systemFont(ofSize: 12)
        help.preferredMaxLayoutWidth = 680

        probeView = TrackpadProbeView(edgeConfig: settings.config, cornerConfig: settings.cornerConfig) { [weak self] trigger in
            guard let self else { return }
            let currentSettings = self.store.load()
            self.runner.test(trigger: trigger, action: currentSettings.action(for: trigger))
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

    private func actionGroupLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
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

    @objc private func restoreRecognitionDefaults() {
        let defaults = EdgeGestureConfig()
        edgeBandSlider.doubleValue = defaults.edgeBand
        minTravelSlider.doubleValue = defaults.minTravel
        crossAxisSlider.doubleValue = defaults.maxCrossAxisTravel
        cooldownSlider.doubleValue = defaults.cooldown
        cornerEdgeBandSlider.doubleValue = defaults.edgeBand
        cornerMinTravelSlider.doubleValue = defaults.minTravel
        cornerCrossAxisSlider.doubleValue = defaults.maxCrossAxisTravel
        cornerCooldownSlider.doubleValue = defaults.cooldown
        updateSettingsFromControls()
    }

    @objc private func updateSettingsFromControls() {
        var updatedSettings = store.load()
        updatedSettings.config.edgeBand = edgeBandSlider.doubleValue
        updatedSettings.config.minTravel = minTravelSlider.doubleValue
        updatedSettings.config.maxCrossAxisTravel = crossAxisSlider.doubleValue
        updatedSettings.config.cooldown = cooldownSlider.doubleValue
        updatedSettings.cornerConfig.edgeBand = cornerEdgeBandSlider.doubleValue
        updatedSettings.cornerConfig.minTravel = cornerMinTravelSlider.doubleValue
        updatedSettings.cornerConfig.maxCrossAxisTravel = cornerCrossAxisSlider.doubleValue
        updatedSettings.cornerConfig.cooldown = cornerCooldownSlider.doubleValue
        updatedSettings.debugLogging = debugCheckbox.state == .on

        settings = updatedSettings
        probeView.updateConfig(edgeConfig: updatedSettings.config, cornerConfig: updatedSettings.cornerConfig)
        store.save(updatedSettings)
    }
}

@MainActor
final class EdgeActionRow: NSStackView {
    private let trigger: GestureTrigger
    private let triggerButton: NSButton
    private let popup: ActionPopUpButton
    private let payload: NSTextField
    private let runner: ActionRunner
    private var selectedKind: GestureActionKind
    private weak var settingsTarget: SettingsWindowController?

    var setting: EdgeActionSetting {
        EdgeActionSetting(kind: selectedKind, payload: payload.stringValue)
    }

    init(trigger: GestureTrigger, setting: EdgeActionSetting, target: SettingsWindowController, runner: ActionRunner) {
        self.trigger = trigger
        self.triggerButton = NSButton(title: trigger.shortDisplayName, target: nil, action: nil)
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

        triggerButton.target = self
        triggerButton.action = #selector(showPreview)
        triggerButton.bezelStyle = .inline
        triggerButton.isBordered = false
        triggerButton.font = .systemFont(ofSize: 13, weight: .medium)
        triggerButton.alignment = .right
        triggerButton.contentTintColor = .labelColor
        triggerButton.toolTip = "Show gesture preview"

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

        addArrangedSubview(triggerButton)
        addArrangedSubview(popup)
        addArrangedSubview(payload)
        addArrangedSubview(button)

        NSLayoutConstraint.activate([
            triggerButton.widthAnchor.constraint(equalToConstant: 96),
            popup.widthAnchor.constraint(equalToConstant: 190),
            payload.widthAnchor.constraint(equalToConstant: 281),
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
        settingsTarget?.showPreview(for: trigger)
    }

    @objc private func testAction() {
        settingsTarget?.updateSettingsFromControls()
        runner.test(trigger: trigger, action: setting)
    }

    @objc private func showPreview() {
        settingsTarget?.showPreview(for: trigger)
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
        case .hideFrontWindow: return "Hides the front window on the active display"
        case .restoreHiddenWindow: return "Restores the last window hidden by EdgeSwipe"
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
