import AppKit
import EdgeSwipeCore

@MainActor
final class TrackpadProbeView: NSView {
    private let recognizer: EdgeGestureRecognizer
    private let onGesture: (Edge) -> Void
    nonisolated(unsafe) private var observer: NSObjectProtocol?
    private var points: [CGPoint] = []
    private var lastGestureText = "Waiting for two-finger edge swipe"

    init(config: EdgeGestureConfig, onGesture: @escaping (Edge) -> Void) {
        self.recognizer = EdgeGestureRecognizer(config: config)
        self.onGesture = onGesture
        super.init(frame: NSRect(x: 0, y: 0, width: 680, height: 180))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        allowedTouchTypes = [.indirect]
        wantsRestingTouches = false

        observer = NotificationCenter.default.addObserver(
            forName: .edgeSwipeGlobalTouchesDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self, let touchPoints = notification.object as? [GlobalTouchPoint] else { return }
            Task { @MainActor in
                self.updateGlobalTouchPoints(touchPoints)
            }
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 680, height: 180)
    }

    func updateConfig(_ config: EdgeGestureConfig) {
        recognizer.config = config
    }

    override func touchesBegan(with event: NSEvent) {
        handle(event)
    }

    override func touchesMoved(with event: NSEvent) {
        handle(event)
    }

    override func touchesEnded(with event: NSEvent) {
        handle(event)
    }

    override func touchesCancelled(with event: NSEvent) {
        handle(event)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        bounds.fill()

        drawEdgeBands()
        drawText()
        drawPoints()
    }

    private func drawEdgeBands() {
        let band = CGFloat(recognizer.config.edgeBand)
        NSColor.systemBlue.withAlphaComponent(0.16).setFill()
        NSRect(x: 0, y: 0, width: bounds.width * band, height: bounds.height).fill()
        NSRect(x: 0, y: bounds.height * (1 - band), width: bounds.width, height: bounds.height * band).fill()
        NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height * band).fill()
    }

    private func drawText() {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        lastGestureText.draw(at: CGPoint(x: 16, y: bounds.height - 30), withAttributes: attributes)
    }

    private func drawPoints() {
        NSColor.systemBlue.setFill()
        for point in points {
            NSBezierPath(ovalIn: NSRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)).fill()
        }
    }

    private func handle(_ event: NSEvent) {
        let touches = event.touches(matching: .any, in: self)
        points = touches.map { touch in
            CGPoint(
                x: CGFloat(touch.normalizedPosition.x) * bounds.width,
                y: CGFloat(touch.normalizedPosition.y) * bounds.height
            )
        }

        let samples = touches.map { touch in
            TouchSample(
                id: touch.identity.hash,
                x: Double(touch.normalizedPosition.x),
                y: Double(touch.normalizedPosition.y),
                phase: TouchPhase(touch.phase),
                timestamp: event.timestamp
            )
        }

        if let gesture = recognizer.ingest(samples) {
            lastGestureText = "Recognized \(gesture.edge.displayName)"
            onGesture(gesture.edge)
        } else if touches.isEmpty {
            lastGestureText = "Waiting for two-finger edge swipe"
        } else {
            lastGestureText = "\(touches.count) active touch(es)"
        }

        needsDisplay = true
    }

    private func updateGlobalTouchPoints(_ touchPoints: [GlobalTouchPoint]) {
        points = touchPoints.map { touch in
            CGPoint(
                x: CGFloat(touch.x) * bounds.width,
                y: CGFloat(touch.y) * bounds.height
            )
        }

        if touchPoints.isEmpty {
            lastGestureText = "Global monitor active"
        } else {
            lastGestureText = "Global monitor: \(touchPoints.count) touch(es)"
        }

        needsDisplay = true
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
