import Foundation
import GlidexCore

@MainActor
final class GestureCoordinator {
    private let sink: TouchSink
    private let logger: Logger

    private var mapper: CoordinateMapper
    private var interpreter = GestureInterpreter()
    private var activeTransaction: TouchTransaction?
    private var lastMousePoint: SimulatorPoint?
    private var pinchInitialRadius: CGFloat = 72
    private var pinchCurrentRadius: CGFloat = 72

    init(mapper: CoordinateMapper, sink: TouchSink, logger: Logger) {
        self.mapper = mapper
        self.sink = sink
        self.logger = logger
    }

    func updateMapper(_ mapper: CoordinateMapper) {
        self.mapper = mapper
    }

    func updatePointer(_ point: CapturePoint) {
        guard let simulatorPoint = mapper.simulatorPoint(fromCapture: point) else { return }
        lastMousePoint = simulatorPoint
    }

    func beginMouse(at point: CapturePoint) {
        cancelActive(reason: "mouse input began")
        guard let simulatorPoint = mapper.simulatorPoint(fromCapture: point) else { return }
        lastMousePoint = simulatorPoint
        let transaction = TouchTransaction(
            source: .mouse,
            intent: .point,
            anchor: simulatorPoint,
            sink: sink
        )
        activeTransaction = transaction
        transaction.begin(contacts: [TouchContactPoint(identifier: 0, point: simulatorPoint)])
    }

    func updateMouse(at point: CapturePoint) {
        guard let simulatorPoint = mapper.simulatorPoint(fromCapture: point) else {
            cancelActive(reason: "mouse left capture bounds")
            return
        }
        lastMousePoint = simulatorPoint
        guard activeTransaction?.source == .mouse else { return }
        activeTransaction?.update(contacts: [TouchContactPoint(identifier: 0, point: simulatorPoint)])
    }

    func endMouse(at point: CapturePoint?) {
        guard activeTransaction?.source == .mouse else { return }
        let contacts = point
            .flatMap(mapper.simulatorPoint(fromCapture:))
            .map { [TouchContactPoint(identifier: 0, point: $0)] }
        activeTransaction?.end(contacts: contacts)
        activeTransaction = nil
    }

    func handleRawFrame(_ frame: RawTouchFrame) {
        guard let output = interpreter.consume(frame) else { return }
        switch output {
        case .pending:
            break
        case let .began(gesture):
            beginRawGesture(gesture)
        case let .changed(gesture):
            updateRawGesture(gesture)
        case .ended:
            endRawGesture()
        }
    }

    func cancelAll(reason: String) {
        _ = interpreter.cancel()
        cancelActive(reason: reason)
    }

    private func beginRawGesture(_ gesture: InterpretedGesture) {
        cancelActive(reason: "raw gesture began")
        let fallback = mapper.simulatorPoint(fromNormalizedTouch: gesture.initialCentroid)
        let anchor = AnchorPolicy.point(lastMousePoint).resolve(
            fallback: fallback,
            simulatorSize: mapper.simulatorSize
        )
        let transaction = TouchTransaction(
            source: .rawTrackpad,
            intent: gesture.intent,
            anchor: anchor,
            sink: sink
        )
        activeTransaction = transaction

        switch gesture.intent {
        case .navigate:
            transaction.begin(contacts: [TouchContactPoint(identifier: 0, point: navigationPoint(for: gesture, anchor: anchor))])
        case .pinch:
            pinchInitialRadius = initialPinchRadius(anchor: anchor)
            pinchCurrentRadius = pinchInitialRadius
            transaction.begin(contacts: pinchContacts(for: gesture, anchor: anchor))
        default:
            break
        }
    }

    private func updateRawGesture(_ gesture: InterpretedGesture) {
        guard let transaction = activeTransaction, transaction.source == .rawTrackpad else { return }
        switch gesture.intent {
        case .navigate:
            transaction.update(contacts: [TouchContactPoint(
                identifier: 0,
                point: navigationPoint(for: gesture, anchor: transaction.anchor)
            )])
        case .pinch:
            transaction.update(contacts: pinchContacts(for: gesture, anchor: transaction.anchor))
        default:
            break
        }
    }

    private func endRawGesture() {
        guard activeTransaction?.source == .rawTrackpad else { return }
        activeTransaction?.end()
        activeTransaction = nil
    }

    private func cancelActive(reason: String) {
        guard let transaction = activeTransaction else { return }
        if transaction.cancel() {
            logger.info("touch transaction cancelled gestureID=\(transaction.gestureID) reason=\(reason)")
        }
        activeTransaction = nil
    }

    private func navigationPoint(for gesture: InterpretedGesture, anchor: SimulatorPoint) -> SimulatorPoint {
        let gain: CGFloat = 1.35
        return mapper.clamped(SimulatorPoint(
            x: anchor.x + (gesture.centroid.x - gesture.initialCentroid.x) * mapper.simulatorSize.width * gain,
            y: anchor.y + (gesture.initialCentroid.y - gesture.centroid.y) * mapper.simulatorSize.height * gain
        ))
    }

    private func initialPinchRadius(anchor: SimulatorPoint) -> CGFloat {
        let screenMaxRadius = min(mapper.simulatorSize.width, mapper.simulatorSize.height) * 0.34
        let edgeMaxRadius = min(anchor.x, mapper.simulatorSize.width - anchor.x)
        return min(72, max(24, min(screenMaxRadius, edgeMaxRadius)))
    }

    private func pinchContacts(for gesture: InterpretedGesture, anchor: SimulatorPoint) -> [TouchContactPoint] {
        let distanceDelta = gesture.distance - gesture.initialDistance
        let radiusGain = min(mapper.simulatorSize.width, mapper.simulatorSize.height) * 0.45
        let targetRadius = clampedPinchRadius(pinchInitialRadius + distanceDelta * radiusGain)
        let filteredTarget = pinchCurrentRadius * 0.82 + targetRadius * 0.18
        let step = min(max(filteredTarget - pinchCurrentRadius, -2.5), 2.5)
        pinchCurrentRadius = clampedPinchRadius(pinchCurrentRadius + step)

        return [
            TouchContactPoint(identifier: 0, point: mapper.clamped(SimulatorPoint(x: anchor.x - pinchCurrentRadius, y: anchor.y))),
            TouchContactPoint(identifier: 1, point: mapper.clamped(SimulatorPoint(x: anchor.x + pinchCurrentRadius, y: anchor.y))),
        ]
    }

    private func clampedPinchRadius(_ radius: CGFloat) -> CGFloat {
        min(max(radius, 32), min(mapper.simulatorSize.width, mapper.simulatorSize.height) * 0.34)
    }
}
