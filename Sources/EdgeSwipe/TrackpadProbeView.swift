import AppKit
import EdgeSwipeCore

@MainActor
final class TrackpadProbeView: NSView {
    private let recognizer: EdgeGestureRecognizer
    private let onGesture: (Edge) -> Void
    nonisolated(unsafe) private var observer: NSObjectProtocol?
    nonisolated(unsafe) private var animationTimer: Timer?
    private var animationPhase: CGFloat = 0
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
        startAnimation()

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
        animationTimer?.invalidate()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 680, height: 180)
    }

    func updateConfig(_ config: EdgeGestureConfig) {
        recognizer.config = config
        needsDisplay = true
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

        drawPanelBackground()
        drawEdgeBands()
        drawTravelThresholds()
        drawDriftGuide()
        drawCooldownIndicator()
        drawText()
        drawPoints()
    }

    private func startAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let cooldown = max(0.1, CGFloat(self.recognizer.config.cooldown))
                self.animationPhase = (self.animationPhase + (1.0 / 30.0) / cooldown).truncatingRemainder(dividingBy: 1)
                self.needsDisplay = true
            }
        }
    }

    private func drawPanelBackground() {
        let background = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        NSColor.windowBackgroundColor.setFill()
        background.fill()

        NSColor.separatorColor.withAlphaComponent(0.55).setStroke()
        background.lineWidth = 1
        background.stroke()
    }

    private func drawEdgeBands() {
        let band = CGFloat(recognizer.config.edgeBand)
        let color = NSColor.systemBlue.withAlphaComponent(0.16)
        let stroke = NSColor.systemBlue.withAlphaComponent(0.55)

        let edgeRects = [
            NSRect(x: 0, y: 0, width: bounds.width * band, height: bounds.height),
            NSRect(x: 0, y: bounds.height * (1 - band), width: bounds.width, height: bounds.height * band)
        ]

        color.setFill()
        stroke.setStroke()
        for rect in edgeRects {
            let path = NSBezierPath(rect: rect.integral)
            path.fill()
            path.lineWidth = 1
            path.stroke()
        }

        drawTinyLabel("Edge band", at: CGPoint(x: 10, y: 10), color: .systemBlue)
    }

    private func drawTravelThresholds() {
        let band = CGFloat(recognizer.config.edgeBand)
        let travel = CGFloat(recognizer.config.minTravel)
        let leftX = min(bounds.width, bounds.width * (band + travel))
        let topY = max(0, bounds.height * (1 - band - travel))

        let path = NSBezierPath()
        path.move(to: CGPoint(x: leftX, y: 0))
        path.line(to: CGPoint(x: leftX, y: bounds.height))
        path.move(to: CGPoint(x: 0, y: topY))
        path.line(to: CGPoint(x: bounds.width, y: topY))

        path.lineWidth = 1
        NSColor.systemPurple.withAlphaComponent(0.72).setStroke()
        path.setLineDash([6, 5], count: 2, phase: animationPhase * 10)
        path.stroke()

        drawTinyLabel("Travel", at: CGPoint(x: leftX + 6, y: bounds.height - 48), color: .systemPurple)
    }

    private func drawDriftGuide() {
        let drift = CGFloat(recognizer.config.maxCrossAxisTravel)
        let corridor = max(12, bounds.height * drift * 0.55)
        let leftGuideY = bounds.midY
        let leftStart = CGPoint(x: bounds.width * CGFloat(recognizer.config.edgeBand), y: leftGuideY)
        let leftEnd = CGPoint(x: min(bounds.width * 0.46, leftStart.x + bounds.width * CGFloat(recognizer.config.minTravel)), y: leftGuideY)

        drawDriftCorridor(from: leftStart, to: leftEnd, radius: corridor / 2)
        drawDirectionArrow(from: leftStart, to: leftEnd, color: .systemGreen)

        let topGuideX = bounds.midX
        let topStart = CGPoint(x: topGuideX, y: bounds.height * (1 - CGFloat(recognizer.config.edgeBand)))
        let topEnd = CGPoint(x: topGuideX, y: max(bounds.height * 0.52, topStart.y - bounds.height * CGFloat(recognizer.config.minTravel)))

        drawDriftCorridor(from: topStart, to: topEnd, radius: corridor / 2)
        drawDirectionArrow(from: topStart, to: topEnd, color: .systemGreen)

        drawTinyLabel("Drift limit", at: CGPoint(x: bounds.width * 0.34, y: bounds.midY + corridor / 2 + 8), color: .systemGreen)
    }

    private func drawDriftCorridor(from start: CGPoint, to end: CGPoint, radius: CGFloat) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = radius * 2
        path.lineCapStyle = .round
        NSColor.systemGreen.withAlphaComponent(0.13).setStroke()
        path.stroke()

        let centerPath = NSBezierPath()
        centerPath.move(to: start)
        centerPath.line(to: end)
        centerPath.lineWidth = 1
        centerPath.lineCapStyle = .round
        NSColor.systemGreen.withAlphaComponent(0.62).setStroke()
        centerPath.stroke()
    }

    private func drawDirectionArrow(from start: CGPoint, to end: CGPoint, color: NSColor) {
        let vector = CGPoint(x: end.x - start.x, y: end.y - start.y)
        let length = max(1, hypot(vector.x, vector.y))
        let unit = CGPoint(x: vector.x / length, y: vector.y / length)
        let normal = CGPoint(x: -unit.y, y: unit.x)
        let tip = end
        let wingLength: CGFloat = 8
        let wingWidth: CGFloat = 5

        let arrow = NSBezierPath()
        arrow.move(to: tip)
        arrow.line(to: CGPoint(
            x: tip.x - unit.x * wingLength + normal.x * wingWidth,
            y: tip.y - unit.y * wingLength + normal.y * wingWidth
        ))
        arrow.move(to: tip)
        arrow.line(to: CGPoint(
            x: tip.x - unit.x * wingLength - normal.x * wingWidth,
            y: tip.y - unit.y * wingLength - normal.y * wingWidth
        ))
        arrow.lineWidth = 1.2
        color.withAlphaComponent(0.72).setStroke()
        arrow.stroke()
    }

    private func drawCooldownIndicator() {
        let cooldown = CGFloat(recognizer.config.cooldown)
        let track = NSRect(x: bounds.width - 166, y: 14, width: 142, height: 8)
        let fillWidth = track.width * animationPhase

        let trackPath = NSBezierPath(roundedRect: track, xRadius: 4, yRadius: 4)
        NSColor.systemOrange.withAlphaComponent(0.16 + min(0.12, cooldown / 10)).setFill()
        trackPath.fill()

        let fillRect = NSRect(x: track.minX, y: track.minY, width: fillWidth, height: track.height)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 4, yRadius: 4)
        NSColor.systemOrange.withAlphaComponent(0.75).setFill()
        fillPath.fill()

        drawTinyLabel("Cooldown", at: CGPoint(x: track.minX, y: track.maxY + 6), color: .systemOrange)
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

    private func drawTinyLabel(_ text: String, at point: CGPoint, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: color.withAlphaComponent(0.88)
        ]
        text.draw(at: point, withAttributes: attributes)
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
