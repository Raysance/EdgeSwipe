import EdgeSwipeCore
import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Check failed: \(message)\n", stderr)
        exit(1)
    }
}

func checkLeftEdgeSwipe() {
    let recognizer = EdgeGestureRecognizer()

    expect(recognizer.ingest([
        TouchSample(id: 1, x: 0.02, y: 0.45, phase: .began, timestamp: 1.0),
        TouchSample(id: 2, x: 0.03, y: 0.56, phase: .began, timestamp: 1.0)
    ]) == nil, "left edge should not trigger on begin")

    let gesture = recognizer.ingest([
        TouchSample(id: 1, x: 0.32, y: 0.46, phase: .moved, timestamp: 1.2),
        TouchSample(id: 2, x: 0.34, y: 0.55, phase: .moved, timestamp: 1.2)
    ])

    expect(gesture?.trigger == .left, "left edge should trigger after inward travel")
}

func checkTopEdgeSwipe() {
    let recognizer = EdgeGestureRecognizer()

    _ = recognizer.ingest([
        TouchSample(id: 1, x: 0.41, y: 0.98, phase: .began, timestamp: 2.0),
        TouchSample(id: 2, x: 0.54, y: 0.97, phase: .began, timestamp: 2.0)
    ])

    let gesture = recognizer.ingest([
        TouchSample(id: 1, x: 0.40, y: 0.70, phase: .moved, timestamp: 2.2),
        TouchSample(id: 2, x: 0.55, y: 0.69, phase: .moved, timestamp: 2.2)
    ])

    expect(gesture?.trigger == .top, "top edge should trigger after downward travel")
}

func checkDiagonalRejection() {
    var config = EdgeGestureConfig()
    config.maxCrossAxisTravel = 0.08
    let recognizer = EdgeGestureRecognizer(config: config)

    _ = recognizer.ingest([
        TouchSample(id: 1, x: 0.03, y: 0.41, phase: .began, timestamp: 3.0),
        TouchSample(id: 2, x: 0.03, y: 0.55, phase: .began, timestamp: 3.0)
    ])

    let gesture = recognizer.ingest([
        TouchSample(id: 1, x: 0.34, y: 0.55, phase: .moved, timestamp: 3.2),
        TouchSample(id: 2, x: 0.35, y: 0.71, phase: .moved, timestamp: 3.2)
    ])

    expect(gesture == nil, "diagonal movement should be rejected")
}

func checkCornerSwipe() {
    let recognizer = EdgeGestureRecognizer()

    expect(recognizer.ingest([
        TouchSample(id: 1, x: 0.02, y: 0.98, phase: .began, timestamp: 4.0)
    ]) == nil, "corner should not trigger on begin")

    let gesture = recognizer.ingest([
        TouchSample(id: 1, x: 0.24, y: 0.76, phase: .moved, timestamp: 4.2)
    ])

    expect(gesture?.trigger == .topLeft, "top-left corner should trigger after diagonal inward travel")
}

func checkSingleFingerEdgeRejection() {
    let recognizer = EdgeGestureRecognizer()

    _ = recognizer.ingest([
        TouchSample(id: 1, x: 0.02, y: 0.50, phase: .began, timestamp: 5.0)
    ])

    let gesture = recognizer.ingest([
        TouchSample(id: 1, x: 0.25, y: 0.50, phase: .moved, timestamp: 5.2)
    ])

    expect(gesture == nil, "single finger from a non-corner edge should not trigger")
}

func checkIndependentCornerConfig() {
    let edgeConfig = EdgeGestureConfig(edgeBand: 0.03, minTravel: 0.40, maxCrossAxisTravel: 0.04, cooldown: 0.5)
    let cornerConfig = EdgeGestureConfig(edgeBand: 0.10, minTravel: 0.12, maxCrossAxisTravel: 0.20, cooldown: 0.1)
    let recognizer = EdgeGestureRecognizer(edgeConfig: edgeConfig, cornerConfig: cornerConfig)

    _ = recognizer.ingest([
        TouchSample(id: 1, x: 0.07, y: 0.96, phase: .began, timestamp: 6.0)
    ])

    let gesture = recognizer.ingest([
        TouchSample(id: 1, x: 0.22, y: 0.81, phase: .moved, timestamp: 6.2)
    ])

    expect(gesture?.trigger == .topLeft, "corner should use corner config independently from edge config")
}

checkLeftEdgeSwipe()
checkTopEdgeSwipe()
checkDiagonalRejection()
checkCornerSwipe()
checkSingleFingerEdgeRejection()
checkIndependentCornerConfig()
print("EdgeSwipe core checks passed")
