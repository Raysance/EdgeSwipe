import AppKit
import EdgeSwipeCore

@MainActor
final class GestureEventMonitor {
    private let store: SettingsStore
    private let runner: ActionRunner
    private let recognizer = EdgeGestureRecognizer()
    private var privateMonitor: PrivateMultitouchMonitor?
    private var settings: AppSettings
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var settingsObserver: NSObjectProtocol?

    init(store: SettingsStore, runner: ActionRunner) {
        self.store = store
        self.runner = runner
        self.settings = store.load()
        self.recognizer.edgeConfig = settings.config
        self.recognizer.cornerConfig = settings.cornerConfig
        self.privateMonitor = PrivateMultitouchMonitor(settings: settings, runner: runner)

        settingsObserver = NotificationCenter.default.addObserver(
            forName: SettingsStore.didChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let settings = notification.object as? AppSettings else { return }
            Task { @MainActor [weak self, settings] in
                guard let self else { return }
                self.settings = settings
                self.recognizer.edgeConfig = settings.config
                self.recognizer.cornerConfig = settings.cornerConfig
                self.privateMonitor?.update(settings: settings)
            }
        }
    }

    func shutdown() {
        stop()
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
            self.settingsObserver = nil
        }
    }

    func start() {
        stop()

        if privateMonitor?.start() == true {
            NSLog("EdgeSwipe: using private MultitouchSupport monitor")
            return
        }

        NSLog("EdgeSwipe: falling back to AppKit gesture monitor")
        let mask: NSEvent.EventTypeMask = [.gesture, .beginGesture, .endGesture]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in
                self?.handle(event)
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        privateMonitor?.stop()

        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func handle(_ event: NSEvent) {
        if event.type == .endGesture {
            _ = recognizer.ingest([])
            return
        }

        let samples = touchSamples(from: event)
        if settings.debugLogging {
            NSLog("EdgeSwipe: event=\(event.type.rawValue) touches=\(samples.count)")
        }

        guard let gesture = recognizer.ingest(samples) else {
            return
        }

        let action = settings.action(for: gesture.trigger)
        runner.run(trigger: gesture.trigger, action: action)
    }

    private func touchSamples(from event: NSEvent) -> [TouchSample] {
        let touches = event.touches(matching: .any, in: nil)
        return touches.map { touch in
            TouchSample(
                id: touch.identity.hash,
                x: Double(touch.normalizedPosition.x),
                y: Double(touch.normalizedPosition.y),
                phase: TouchPhase(touch.phase),
                timestamp: event.timestamp
            )
        }
    }
}

private extension TouchPhase {
    init(_ phase: NSTouch.Phase) {
        if phase.contains(.began) {
            self = .began
        } else if phase.contains(.moved) {
            self = .moved
        } else if phase.contains(.stationary) {
            self = .stationary
        } else if phase.contains(.ended) {
            self = .ended
        } else if phase.contains(.cancelled) {
            self = .cancelled
        } else {
            self = .stationary
        }
    }
}
