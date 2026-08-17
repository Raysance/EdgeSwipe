import AppKit
import EdgeSwipeCore

@MainActor
final class GesturePreviewView: NSView {
    nonisolated(unsafe) private var animationTimer: Timer?
    private var trigger: GestureTrigger = .left
    private var action: EdgeActionSetting = .disabled
    private var phase: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        startAnimation()
    }

    required init?(coder: NSCoder) {
        nil
    }

    deinit {
        animationTimer?.invalidate()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 680, height: 190)
    }

    func show(trigger: GestureTrigger, action: EdgeActionSetting) {
        self.trigger = trigger
        self.action = action
        phase = 0
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()

        let leftPanel = NSRect(x: 0, y: 0, width: 328, height: bounds.height)
        let rightPanel = NSRect(x: 352, y: 0, width: bounds.width - 352, height: bounds.height)

        drawPanel(leftPanel)
        drawPanel(rightPanel)
        drawTrackpad(in: leftPanel.insetBy(dx: 34, dy: 28))
        drawActionPreview(in: rightPanel.insetBy(dx: 20, dy: 20))
        drawTitle(in: bounds)
    }

    private func startAnimation() {
        animationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.phase = (self.phase + 1.0 / 96.0).truncatingRemainder(dividingBy: 1)
                self.needsDisplay = true
            }
        }
    }

    private func drawPanel(_ rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 16, yRadius: 16)
        NSColor.controlBackgroundColor.withAlphaComponent(0.78).setFill()
        path.fill()
    }

    private func drawTitle(in rect: NSRect) {
        let text = "\(trigger.displayName) Preview"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        text.draw(at: CGPoint(x: 16, y: rect.height - 25), withAttributes: attributes)
    }

    private func drawTrackpad(in rect: NSRect) {
        let padSize = NSSize(width: min(rect.width, 205), height: min(rect.height, 128))
        let pad = NSRect(
            x: rect.midX - padSize.width / 2,
            y: rect.midY - padSize.height / 2 - 4,
            width: padSize.width,
            height: padSize.height
        )

        let padPath = NSBezierPath(roundedRect: pad, xRadius: 16, yRadius: 16)
        NSColor.windowBackgroundColor.setFill()
        padPath.fill()
        NSColor.separatorColor.withAlphaComponent(0.9).setStroke()
        padPath.lineWidth = 3
        padPath.stroke()

        drawStartZone(in: pad)
        drawFingerDots(in: pad)
    }

    private func drawStartZone(in pad: NSRect) {
        let zoneColor = isCornerTrigger ? NSColor.systemTeal : NSColor.systemBlue
        let path = NSBezierPath()
        let band = max(12, min(pad.width, pad.height) * 0.18)

        switch trigger {
        case .left:
            path.appendRect(NSRect(x: pad.minX, y: pad.minY, width: band, height: pad.height))
        case .right:
            path.appendRect(NSRect(x: pad.maxX - band, y: pad.minY, width: band, height: pad.height))
        case .top:
            path.appendRect(NSRect(x: pad.minX, y: pad.maxY - band, width: pad.width, height: band))
        case .bottom:
            path.appendRect(NSRect(x: pad.minX, y: pad.minY, width: pad.width, height: band))
        case .topLeft:
            path.appendRect(NSRect(x: pad.minX, y: pad.maxY - band, width: band, height: band))
        case .topRight:
            path.appendRect(NSRect(x: pad.maxX - band, y: pad.maxY - band, width: band, height: band))
        case .bottomLeft:
            path.appendRect(NSRect(x: pad.minX, y: pad.minY, width: band, height: band))
        case .bottomRight:
            path.appendRect(NSRect(x: pad.maxX - band, y: pad.minY, width: band, height: band))
        }

        zoneColor.withAlphaComponent(0.12).setFill()
        path.fill()
    }

    private func drawFingerDots(in pad: NSRect) {
        let progress = easedProgress
        let color = isCornerTrigger ? NSColor.systemTeal : NSColor.systemBlue
        let positions = fingerPositions(progress: progress)

        for point in positions {
            let center = CGPoint(
                x: pad.minX + point.x * pad.width,
                y: pad.minY + point.y * pad.height
            )
            drawDot(at: center, radius: 10, color: color)
        }
    }

    private func drawActionPreview(in rect: NSRect) {
        let progress = easedProgress
        let background = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        actionBackgroundColor.withAlphaComponent(action.kind == .disabled ? 0.34 : 0.78).setFill()
        background.fill()

        switch action.kind {
        case .disabled:
            drawDisabledPreview(in: rect, progress: progress)
        case .showHUD:
            drawHUDPreview(in: rect, progress: progress)
        case .open:
            drawOpenPreview(in: rect, progress: progress)
        case .runShell:
            drawShellPreview(in: rect, progress: progress)
        case .controlCenter:
            drawControlCenterPreview(in: rect, progress: progress)
        case .lockScreen:
            drawLockPreview(in: rect, progress: progress)
        case .screenshot:
            drawScreenshotPreview(in: rect, progress: progress)
        case .hideFrontWindow:
            drawSwitchAppPreview(in: rect, progress: 1 - progress)
        case .restoreHiddenWindow:
            drawSwitchAppPreview(in: rect, progress: progress)
        case .switchApplication:
            drawSwitchAppPreview(in: rect, progress: progress)
        case .missionControl, .appExpose, .showDesktop, .launchpad, .notificationCenter, .startScreenSaver:
            drawDisabledPreview(in: rect, progress: progress)
        }
    }

    private func drawDesktopBackdrop(in rect: NSRect, progress: CGFloat = 1) {
        let windowShift = responseShift(progress)
        let window = NSRect(
            x: rect.midX - 98 + windowShift.x * 0.45,
            y: rect.midY - 44 + windowShift.y * 0.45,
            width: 196,
            height: 100
        )
        drawDemoWindow(window, alpha: 0.86)
        drawDock(in: rect)
    }

    private func drawDemoWindow(_ rect: NSRect, alpha: CGFloat = 0.92) {
        let windowPath = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        NSColor.windowBackgroundColor.withAlphaComponent(alpha).setFill()
        windowPath.fill()

        let titleBar = NSRect(x: rect.minX, y: rect.maxY - 18, width: rect.width, height: 18)
        NSColor.white.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: titleBar, xRadius: 5, yRadius: 5).fill()

        for index in 0..<4 {
            drawDot(
                at: CGPoint(x: titleBar.minX + 12 + CGFloat(index) * 14, y: titleBar.midY),
                radius: 4,
                color: NSColor.white.withAlphaComponent(0.8)
            )
        }

        let shapeRect = NSRect(x: rect.midX - 44, y: rect.midY - 12, width: 88, height: 42)
        NSColor.systemGreen.withAlphaComponent(0.86).setFill()
        NSBezierPath(roundedRect: NSRect(x: shapeRect.minX + 34, y: shapeRect.minY + 8, width: 42, height: 34), xRadius: 6, yRadius: 6).fill()
        NSColor.systemBlue.withAlphaComponent(0.86).setFill()
        NSBezierPath(ovalIn: NSRect(x: shapeRect.minX, y: shapeRect.minY, width: 52, height: 52)).fill()
        NSColor.systemYellow.withAlphaComponent(0.9).setFill()
        let triangle = NSBezierPath()
        triangle.move(to: CGPoint(x: shapeRect.maxX, y: shapeRect.minY + 3))
        triangle.line(to: CGPoint(x: shapeRect.maxX - 36, y: shapeRect.minY + 3))
        triangle.line(to: CGPoint(x: shapeRect.maxX - 18, y: shapeRect.maxY))
        triangle.close()
        triangle.fill()

        NSColor.secondaryLabelColor.withAlphaComponent(0.25).setStroke()
        for index in 0..<4 {
            let y = rect.minY + 16 + CGFloat(index) * 7
            let line = NSBezierPath()
            line.move(to: CGPoint(x: rect.minX + 46, y: y))
            line.line(to: CGPoint(x: rect.maxX - 46, y: y))
            line.lineWidth = 2
            line.stroke()
        }
    }

    private func drawDock(in rect: NSRect) {
        let dock = NSRect(x: rect.midX - 88, y: rect.minY + 8, width: 176, height: 18)
        NSColor.white.withAlphaComponent(0.28).setFill()
        NSBezierPath(roundedRect: dock, xRadius: 7, yRadius: 7).fill()

        let colors: [NSColor] = [.systemBlue, .systemRed, .systemGreen, .systemYellow, .systemPurple, .systemGray]
        for (index, color) in colors.enumerated() {
            let item = NSRect(x: dock.minX + 9 + CGFloat(index) * 27, y: dock.minY + 4, width: 10, height: 10)
            color.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: item, xRadius: 2, yRadius: 2).fill()
        }
    }

    private func drawDisabledPreview(in rect: NSRect, progress: CGFloat) {
        drawDesktopBackdrop(in: rect, progress: 0)
        let line = NSBezierPath()
        line.move(to: CGPoint(x: rect.midX - 22, y: rect.midY - 22))
        line.line(to: CGPoint(x: rect.midX + 22, y: rect.midY + 22))
        line.move(to: CGPoint(x: rect.midX - 22, y: rect.midY + 22))
        line.line(to: CGPoint(x: rect.midX + 22, y: rect.midY - 22))
        line.lineWidth = 5
        line.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.35 + 0.35 * progress).setStroke()
        line.stroke()
    }

    private func drawHUDPreview(in rect: NSRect, progress: CGFloat) {
        drawDesktopBackdrop(in: rect, progress: progress)

        NSColor.black.withAlphaComponent(0.18 + 0.18 * progress).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()

        let hud = NSRect(x: rect.midX - 76, y: rect.midY - 27, width: 152, height: 54).insetBy(dx: 0, dy: 12 * (1 - progress))
        let path = NSBezierPath(roundedRect: hud, xRadius: 12, yRadius: 12)
        NSColor.black.withAlphaComponent(0.46 + 0.24 * progress).setFill()
        path.fill()
        drawHUDGlyph(in: hud.insetBy(dx: 35, dy: 12), progress: progress)
    }

    private func drawOpenPreview(in rect: NSRect, progress: CGFloat) {
        drawDesktopBackdrop(in: rect, progress: progress)

        if isURLTarget {
            let browser = NSRect(x: rect.midX - 82, y: rect.midY - 50 + 12 * progress, width: 164, height: 98)
            drawBrowserWindow(browser)
            drawExternalArrow(from: CGPoint(x: browser.maxX - 38, y: browser.minY + 26), progress: progress)
        } else {
            let folder = NSRect(x: rect.midX - 54, y: rect.midY - 34 + 14 * progress, width: 108, height: 76)
            drawFolderIcon(in: folder)
        }
    }

    private func drawShellPreview(in rect: NSRect, progress: CGFloat) {
        let terminal = NSRect(x: rect.midX - 90, y: rect.midY - 44 + 10 * progress, width: 180, height: 88)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: terminal, xRadius: 7, yRadius: 7).fill()
        NSColor.white.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: NSRect(x: terminal.minX, y: terminal.maxY - 20, width: terminal.width, height: 20), xRadius: 7, yRadius: 7).fill()

        drawDot(at: CGPoint(x: terminal.minX + 14, y: terminal.maxY - 10), radius: 3, color: .systemRed)
        drawDot(at: CGPoint(x: terminal.minX + 26, y: terminal.maxY - 10), radius: 3, color: .systemYellow)
        drawDot(at: CGPoint(x: terminal.minX + 38, y: terminal.maxY - 10), radius: 3, color: .systemGreen)

        NSColor.systemGreen.withAlphaComponent(0.74 + 0.2 * progress).setStroke()
        for index in 0..<4 {
            let path = NSBezierPath()
            path.move(to: CGPoint(x: terminal.minX + 18, y: terminal.maxY - 34 - CGFloat(index) * 12))
            path.line(to: CGPoint(x: terminal.minX + 58 + CGFloat(index) * 18, y: terminal.maxY - 34 - CGFloat(index) * 12))
            path.lineWidth = 2
            path.stroke()
        }

        let caret = NSRect(x: terminal.minX + 92 + 30 * progress, y: terminal.minY + 18, width: 9, height: 16)
        NSColor.systemGreen.withAlphaComponent(0.92).setFill()
        NSBezierPath(rect: caret).fill()
    }

    private func drawControlCenterPreview(in rect: NSRect, progress: CGFloat) {
        drawMenuBar(in: rect)

        let iconCenter = CGPoint(x: rect.maxX - 28, y: rect.maxY - 13)
        drawControlCenterMenuIcon(at: iconCenter, active: progress > 0.25)

        let panelWidth: CGFloat = 136
        let panel = NSRect(x: rect.maxX - 12 - panelWidth * progress, y: rect.maxY - 138, width: panelWidth, height: 118)
        NSColor.white.withAlphaComponent(0.82).setFill()
        NSBezierPath(roundedRect: panel, xRadius: 12, yRadius: 12).fill()

        let tileRects = [
            NSRect(x: panel.minX + 12, y: panel.maxY - 42, width: 52, height: 30),
            NSRect(x: panel.minX + 72, y: panel.maxY - 42, width: 52, height: 30),
            NSRect(x: panel.minX + 12, y: panel.maxY - 80, width: 112, height: 14),
            NSRect(x: panel.minX + 12, y: panel.maxY - 104, width: 112, height: 14)
        ]
        for tile in tileRects {
            NSColor.systemBlue.withAlphaComponent(0.64).setFill()
            NSBezierPath(roundedRect: tile, xRadius: 7, yRadius: 7).fill()
        }
    }

    private func drawLockPreview(in rect: NSRect, progress: CGFloat) {
        drawDesktopBackdrop(in: rect, progress: 0)
        NSColor.black.withAlphaComponent(0.45 + 0.45 * progress).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        drawLockGlyph(center: CGPoint(x: rect.midX, y: rect.midY), scale: 1.35, alpha: 0.72 + 0.22 * progress)
    }

    private func drawScreenshotPreview(in rect: NSRect, progress: CGFloat) {
        drawDesktopBackdrop(in: rect, progress: 0)
        let selection = NSRect(
            x: rect.midX - 86 + 12 * progress,
            y: rect.midY - 50 + 9 * progress,
            width: 172 - 24 * progress,
            height: 100 - 18 * progress
        )
        let path = NSBezierPath(roundedRect: selection, xRadius: 4, yRadius: 4)
        path.lineWidth = 2
        path.setLineDash([7, 5], count: 2, phase: phase * 18)
        NSColor.white.withAlphaComponent(0.86).setStroke()
        path.stroke()

        drawCameraGlyph(center: CGPoint(x: selection.midX, y: selection.midY), scale: 1 + 0.12 * progress)
        let flash = NSBezierPath(ovalIn: NSRect(x: selection.midX - 58 * progress, y: selection.midY - 58 * progress, width: 116 * progress, height: 116 * progress))
        NSColor.white.withAlphaComponent(0.18 * (1 - progress)).setFill()
        flash.fill()
    }

    private func drawSwitchAppPreview(in rect: NSRect, progress: CGFloat) {
        drawDesktopBackdrop(in: rect, progress: 0)
        NSColor.black.withAlphaComponent(0.28 + 0.18 * progress).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()

        let switcher = NSRect(x: rect.midX - 112, y: rect.midY - 44, width: 224, height: 88)
        NSColor.white.withAlphaComponent(0.32 + 0.32 * progress).setFill()
        NSBezierPath(roundedRect: switcher, xRadius: 16, yRadius: 16).fill()

        let iconSize: CGFloat = 44
        let centers = [
            CGPoint(x: switcher.minX + 45, y: switcher.midY),
            CGPoint(x: switcher.midX, y: switcher.midY + 5 * progress),
            CGPoint(x: switcher.maxX - 45, y: switcher.midY)
        ]

        for (index, center) in centers.enumerated() {
            let iconRect = NSRect(x: center.x - iconSize / 2, y: center.y - iconSize / 2, width: iconSize, height: iconSize)
            if index == 1, let icon = selectedAppIcon {
                icon.draw(in: iconRect)
            } else {
                drawGenericAppIcon(in: iconRect, index: index)
            }
        }

        let selected = NSRect(x: centers[1].x - 30, y: centers[1].y - 30, width: 60, height: 60)
        NSColor.white.withAlphaComponent(0.72).setStroke()
        let highlight = NSBezierPath(roundedRect: selected, xRadius: 13, yRadius: 13)
        highlight.lineWidth = 3
        highlight.stroke()
    }

    private func drawHUDGlyph(in rect: NSRect, progress: CGFloat) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        NSColor.white.withAlphaComponent(0.82).setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: center.x - 17, y: center.y - 17, width: 34, height: 34))
        ring.lineWidth = 3
        ring.stroke()

        let pulse = NSBezierPath(ovalIn: NSRect(x: center.x - 27 * progress, y: center.y - 27 * progress, width: 54 * progress, height: 54 * progress))
        NSColor.white.withAlphaComponent(0.2 * (1 - progress)).setStroke()
        pulse.lineWidth = 3
        pulse.stroke()

        drawSignalBars(in: NSRect(x: rect.minX + 6, y: rect.minY + 3, width: 64, height: 24), color: .white, alpha: 0.78)
    }

    private func drawBrowserWindow(_ rect: NSRect) {
        NSColor.white.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()

        let bar = NSRect(x: rect.minX, y: rect.maxY - 22, width: rect.width, height: 22)
        NSColor.white.withAlphaComponent(0.5).setFill()
        NSBezierPath(roundedRect: bar, xRadius: 8, yRadius: 8).fill()

        let address = NSRect(x: bar.minX + 36, y: bar.midY - 5, width: bar.width - 48, height: 10)
        NSColor.systemBlue.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: address, xRadius: 5, yRadius: 5).fill()

        drawGlobeGlyph(center: CGPoint(x: rect.midX, y: rect.midY - 8), radius: 26)
    }

    private func drawGlobeGlyph(center: CGPoint, radius: CGFloat) {
        NSColor.systemBlue.withAlphaComponent(0.82).setStroke()
        let globe = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
        globe.lineWidth = 3
        globe.stroke()

        for offset in [-0.45, 0.45] {
            let line = NSBezierPath()
            line.move(to: CGPoint(x: center.x + CGFloat(offset) * radius, y: center.y - radius + 3))
            line.line(to: CGPoint(x: center.x + CGFloat(offset) * radius, y: center.y + radius - 3))
            line.lineWidth = 2
            line.stroke()
        }

        for offset in [-0.35, 0.35] {
            let line = NSBezierPath()
            line.move(to: CGPoint(x: center.x - radius + 4, y: center.y + CGFloat(offset) * radius))
            line.line(to: CGPoint(x: center.x + radius - 4, y: center.y + CGFloat(offset) * radius))
            line.lineWidth = 2
            line.stroke()
        }
    }

    private func drawExternalArrow(from start: CGPoint, progress: CGFloat) {
        let end = CGPoint(x: start.x + 34 * progress, y: start.y + 28 * progress)
        let arrow = NSBezierPath()
        arrow.move(to: start)
        arrow.line(to: end)
        arrow.move(to: CGPoint(x: end.x - 16, y: end.y))
        arrow.line(to: end)
        arrow.line(to: CGPoint(x: end.x, y: end.y - 16))
        arrow.lineWidth = 4
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        NSColor.white.withAlphaComponent(0.76).setStroke()
        arrow.stroke()
    }

    private func drawFolderIcon(in rect: NSRect) {
        let tab = NSRect(x: rect.minX + 10, y: rect.maxY - 23, width: rect.width * 0.42, height: 18)
        NSColor.systemYellow.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: tab, xRadius: 5, yRadius: 5).fill()

        let body = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - 12)
        NSColor.systemYellow.withAlphaComponent(0.98).setFill()
        NSBezierPath(roundedRect: body, xRadius: 9, yRadius: 9).fill()

        NSColor.white.withAlphaComponent(0.3).setFill()
        NSBezierPath(roundedRect: body.insetBy(dx: 15, dy: 18), xRadius: 5, yRadius: 5).fill()
    }

    private func drawMenuBar(in rect: NSRect) {
        let menuBar = NSRect(x: rect.minX, y: rect.maxY - 26, width: rect.width, height: 26)
        NSColor.white.withAlphaComponent(0.3).setFill()
        NSBezierPath(roundedRect: menuBar, xRadius: 6, yRadius: 6).fill()
    }

    private func drawControlCenterMenuIcon(at center: CGPoint, active: Bool) {
        let rect = NSRect(x: center.x - 12, y: center.y - 9, width: 24, height: 18)
        NSColor.white.withAlphaComponent(active ? 0.86 : 0.58).setStroke()
        let path = NSBezierPath()
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.move(to: CGPoint(x: rect.minX + 2, y: rect.maxY - 5))
        path.line(to: CGPoint(x: rect.maxX - 2, y: rect.maxY - 5))
        path.move(to: CGPoint(x: rect.minX + 2, y: rect.minY + 5))
        path.line(to: CGPoint(x: rect.maxX - 2, y: rect.minY + 5))
        path.stroke()
        drawDot(at: CGPoint(x: rect.midX + 5, y: rect.maxY - 5), radius: 3, color: .white)
        drawDot(at: CGPoint(x: rect.midX - 5, y: rect.minY + 5), radius: 3, color: .white)
    }

    private func drawLockGlyph(center: CGPoint, scale: CGFloat, alpha: CGFloat) {
        NSColor.white.withAlphaComponent(alpha).setStroke()
        let shackle = NSBezierPath()
        shackle.appendArc(
            withCenter: CGPoint(x: center.x, y: center.y + 12 * scale),
            radius: 17 * scale,
            startAngle: 0,
            endAngle: 180,
            clockwise: false
        )
        shackle.lineWidth = 4 * scale
        shackle.stroke()

        NSColor.white.withAlphaComponent(alpha).setFill()
        NSBezierPath(roundedRect: NSRect(x: center.x - 24 * scale, y: center.y - 24 * scale, width: 48 * scale, height: 38 * scale), xRadius: 7 * scale, yRadius: 7 * scale).fill()
    }

    private func drawCameraGlyph(center: CGPoint, scale: CGFloat) {
        let body = NSRect(x: center.x - 34 * scale, y: center.y - 20 * scale, width: 68 * scale, height: 42 * scale)
        NSColor.white.withAlphaComponent(0.84).setFill()
        NSBezierPath(roundedRect: body, xRadius: 8 * scale, yRadius: 8 * scale).fill()

        let top = NSRect(x: center.x - 18 * scale, y: body.maxY - 1, width: 36 * scale, height: 10 * scale)
        NSBezierPath(roundedRect: top, xRadius: 5 * scale, yRadius: 5 * scale).fill()

        NSColor.systemOrange.withAlphaComponent(0.9).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 13 * scale, y: center.y - 13 * scale, width: 26 * scale, height: 26 * scale)).fill()
        NSColor.white.withAlphaComponent(0.85).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - 6 * scale, y: center.y - 6 * scale, width: 12 * scale, height: 12 * scale)).fill()
    }

    private func drawGenericAppIcon(in rect: NSRect, index: Int) {
        let colors: [NSColor] = [.systemBlue, .systemGreen, .systemOrange]
        colors[index % colors.count].withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
        NSColor.white.withAlphaComponent(0.52).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 12, dy: 12)).fill()
    }

    private func drawSignalBars(in rect: NSRect, color: NSColor, alpha: CGFloat) {
        color.withAlphaComponent(alpha).setFill()
        for index in 0..<4 {
            let height = CGFloat(index + 1) * 5
            let bar = NSRect(x: rect.minX + CGFloat(index) * 16, y: rect.minY, width: 8, height: height)
            NSBezierPath(roundedRect: bar, xRadius: 2, yRadius: 2).fill()
        }
    }

    private func drawResponseArrow(in rect: NSRect, progress: CGFloat) {
        let vector = directionVector
        let center = CGPoint(x: rect.midX + vector.x * 32 * progress, y: rect.midY + vector.y * 26 * progress)
        let start = CGPoint(x: center.x - vector.x * 22, y: center.y - vector.y * 22)
        let end = CGPoint(x: center.x + vector.x * 22, y: center.y + vector.y * 22)

        let arrow = NSBezierPath()
        arrow.move(to: start)
        arrow.line(to: end)
        arrow.lineWidth = 4
        arrow.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.36 + 0.34 * progress).setStroke()
        arrow.stroke()
    }

    private func drawDot(at center: CGPoint, radius: CGFloat, color: NSColor) {
        color.withAlphaComponent(0.22).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - radius - 4, y: center.y - radius - 4, width: (radius + 4) * 2, height: (radius + 4) * 2)).fill()
        color.withAlphaComponent(0.92).setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
    }

    private func fingerPositions(progress: CGFloat) -> [CGPoint] {
        let startEnd = pathPoints
        if isCornerTrigger {
            return [interpolate(from: startEnd.start, to: startEnd.end, progress: progress)]
        }

        let offset = perpendicularOffset
        let firstStart = CGPoint(x: startEnd.start.x + offset.x, y: startEnd.start.y + offset.y)
        let secondStart = CGPoint(x: startEnd.start.x - offset.x, y: startEnd.start.y - offset.y)
        let firstEnd = CGPoint(x: startEnd.end.x + offset.x, y: startEnd.end.y + offset.y)
        let secondEnd = CGPoint(x: startEnd.end.x - offset.x, y: startEnd.end.y - offset.y)
        return [
            interpolate(from: firstStart, to: firstEnd, progress: progress),
            interpolate(from: secondStart, to: secondEnd, progress: progress)
        ]
    }

    private var pathPoints: (start: CGPoint, end: CGPoint) {
        switch trigger {
        case .left:
            return (CGPoint(x: 0.12, y: 0.5), CGPoint(x: 0.52, y: 0.5))
        case .right:
            return (CGPoint(x: 0.88, y: 0.5), CGPoint(x: 0.48, y: 0.5))
        case .top:
            return (CGPoint(x: 0.5, y: 0.86), CGPoint(x: 0.5, y: 0.46))
        case .bottom:
            return (CGPoint(x: 0.5, y: 0.14), CGPoint(x: 0.5, y: 0.54))
        case .topLeft:
            return (CGPoint(x: 0.12, y: 0.86), CGPoint(x: 0.48, y: 0.5))
        case .topRight:
            return (CGPoint(x: 0.88, y: 0.86), CGPoint(x: 0.52, y: 0.5))
        case .bottomLeft:
            return (CGPoint(x: 0.12, y: 0.14), CGPoint(x: 0.48, y: 0.5))
        case .bottomRight:
            return (CGPoint(x: 0.88, y: 0.14), CGPoint(x: 0.52, y: 0.5))
        }
    }

    private var perpendicularOffset: CGPoint {
        switch trigger {
        case .left, .right:
            return CGPoint(x: 0, y: 0.08)
        case .top, .bottom:
            return CGPoint(x: 0.08, y: 0)
        case .topLeft, .topRight, .bottomLeft, .bottomRight:
            return .zero
        }
    }

    private var directionVector: CGPoint {
        let points = pathPoints
        let dx = points.end.x - points.start.x
        let dy = points.end.y - points.start.y
        let length = max(0.01, hypot(dx, dy))
        return CGPoint(x: dx / length, y: dy / length)
    }

    private func responseShift(_ progress: CGFloat) -> CGPoint {
        let vector = directionVector
        return CGPoint(x: vector.x * 16 * progress, y: vector.y * 12 * progress)
    }

    private var isCornerTrigger: Bool {
        GestureTrigger.cornerCases.contains(trigger)
    }

    private var isURLTarget: Bool {
        let trimmed = action.payload.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            return false
        }
        return url.scheme != nil
    }

    private var selectedAppIcon: NSImage? {
        let target = action.payload.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else {
            return nil
        }

        return NSWorkspace.shared.runningApplications.first { app in
            app.bundleIdentifier?.lowercased() == target ||
                app.localizedName?.lowercased() == target
        }?.icon
    }

    private var actionBackgroundColor: NSColor {
        switch action.kind {
        case .disabled:
            return .systemGray
        case .showHUD:
            return .systemIndigo
        case .open:
            return .systemBlue
        case .runShell:
            return .systemGreen
        case .controlCenter:
            return .systemCyan
        case .lockScreen:
            return .black
        case .screenshot:
            return .systemOrange
        case .hideFrontWindow:
            return .systemTeal
        case .restoreHiddenWindow:
            return .systemMint
        case .switchApplication:
            return .systemPurple
        case .missionControl, .appExpose, .showDesktop, .launchpad, .notificationCenter, .startScreenSaver:
            return .systemGray
        }
    }

    private var easedProgress: CGFloat {
        let raw = min(max(phase / 0.72, 0), 1)
        return raw * raw * (3 - 2 * raw)
    }

    private func interpolate(from start: CGPoint, to end: CGPoint, progress: CGFloat) -> CGPoint {
        CGPoint(
            x: start.x + (end.x - start.x) * progress,
            y: start.y + (end.y - start.y) * progress
        )
    }
}
