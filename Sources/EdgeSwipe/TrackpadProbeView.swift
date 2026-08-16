import AppKit
import EdgeSwipeCore

@MainActor
final class TrackpadProbeView: NSView {
    private let recognizer: EdgeGestureRecognizer
    private let onGesture: (GestureTrigger) -> Void
    nonisolated(unsafe) private var observer: NSObjectProtocol?
    nonisolated(unsafe) private var animationTimer: Timer?
    private var animationPhase: CGFloat = 0
    private var cornerAnimationPhase: CGFloat = 0
    private var points: [CGPoint] = []
    private var lastGestureText = "Waiting for edge or corner swipe"

    init(edgeConfig: EdgeGestureConfig, cornerConfig: EdgeGestureConfig, onGesture: @escaping (GestureTrigger) -> Void) {
        self.recognizer = EdgeGestureRecognizer(edgeConfig: edgeConfig, cornerConfig: cornerConfig)
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

    func updateConfig(edgeConfig: EdgeGestureConfig, cornerConfig: EdgeGestureConfig) {
        recognizer.edgeConfig = edgeConfig
        recognizer.cornerConfig = cornerConfig
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
        drawCornerZones()
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
                let edgeCooldown = max(0.1, CGFloat(self.recognizer.edgeConfig.cooldown))
                let cornerCooldown = max(0.1, CGFloat(self.recognizer.cornerConfig.cooldown))
                self.animationPhase = (self.animationPhase + (1.0 / 30.0) / edgeCooldown).truncatingRemainder(dividingBy: 1)
                self.cornerAnimationPhase = (self.cornerAnimationPhase + (1.0 / 30.0) / cornerCooldown).truncatingRemainder(dividingBy: 1)
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
        let band = CGFloat(recognizer.edgeConfig.edgeBand)
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

    private func drawCornerZones() {
        let band = CGFloat(recognizer.cornerConfig.edgeBand)
        let cornerSize = CGSize(width: bounds.width * band, height: bounds.height * band)
        let cornerRects = [
            NSRect(x: 0, y: bounds.height - cornerSize.height, width: cornerSize.width, height: cornerSize.height),
            NSRect(x: bounds.width - cornerSize.width, y: bounds.height - cornerSize.height, width: cornerSize.width, height: cornerSize.height),
            NSRect(x: 0, y: 0, width: cornerSize.width, height: cornerSize.height),
            NSRect(x: bounds.width - cornerSize.width, y: 0, width: cornerSize.width, height: cornerSize.height)
        ]

        NSColor.systemTeal.withAlphaComponent(0.18).setFill()
        NSColor.systemTeal.withAlphaComponent(0.55).setStroke()
        for rect in cornerRects {
            let path = NSBezierPath(roundedRect: rect.integral.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4)
            path.fill()
            path.lineWidth = 1
            path.stroke()
        }

        drawTinyLabel("1-finger corners", at: CGPoint(x: bounds.width - 110, y: bounds.height - 24), color: .systemTeal)
    }

    private func drawTravelThresholds() {
        let band = CGFloat(recognizer.edgeConfig.edgeBand)
        let travel = CGFloat(recognizer.edgeConfig.minTravel)
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
        let drift = CGFloat(recognizer.edgeConfig.maxCrossAxisTravel)
        let corridor = max(12, bounds.height * drift * 0.55)
        let leftGuideY = bounds.midY
        let leftStart = CGPoint(x: bounds.width * CGFloat(recognizer.edgeConfig.edgeBand), y: leftGuideY)
        let leftEnd = CGPoint(x: min(bounds.width * 0.46, leftStart.x + bounds.width * CGFloat(recognizer.edgeConfig.minTravel)), y: leftGuideY)

        drawDriftCorridor(from: leftStart, to: leftEnd, radius: corridor / 2)
        drawDirectionArrow(from: leftStart, to: leftEnd, color: .systemGreen)

        let topGuideX = bounds.midX
        let topStart = CGPoint(x: topGuideX, y: bounds.height * (1 - CGFloat(recognizer.edgeConfig.edgeBand)))
        let topEnd = CGPoint(x: topGuideX, y: max(bounds.height * 0.52, topStart.y - bounds.height * CGFloat(recognizer.edgeConfig.minTravel)))

        drawDriftCorridor(from: topStart, to: topEnd, radius: corridor / 2)
        drawDirectionArrow(from: topStart, to: topEnd, color: .systemGreen)

        drawCornerDirectionGuides()
        drawTinyLabel("Drift limit", at: CGPoint(x: bounds.width * 0.34, y: bounds.midY + corridor / 2 + 8), color: .systemGreen)
    }

    private func drawCornerDirectionGuides() {
        let band = CGFloat(recognizer.cornerConfig.edgeBand)
        let travel = CGFloat(recognizer.cornerConfig.minTravel)
        let starts = [
            CGPoint(x: bounds.width * band * 0.5, y: bounds.height * (1 - band * 0.5)),
            CGPoint(x: bounds.width * (1 - band * 0.5), y: bounds.height * (1 - band * 0.5)),
            CGPoint(x: bounds.width * band * 0.5, y: bounds.height * band * 0.5),
            CGPoint(x: bounds.width * (1 - band * 0.5), y: bounds.height * band * 0.5)
        ]

        let deltas = [
            CGPoint(x: bounds.width * travel, y: -bounds.height * travel),
            CGPoint(x: -bounds.width * travel, y: -bounds.height * travel),
            CGPoint(x: bounds.width * travel, y: bounds.height * travel),
            CGPoint(x: -bounds.width * travel, y: bounds.height * travel)
        ]

        for (start, delta) in zip(starts, deltas) {
            let end = CGPoint(x: start.x + delta.x, y: start.y + delta.y)
            drawDirectionArrow(from: start, to: end, color: .systemTeal)
        }
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
        let edgeTrack = NSRect(x: bounds.width - 166, y: 14, width: 142, height: 6)
        let cornerTrack = NSRect(x: bounds.width - 166, y: 27, width: 142, height: 6)

        drawCooldownTrack(edgeTrack, phase: animationPhase, color: .systemOrange)
        drawCooldownTrack(cornerTrack, phase: cornerAnimationPhase, color: .systemTeal)

        drawTinyLabel("Edge cooldown", at: CGPoint(x: edgeTrack.minX, y: edgeTrack.maxY + 1), color: .systemOrange)
        drawTinyLabel("Corner", at: CGPoint(x: cornerTrack.minX - 48, y: cornerTrack.minY - 2), color: .systemTeal)
    }

    private func drawCooldownTrack(_ track: NSRect, phase: CGFloat, color: NSColor) {
        let trackPath = NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3)
        color.withAlphaComponent(0.16).setFill()
        trackPath.fill()

        let fillRect = NSRect(x: track.minX, y: track.minY, width: track.width * phase, height: track.height)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: 3, yRadius: 3)
        color.withAlphaComponent(0.75).setFill()
        fillPath.fill()
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
            lastGestureText = "Recognized \(gesture.trigger.displayName)"
            onGesture(gesture.trigger)
        } else if touches.isEmpty {
            lastGestureText = "Waiting for edge or corner swipe"
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
