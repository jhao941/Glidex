import CoreGraphics
import Foundation

enum GestureSynthesizer {
    enum Step {
        case singleTouch(point: CGPoint, direction: TouchDirection, description: String)
        case twoFingerTouch(finger1: CGPoint, finger2: CGPoint, direction: TouchDirection, description: String)
        case delay(TimeInterval, description: String)
    }

    static func tap(point: CGPoint, holdDuration: TimeInterval? = 0.06) -> [Step] {
        var steps: [Step] = [
            .singleTouch(point: point, direction: .down, description: "tap down point=(\(point.x), \(point.y))")
        ]
        if let holdDuration, holdDuration > 0 {
            steps.append(.delay(holdDuration, description: "tap hold delay=\(holdDuration)"))
        }
        steps.append(.singleTouch(point: point, direction: .up, description: "tap up point=(\(point.x), \(point.y))"))
        return steps
    }

    static func drag(from: CGPoint, to: CGPoint, duration: TimeInterval, delta: CGFloat = 10) -> [Step] {
        let distance = hypot(to.x - from.x, to.y - from.y)
        let effectiveDelta = delta > 0 ? delta : 10
        let steps = max(1, Int(distance / effectiveDelta))
        let dx = (to.x - from.x) / CGFloat(steps)
        let dy = (to.y - from.y) / CGFloat(steps)
        let stepDelay = duration / Double(steps + 2)

        var sequence: [Step] = []
        for index in 0...steps {
            let point = CGPoint(x: from.x + dx * CGFloat(index), y: from.y + dy * CGFloat(index))
            sequence.append(.singleTouch(point: point, direction: .down, description: "drag down[\(index)] point=(\(point.x), \(point.y))"))
            sequence.append(.delay(stepDelay, description: "drag delay[\(index)] duration=\(stepDelay)"))
        }

        let finalPoint = CGPoint(x: from.x + dx * CGFloat(steps), y: from.y + dy * CGFloat(steps))
        sequence.append(.singleTouch(point: finalPoint, direction: .down, description: "drag final-repeat point=(\(finalPoint.x), \(finalPoint.y))"))
        sequence.append(.delay(stepDelay, description: "drag final-repeat delay=\(stepDelay)"))
        sequence.append(.singleTouch(point: to, direction: .up, description: "drag up point=(\(to.x), \(to.y))"))
        return sequence
    }

    static func pinch(center: CGPoint, scale: Double, duration: TimeInterval, radius: CGFloat = 40, delta: CGFloat = 10) -> [Step] {
        let startRadius = radius
        let endRadius = radius * CGFloat(scale)
        let fingerDistance = abs(endRadius - startRadius)
        let effectiveDelta = delta > 0 ? delta : 10
        let steps = max(2, Int(fingerDistance / effectiveDelta))
        let stepDelay = duration / Double(steps + 2)
        let radiusStep = (endRadius - startRadius) / CGFloat(steps)

        func fingers(radius: CGFloat) -> (CGPoint, CGPoint) {
            (
                CGPoint(x: center.x - radius, y: center.y),
                CGPoint(x: center.x + radius, y: center.y)
            )
        }

        var sequence: [Step] = []
        let start = fingers(radius: startRadius)
        sequence.append(.twoFingerTouch(finger1: start.0, finger2: start.1, direction: .down, description: "pinch began a=(\(start.0.x), \(start.0.y)) b=(\(start.1.x), \(start.1.y))"))
        sequence.append(.delay(stepDelay, description: "pinch delay[0] duration=\(stepDelay)"))

        for index in 1...steps {
            let radius = startRadius + radiusStep * CGFloat(index)
            let frame = fingers(radius: radius)
            sequence.append(.twoFingerTouch(finger1: frame.0, finger2: frame.1, direction: .down, description: "pinch frame[\(index)] a=(\(frame.0.x), \(frame.0.y)) b=(\(frame.1.x), \(frame.1.y))"))
            sequence.append(.delay(stepDelay, description: "pinch delay[\(index)] duration=\(stepDelay)"))
        }

        let final = fingers(radius: endRadius)
        sequence.append(.twoFingerTouch(finger1: final.0, finger2: final.1, direction: .down, description: "pinch final-repeat a=(\(final.0.x), \(final.0.y)) b=(\(final.1.x), \(final.1.y))"))
        sequence.append(.delay(stepDelay, description: "pinch final-repeat delay=\(stepDelay)"))
        sequence.append(.twoFingerTouch(finger1: final.0, finger2: final.1, direction: .up, description: "pinch ended a=(\(final.0.x), \(final.0.y)) b=(\(final.1.x), \(final.1.y))"))
        return sequence
    }
}
