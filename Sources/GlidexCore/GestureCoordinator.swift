import Foundation
@MainActor
public final class GestureCoordinator {
    private let sink: TouchSink
    private let logger: Logger

    private var mapper: CoordinateMapper
    private var interpreter = GestureInterpreter()
    private var mouseState = MouseGestureStateMachine()
    private var activeTransaction: TouchTransaction?
    private var lastMousePoint: SimulatorPoint?
    private var pinchInitialRadius: CGFloat = 72
    private var pinchCurrentRadius: CGFloat = 72

    public private(set) var mode: CaptureInputMode = .navigate
    public private(set) var virtualFingerPoint: SimulatorPoint?
    public var onStateChange: (() -> Void)?
    public var inputStatus: String { activeTransaction == nil ? "idle" : "active" }

    public init(mapper: CoordinateMapper, sink: TouchSink, logger: Logger) {
        self.mapper = mapper
        self.sink = sink
        self.logger = logger
    }

    public func updateMapper(_ mapper: CoordinateMapper) {
        self.mapper = mapper
        if virtualFingerPoint == nil {
            virtualFingerPoint = SimulatorPoint(
                x: mapper.simulatorSize.width / 2,
                y: mapper.simulatorSize.height / 2
            )
        }
    }

    public func updatePointer(_ point: CapturePoint) {
        guard mode == .point || mode == .edge,
              let simulatorPoint = mapper.simulatorPoint(fromCapture: point) else { return }
        lastMousePoint = simulatorPoint
        virtualFingerPoint = simulatorPoint
        onStateChange?()
    }

    public func setMode(_ mode: CaptureInputMode) {
        guard self.mode != mode else { return }
        cancelAll(reason: "input mode changed")
        self.mode = mode
        onStateChange?()
    }

    public func beginMouse(at point: CapturePoint) {
        guard mode != .disabled else { return }
        if mode == .point || mode == .edge {
            updatePointer(point)
            return
        }
        cancelActive(reason: "mouse input began")
        guard let simulatorPoint = mapper.simulatorPoint(fromCapture: point) else { return }
        lastMousePoint = simulatorPoint
        handleMouseActions(mouseState.mouseDown(capture: point, simulator: simulatorPoint))
    }

    public func updateMouse(at point: CapturePoint) {
        if mode == .point || mode == .edge {
            updatePointer(point)
            return
        }
        guard mode != .disabled else { return }
        guard let simulatorPoint = mapper.projectedSimulatorPoint(fromCapture: point) else { return }
        handleMouseActions(mouseState.mouseDragged(capture: point, simulator: simulatorPoint))
    }

    public func endMouse(at point: CapturePoint?) {
        if mode == .point || mode == .edge || mode == .disabled { return }
        guard let point, let simulatorPoint = mapper.projectedSimulatorPoint(fromCapture: point) else {
            handleMouseAction(mouseState.cancel())
            return
        }
        handleMouseActions(mouseState.mouseUp(capture: point, simulator: simulatorPoint))
    }

    public func handleRawFrame(_ frame: RawTouchFrame) {
        guard mode != .disabled else { return }
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

    public func cancelAll(reason: String) {
        _ = interpreter.cancel()
        handleMouseAction(mouseState.cancel())
        cancelActive(reason: reason)
    }

    public func prepareForDeviceChange() {
        cancelAll(reason: "simulator device changing")
        (sink as? DeviceAwareTouchSink)?.prepareForDeviceChange()
    }

    private func beginRawGesture(_ gesture: InterpretedGesture) {
        handleMouseAction(mouseState.cancel())
        cancelActive(reason: "raw gesture began")
        let fallback = mapper.simulatorPoint(fromNormalizedTouch: gesture.initialCentroid)
        let policy = anchorPolicy(fallback: fallback)
        let anchor = policy.resolve(
            fallback: fallback,
            simulatorSize: mapper.simulatorSize
        )
        let transaction = TouchTransaction(
            source: .rawTrackpad,
            intent: mode == .edge ? .edge : gesture.intent,
            anchor: anchor,
            sink: sink
        )
        activeTransaction = transaction
        onStateChange?()

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
        onStateChange?()
    }

    private func cancelActive(reason: String) {
        guard let transaction = activeTransaction else { return }
        if transaction.cancel() {
            logger.info("touch transaction cancelled gestureID=\(transaction.gestureID) reason=\(reason)")
        }
        activeTransaction = nil
        onStateChange?()
    }

    private func handleMouseActions(_ actions: [MouseGestureAction]) {
        for action in actions { handleMouseAction(action) }
    }

    private func handleMouseAction(_ action: MouseGestureAction?) {
        guard let action else { return }
        switch action {
        case let .tap(point):
            let transaction = makeMouseTransaction(anchor: point)
            let contact = [TouchContactPoint(identifier: 0, point: point)]
            transaction.begin(contacts: contact)
            transaction.end(contacts: contact)
        case let .beginDrag(start, current):
            let transaction = makeMouseTransaction(anchor: start)
            activeTransaction = transaction
            onStateChange?()
            transaction.begin(contacts: [TouchContactPoint(identifier: 0, point: start)])
            transaction.update(contacts: [TouchContactPoint(identifier: 0, point: current)])
        case let .updateDrag(point):
            activeTransaction?.update(contacts: [TouchContactPoint(identifier: 0, point: point)])
        case let .endDrag(point):
            activeTransaction?.end(contacts: [TouchContactPoint(identifier: 0, point: point)])
            activeTransaction = nil
            onStateChange?()
        case .cancelDrag:
            cancelActive(reason: "mouse drag cancelled")
        }
    }

    private func makeMouseTransaction(anchor: SimulatorPoint) -> TouchTransaction {
        TouchTransaction(source: .mouse, intent: .point, anchor: anchor, sink: sink)
    }

    private func navigationPoint(for gesture: InterpretedGesture, anchor: SimulatorPoint) -> SimulatorPoint {
        let gain = InputTuning.stable.navigationGain
        return SimulatorPoint(
            x: anchor.x + (gesture.centroid.x - gesture.initialCentroid.x) * mapper.simulatorSize.width * gain,
            y: anchor.y + (gesture.initialCentroid.y - gesture.centroid.y) * mapper.simulatorSize.height * gain
        )
    }

    public func capturePointForVirtualFinger() -> CapturePoint? {
        virtualFingerPoint.flatMap(mapper.capturePoint(fromSimulator:))
    }

    private func anchorPolicy(fallback: SimulatorPoint) -> AnchorPolicy {
        switch mode {
        case .navigate:
            return .navigate
        case .point:
            return .point(virtualFingerPoint ?? lastMousePoint)
        case .edge:
            let reference = virtualFingerPoint ?? fallback
            return .edge(AnchorPolicy.nearestEdge(to: reference, simulatorSize: mapper.simulatorSize))
        case .disabled:
            return .navigate
        }
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
