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
        edgeBand: Double = 0.08,
        minTravel: Double = 0.22,
        maxCrossAxisTravel: Double = 0.18,
        cooldown: TimeInterval = 0.7
    ) {
        self.edgeBand = edgeBand
        self.minTravel = minTravel
        self.maxCrossAxisTravel = maxCrossAxisTravel
        self.cooldown = cooldown
    }
}

public struct EdgeGesture: Equatable, Sendable {
    public let edge: Edge
    public let timestamp: TimeInterval
}

public final class EdgeGestureRecognizer {
    public var config: EdgeGestureConfig

    private struct Session {
        let edge: Edge
        let ids: Set<Int>
        let startX: Double
        let startY: Double
        var didTrigger: Bool
    }

    private var session: Session?
    private var lastTriggerAt: [Edge: TimeInterval] = [:]

    public init(config: EdgeGestureConfig = EdgeGestureConfig()) {
        self.config = config
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

        guard activeSamples.count == 2 else {
            if activeSamples.isEmpty {
                session = nil
            }
            return nil
        }

        let ids = Set(activeSamples.map(\.id))
        let averageX = activeSamples.map(\.x).reduce(0, +) / 2.0
        let averageY = activeSamples.map(\.y).reduce(0, +) / 2.0
        let timestamp = activeSamples.map(\.timestamp).max() ?? 0

        if session == nil || session?.ids != ids {
            guard let edge = edgeForStart(activeSamples) else {
                session = nil
                return nil
            }

            session = Session(
                edge: edge,
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

        guard hasMovedInward(from: current.edge, startX: current.startX, startY: current.startY, x: averageX, y: averageY) else {
            session = current
            return nil
        }

        let last = lastTriggerAt[current.edge] ?? -.infinity
        guard timestamp - last >= config.cooldown else {
            current.didTrigger = true
            session = current
            return nil
        }

        current.didTrigger = true
        session = current
        lastTriggerAt[current.edge] = timestamp
        return EdgeGesture(edge: current.edge, timestamp: timestamp)
    }

    private func edgeForStart(_ samples: [TouchSample]) -> Edge? {
        let band = config.edgeBand
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

    private func hasMovedInward(from edge: Edge, startX: Double, startY: Double, x: Double, y: Double) -> Bool {
        switch edge {
        case .left:
            return x - startX >= config.minTravel && abs(y - startY) <= config.maxCrossAxisTravel
        case .right:
            return startX - x >= config.minTravel && abs(y - startY) <= config.maxCrossAxisTravel
        case .top:
            return startY - y >= config.minTravel && abs(x - startX) <= config.maxCrossAxisTravel
        case .bottom:
            return y - startY >= config.minTravel && abs(x - startX) <= config.maxCrossAxisTravel
        }
    }
}
