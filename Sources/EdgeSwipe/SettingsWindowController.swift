import AppKit
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

        stack.addArrangedSubview(labeledControl("Edge band", detail: "Start zone near an edge", control: edgeBandSlider))
        stack.addArrangedSubview(labeledControl("Inward travel", detail: "Required movement toward center", control: minTravelSlider))
        stack.addArrangedSubview(labeledControl("Drift limit", detail: "Maximum movement across the wrong axis", control: crossAxisSlider))
        stack.addArrangedSubview(labeledControl("Cooldown", detail: "Minimum seconds between triggers", control: cooldownSlider))

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

    private func labeledControl(_ title: String, detail: String, control: NSControl) -> NSView {
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

        labels.addArrangedSubview(titleLabel)
        labels.addArrangedSubview(detailLabel)
        row.addArrangedSubview(labels)
        row.addArrangedSubview(control)

        NSLayoutConstraint.activate([
            labels.widthAnchor.constraint(equalToConstant: 190),
            control.widthAnchor.constraint(equalToConstant: 430)
        ])

        return row
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
    private let popup: NSPopUpButton
    private let payload: NSTextField
    private let runner: ActionRunner
    private weak var settingsTarget: SettingsWindowController?

    var setting: EdgeActionSetting {
        let selected = GestureActionKind.allCases[popup.indexOfSelectedItem]
        return EdgeActionSetting(kind: selected, payload: payload.stringValue)
    }

    init(edge: Edge, setting: EdgeActionSetting, target: SettingsWindowController, runner: ActionRunner) {
        self.edge = edge
        self.popup = NSPopUpButton()
        self.payload = NSTextField(string: setting.payload)
        self.runner = runner
        self.settingsTarget = target
        super.init(frame: .zero)

        orientation = .horizontal
        alignment = .centerY
        spacing = 10
        translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: edge.displayName)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.alignment = .right

        popup.addItems(withTitles: GestureActionKind.allCases.map(\.displayName))
        popup.selectItem(at: GestureActionKind.allCases.firstIndex(of: setting.kind) ?? 0)
        popup.target = self
        popup.action = #selector(changed)

        payload.placeholderString = placeholder(for: setting.kind)
        payload.isEnabled = setting.kind.usesPayload
        payload.textColor = setting.kind.usesPayload ? .labelColor : .secondaryLabelColor
        payload.target = self
        payload.action = #selector(changed)

        let button = NSButton(title: "Test", target: self, action: #selector(testAction))
        button.bezelStyle = .rounded

        addArrangedSubview(label)
        addArrangedSubview(popup)
        addArrangedSubview(payload)
        addArrangedSubview(button)

        NSLayoutConstraint.activate([
            label.widthAnchor.constraint(equalToConstant: 72),
            popup.widthAnchor.constraint(equalToConstant: 135),
            payload.widthAnchor.constraint(equalToConstant: 360),
            button.widthAnchor.constraint(equalToConstant: 72)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    @objc private func changed() {
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
        case .missionControl: return "Built-in system action"
        case .appExpose: return "Uses Control + Down Arrow"
        case .showDesktop: return "Uses F11"
        case .launchpad: return "Uses F4"
        case .notificationCenter: return "Uses Control Center/Notification Center"
        case .lockScreen: return "Uses CGSession"
        case .startScreenSaver: return "Opens ScreenSaverEngine"
        case .runShell: return #"osascript -e 'display notification "Triggered"'"#
        case .open: return "https://apple.com or ~/Documents"
        }
    }
}
