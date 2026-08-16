import Foundation

public enum Edge: String, CaseIterable, Codable, Sendable {
    case left
    case right
    case top
    case bottom

    public var displayName: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .top: return "Top"
        case .bottom: return "Bottom"
        }
    }
}

public enum GestureTrigger: String, CaseIterable, Codable, Sendable {
    case left
    case right
    case top
    case bottom
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    public static let edgeCases: [GestureTrigger] = [.left, .top, .bottom, .right]
    public static let cornerCases: [GestureTrigger] = [.topLeft, .topRight, .bottomLeft, .bottomRight]

    public var displayName: String {
        switch self {
        case .left: return "Left Edge"
        case .right: return "Right Edge"
        case .top: return "Top Edge"
        case .bottom: return "Bottom Edge"
        case .topLeft: return "Top-Left Corner"
        case .topRight: return "Top-Right Corner"
        case .bottomLeft: return "Bottom-Left Corner"
        case .bottomRight: return "Bottom-Right Corner"
        }
    }

    public var shortDisplayName: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }
}

public enum TouchPhase: Sendable {
    case began
    case moved
    case stationary
    case ended
    case cancelled
}

public struct TouchSample: Sendable {
    public let id: Int
    public let x: Double
    public let y: Double
    public let phase: TouchPhase
    public let timestamp: TimeInterval

    public init(id: Int, x: Double, y: Double, phase: TouchPhase, timestamp: TimeInterval) {
        self.id = id
        self.x = x
        self.y = y
        self.phase = phase
        self.timestamp = timestamp
    }
}

public struct EdgeGestureConfig: Codable, Sendable {
    public var edgeBand: Double
    public var minTravel: Double
    public var maxCrossAxisTravel: Double
    public var cooldown: TimeInterval

    public init(
        edgeBand: Double = 0.05,
        minTravel: Double = 0.17,
        maxCrossAxisTravel: Double = 0.20,
        cooldown: TimeInterval = 0.28
    ) {
        self.edgeBand = edgeBand
        self.minTravel = minTravel
        self.maxCrossAxisTravel = maxCrossAxisTravel
        self.cooldown = cooldown
    }
}

public struct EdgeGesture: Equatable, Sendable {
    public let trigger: GestureTrigger
    public let timestamp: TimeInterval
}

public final class EdgeGestureRecognizer {
    public var edgeConfig: EdgeGestureConfig
    public var cornerConfig: EdgeGestureConfig

    public var config: EdgeGestureConfig {
        get {
            edgeConfig
        }
        set {
            edgeConfig = newValue
            cornerConfig = newValue
        }
    }

    private struct Session {
        let trigger: GestureTrigger
        let ids: Set<Int>
        let startX: Double
        let startY: Double
        var didTrigger: Bool
    }

    private var session: Session?
    private var lastTriggerAt: [GestureTrigger: TimeInterval] = [:]

    public init(config: EdgeGestureConfig = EdgeGestureConfig()) {
        self.edgeConfig = config
        self.cornerConfig = config
    }

    public init(edgeConfig: EdgeGestureConfig, cornerConfig: EdgeGestureConfig) {
        self.edgeConfig = edgeConfig
        self.cornerConfig = cornerConfig
    }

    public func reset() {
        session = nil
        lastTriggerAt = [:]
    }

    public func ingest(_ samples: [TouchSample]) -> EdgeGesture? {
        let activeSamples = samples.filter { sample in
            switch sample.phase {
            case .began, .moved, .stationary:
                return true
            case .ended, .cancelled:
                return false
            }
        }

        guard activeSamples.count == 1 || activeSamples.count == 2 else {
            if activeSamples.isEmpty {
                session = nil
            }
            return nil
        }

        let ids = Set(activeSamples.map(\.id))
        let sampleCount = Double(activeSamples.count)
        let averageX = activeSamples.map(\.x).reduce(0, +) / sampleCount
        let averageY = activeSamples.map(\.y).reduce(0, +) / sampleCount
        let timestamp = activeSamples.map(\.timestamp).max() ?? 0

        if session == nil || session?.ids != ids {
            guard let trigger = triggerForStart(activeSamples) else {
                session = nil
                return nil
            }

            session = Session(
                trigger: trigger,
                ids: ids,
                startX: averageX,
                startY: averageY,
                didTrigger: false
            )
            return nil
        }

        guard var current = session, !current.didTrigger else {
            return nil
        }

        guard hasMovedInward(from: current.trigger, startX: current.startX, startY: current.startY, x: averageX, y: averageY) else {
            session = current
            return nil
        }

        let last = lastTriggerAt[current.trigger] ?? -.infinity
        guard timestamp - last >= config(for: current.trigger).cooldown else {
            current.didTrigger = true
            session = current
            return nil
        }

        current.didTrigger = true
        session = current
        lastTriggerAt[current.trigger] = timestamp
        return EdgeGesture(trigger: current.trigger, timestamp: timestamp)
    }

    private func triggerForStart(_ samples: [TouchSample]) -> GestureTrigger? {
        if samples.count == 1 {
            return cornerForStart(samples[0])
        }

        guard samples.count == 2 else {
            return nil
        }

        let band = edgeConfig.edgeBand
        let allLeft = samples.allSatisfy { $0.x <= band }
        let allRight = samples.allSatisfy { $0.x >= 1.0 - band }
        let allBottom = samples.allSatisfy { $0.y <= band }
        let allTop = samples.allSatisfy { $0.y >= 1.0 - band }

        if allLeft { return .left }
        if allRight { return .right }
        if allTop { return .top }
        if allBottom { return .bottom }
        return nil
    }

    private func cornerForStart(_ sample: TouchSample) -> GestureTrigger? {
        let band = cornerConfig.edgeBand
        let left = sample.x <= band
        let right = sample.x >= 1.0 - band
        let bottom = sample.y <= band
        let top = sample.y >= 1.0 - band

        if top && left { return .topLeft }
        if top && right { return .topRight }
        if bottom && left { return .bottomLeft }
        if bottom && right { return .bottomRight }
        return nil
    }

    private func hasMovedInward(from trigger: GestureTrigger, startX: Double, startY: Double, x: Double, y: Double) -> Bool {
        let config = config(for: trigger)

        switch trigger {
        case .left:
            return x - startX >= config.minTravel && abs(y - startY) <= config.maxCrossAxisTravel
        case .right:
            return startX - x >= config.minTravel && abs(y - startY) <= config.maxCrossAxisTravel
        case .top:
            return startY - y >= config.minTravel && abs(x - startX) <= config.maxCrossAxisTravel
        case .bottom:
            return y - startY >= config.minTravel && abs(x - startX) <= config.maxCrossAxisTravel
        case .topLeft:
            return diagonalMovedInward(horizontal: x - startX, vertical: startY - y, config: config)
        case .topRight:
            return diagonalMovedInward(horizontal: startX - x, vertical: startY - y, config: config)
        case .bottomLeft:
            return diagonalMovedInward(horizontal: x - startX, vertical: y - startY, config: config)
        case .bottomRight:
            return diagonalMovedInward(horizontal: startX - x, vertical: y - startY, config: config)
        }
    }

    private func diagonalMovedInward(horizontal: Double, vertical: Double, config: EdgeGestureConfig) -> Bool {
        horizontal >= config.minTravel &&
            vertical >= config.minTravel &&
            abs(horizontal - vertical) <= config.maxCrossAxisTravel
    }

    private func config(for trigger: GestureTrigger) -> EdgeGestureConfig {
        GestureTrigger.cornerCases.contains(trigger) ? cornerConfig : edgeConfig
    }
}
