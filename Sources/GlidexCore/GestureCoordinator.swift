import Foundation
@MainActor
public final class GestureCoordinator {
    private enum InputOwner {
        case mouse
        case rawTouch
    }

    private enum DirectTouchState {
        case idle
        case trackingSingleContact
        case blockedUntilRelease
    }

    private struct RawGestureDiagnostics {
        let gestureID: UUID
        let startedAt: TimeInterval
        let initialCentroid: NormalizedTouchPoint
        let initialSimulatorPoint: SimulatorPoint
        var lastCentroid: NormalizedTouchPoint
        var lastSimulatorPoint: SimulatorPoint
        var maximumCentroidDistance: CGFloat = 0
        var maximumSimulatorDistance: CGFloat = 0
        var updateCount = 0
    }

    private let sink: TouchSink
    private let logger: Logger
    private var rawGestureInputProvider: () -> GestureInputSample

    private var mapper: CoordinateMapper
    private var interpreter = GestureInterpreter()
    private var directTouchMapper: DirectTouchMapper
    private var directTouchState: DirectTouchState = .idle
    private var activeTransaction: TouchTransaction?
    private var lastMousePoint: SimulatorPoint?
    private var pinchInitialRadius: CGFloat = 72
    private var pinchCurrentRadius: CGFloat = 72
    private var pinchCurrentAngle: CGFloat = 0
    private var rawGestureDiagnostics: RawGestureDiagnostics?
    private var inputOwner: InputOwner?

    public private(set) var mode: CaptureInputMode = .navigate
    public private(set) var isAnchorLocked = false
    public private(set) var virtualFingerPoint: SimulatorPoint?
    public private(set) var activeGestureContext: GestureInputContext?
    public var onStateChange: (() -> Void)?
    public var inputStatus: String { activeTransaction == nil ? "idle" : "active" }

    public init(
        mapper: CoordinateMapper,
        sink: TouchSink,
        logger: Logger,
        rawGestureInputProvider: @escaping () -> GestureInputSample = { .none }
    ) {
        self.mapper = mapper
        self.directTouchMapper = DirectTouchMapper(coordinateMapper: mapper)
        self.sink = sink
        self.logger = logger
        self.rawGestureInputProvider = rawGestureInputProvider
    }

    public func updateMapper(_ mapper: CoordinateMapper) {
        self.mapper = mapper
        directTouchMapper.updateCoordinateMapper(mapper)
        if virtualFingerPoint == nil {
            virtualFingerPoint = SimulatorPoint(
                x: mapper.simulatorSize.width / 2,
                y: mapper.simulatorSize.height / 2
            )
        } else if let virtualFingerPoint {
            self.virtualFingerPoint = mapper.clamped(virtualFingerPoint)
        }
        onStateChange?()
    }

    public func setRawGestureInputProvider(_ provider: @escaping () -> GestureInputSample) {
        rawGestureInputProvider = provider
    }

    public func updatePointer(_ point: CapturePoint) {
        guard !isAnchorLocked, mode == .point || mode == .edge,
              let simulatorPoint = mapper.simulatorPoint(fromCapture: point) else { return }
        lastMousePoint = simulatorPoint
        virtualFingerPoint = simulatorPoint
        onStateChange?()
    }

    public func setMode(_ mode: CaptureInputMode) {
        guard self.mode != mode else { return }
        cancelAll(reason: "input mode changed")
        self.mode = mode
        if !mode.supportsAnchor { isAnchorLocked = false }
        onStateChange?()
    }

    public func setAnchorLocked(_ locked: Bool) {
        let effective = mode.supportsAnchor && locked
        guard isAnchorLocked != effective else { return }
        cancelAll(reason: "anchor lock changed")
        isAnchorLocked = effective
        onStateChange?()
    }

    public func beginMouse(at point: CapturePoint) {
        guard mode != .disabled, mode != .directTouch else { return }
        guard inputOwner != .rawTouch else { return }
        inputOwner = .mouse
        if AnchorEditingPolicy.accepts(.down, mode: mode, isLocked: isAnchorLocked) {
            updatePointer(point)
            return
        }
        cancelActive(reason: "mouse input began")
        guard let simulatorPoint = mapper.simulatorPoint(fromCapture: point) else { return }
        lastMousePoint = simulatorPoint
        let transaction = makeMouseTransaction(anchor: simulatorPoint)
        activeTransaction = transaction
        transaction.begin(contacts: [TouchContactPoint(identifier: 0, point: simulatorPoint)])
        onStateChange?()
    }

    public func updateMouse(at point: CapturePoint) {
        guard inputOwner == .mouse else { return }
        if AnchorEditingPolicy.accepts(.drag, mode: mode, isLocked: isAnchorLocked) {
            updatePointer(point)
            return
        }
        guard mode != .disabled else { return }
        guard let simulatorPoint = mapper.projectedSimulatorPoint(fromCapture: point) else { return }
        activeTransaction?.update(contacts: [TouchContactPoint(identifier: 0, point: simulatorPoint)])
    }

    public func endMouse(at point: CapturePoint?) {
        guard inputOwner == .mouse else { return }
        defer { inputOwner = nil }
        if ((mode == .point || mode == .edge) && !isAnchorLocked) || mode == .disabled { return }
        guard let point, let simulatorPoint = mapper.projectedSimulatorPoint(fromCapture: point) else {
            cancelActive(reason: "mouse input ended outside capture")
            return
        }
        activeTransaction?.end(contacts: [TouchContactPoint(identifier: 0, point: simulatorPoint)])
        activeTransaction = nil
        onStateChange?()
    }

    public func handleRawFrame(_ frame: RawTouchFrame) {
        guard mode != .disabled else { return }
        if mode == .directTouch {
            handleDirectTouchFrame(frame)
            return
        }
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
        _ = directTouchMapper.cancel()
        directTouchState = .idle
        cancelActive(reason: reason)
        inputOwner = nil
    }

    public func prepareForDeviceChange() {
        cancelAll(reason: "simulator device changing")
        virtualFingerPoint = nil
        lastMousePoint = nil
        (sink as? DeviceAwareTouchSink)?.prepareForDeviceChange()
        onStateChange?()
    }

    private func beginRawGesture(_ gesture: InterpretedGesture) {
        cancelActive(reason: "raw gesture began")
        inputOwner = .rawTouch
        let fallback = mapper.simulatorPoint(fromNormalizedTouch: gesture.initialCentroid)
        let sample = rawGestureInputProvider()
        let simulatorMouseLocation = sample.captureMouseLocation.flatMap(mapper.simulatorPoint(fromCapture:))
        let context = GestureInputContext.resolve(
            persistentMode: mode,
            optionPressed: sample.optionPressed,
            globalMouseLocation: sample.globalMouseLocation,
            simulatorMouseLocation: simulatorMouseLocation,
            fixedPoint: virtualFingerPoint ?? lastMousePoint,
            fallback: fallback,
            simulatorSize: mapper.simulatorSize
        )
        let anchor = context.anchorPolicy.resolve(
            fallback: fallback,
            simulatorSize: mapper.simulatorSize
        )
        let transaction = TouchTransaction(
            source: .rawTrackpad,
            intent: context.persistentMode == .edge ? .edge : gesture.intent,
            anchor: anchor,
            sink: sink
        )
        activeGestureContext = context
        activeTransaction = transaction
        let initialSimulatorPoint = navigationPoint(for: gesture, anchor: anchor)
        let resolvedCentroidDistance = distance(from: gesture.initialCentroid, to: gesture.centroid)
        rawGestureDiagnostics = RawGestureDiagnostics(
            gestureID: transaction.gestureID,
            startedAt: ProcessInfo.processInfo.systemUptime,
            initialCentroid: gesture.initialCentroid,
            initialSimulatorPoint: initialSimulatorPoint,
            lastCentroid: gesture.centroid,
            lastSimulatorPoint: initialSimulatorPoint,
            maximumCentroidDistance: resolvedCentroidDistance
        )
        logger.info(
            "event=input-diagnostic path=rawGesture phase=begin gestureID=\(transaction.gestureID) " +
                "intent=\(gesture.intent.rawValue) contacts=\(gesture.contactIDs.map(String.init).joined(separator: ",")) " +
                "centroidInitial=\(format(gesture.initialCentroid.x)),\(format(gesture.initialCentroid.y)) " +
                "centroidResolved=\(format(gesture.centroid.x)),\(format(gesture.centroid.y)) " +
                "centroidResolvedDistance=\(format(resolvedCentroidDistance)) " +
                "simulatorPoint=\(format(initialSimulatorPoint.x)),\(format(initialSimulatorPoint.y))"
        )
        onStateChange?()

        switch gesture.intent {
        case .navigate:
            transaction.begin(contacts: [TouchContactPoint(identifier: 0, point: navigationPoint(for: gesture, anchor: anchor))])
        case .pinch:
            pinchInitialRadius = initialPinchRadius(anchor: anchor)
            pinchCurrentRadius = pinchInitialRadius
            pinchCurrentAngle = 0
            transaction.begin(contacts: pinchContacts(for: gesture, anchor: anchor))
        default:
            break
        }
    }

    private func handleDirectTouchFrame(_ frame: RawTouchFrame) {
        let activeContactCount = frame.contacts.filter(\.isActive).count
        switch directTouchState {
        case .blockedUntilRelease:
            if activeContactCount == 0 {
                directTouchState = .idle
            }
            return
        case .idle, .trackingSingleContact:
            if activeContactCount > 1 {
                _ = directTouchMapper.cancel()
                cancelActive(reason: "Direct Touch single-contact limit exceeded")
                inputOwner = nil
                directTouchState = .blockedUntilRelease
                return
            }
        }

        guard let output = directTouchMapper.consume(frame) else { return }
        switch output {
        case let .began(contacts):
            guard let contact = contacts.first else { return }
            cancelActive(reason: "Direct Touch began")
            inputOwner = .rawTouch
            directTouchState = .trackingSingleContact
            let transaction = TouchTransaction(
                source: .rawTrackpad,
                intent: .directTouch,
                anchor: contact.point,
                sink: sink
            )
            activeTransaction = transaction
            transaction.begin(contacts: contacts)
            logger.info("event=input-diagnostic path=directTouch phase=begin gestureID=\(transaction.gestureID) contacts=1")
            onStateChange?()
        case let .changed(contacts):
            activeTransaction?.update(contacts: contacts)
        case let .ended(contacts):
            activeTransaction?.end(contacts: contacts)
            activeTransaction = nil
            inputOwner = nil
            directTouchState = .idle
            logger.info("event=input-diagnostic path=directTouch phase=end contacts=0")
            onStateChange?()
        case .cancelled:
            cancelActive(reason: "Direct Touch cancelled")
            inputOwner = nil
            directTouchState = .idle
        }
    }

    private func updateRawGesture(_ gesture: InterpretedGesture) {
        guard let transaction = activeTransaction, transaction.source == .rawTrackpad else { return }
        updateRawGestureDiagnostics(gesture, anchor: transaction.anchor)
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
        guard inputOwner == .rawTouch else { return }
        defer { inputOwner = nil }
        guard activeTransaction?.source == .rawTrackpad else { return }
        logRawGestureDiagnostics()
        activeTransaction?.end()
        activeTransaction = nil
        activeGestureContext = nil
        rawGestureDiagnostics = nil
        onStateChange?()
    }

    private func cancelActive(reason: String) {
        guard let transaction = activeTransaction else { return }
        if transaction.cancel() {
            logger.info("touch transaction cancelled gestureID=\(transaction.gestureID) reason=\(reason)")
        }
        activeTransaction = nil
        activeGestureContext = nil
        rawGestureDiagnostics = nil
        onStateChange?()
    }

    private func updateRawGestureDiagnostics(_ gesture: InterpretedGesture, anchor: SimulatorPoint) {
        guard var diagnostics = rawGestureDiagnostics else { return }
        let simulatorPoint = navigationPoint(for: gesture, anchor: anchor)
        diagnostics.lastCentroid = gesture.centroid
        diagnostics.lastSimulatorPoint = simulatorPoint
        diagnostics.maximumCentroidDistance = max(
            diagnostics.maximumCentroidDistance,
            distance(from: diagnostics.initialCentroid, to: gesture.centroid)
        )
        diagnostics.maximumSimulatorDistance = max(
            diagnostics.maximumSimulatorDistance,
            distance(from: diagnostics.initialSimulatorPoint, to: simulatorPoint)
        )
        diagnostics.updateCount += 1
        rawGestureDiagnostics = diagnostics
    }

    private func logRawGestureDiagnostics() {
        guard let diagnostics = rawGestureDiagnostics else { return }
        let durationMilliseconds = (ProcessInfo.processInfo.systemUptime - diagnostics.startedAt) * 1_000
        logger.info(
            "event=input-diagnostic path=rawGesture phase=end gestureID=\(diagnostics.gestureID) " +
                "durationMs=\(format(durationMilliseconds)) updates=\(diagnostics.updateCount) " +
                "centroidFinalDistance=\(format(distance(from: diagnostics.initialCentroid, to: diagnostics.lastCentroid))) " +
                "centroidMaxDistance=\(format(diagnostics.maximumCentroidDistance)) " +
                "simulatorFinalDistance=\(format(distance(from: diagnostics.initialSimulatorPoint, to: diagnostics.lastSimulatorPoint))) " +
                "simulatorMaxDistance=\(format(diagnostics.maximumSimulatorDistance))"
        )
    }

    private func distance(from first: NormalizedTouchPoint, to second: NormalizedTouchPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private func distance(from first: SimulatorPoint, to second: SimulatorPoint) -> CGFloat {
        hypot(first.x - second.x, first.y - second.y)
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.4f", Double(value))
    }

    private func makeMouseTransaction(anchor: SimulatorPoint) -> TouchTransaction {
        TouchTransaction(source: .mouse, intent: .point, anchor: anchor, sink: sink)
    }

    private func navigationPoint(for gesture: InterpretedGesture, anchor: SimulatorPoint) -> SimulatorPoint {
        let gain = InputTuning.stable.navigationGain
        let point = SimulatorPoint(
            x: anchor.x + (gesture.centroid.x - gesture.initialCentroid.x) * mapper.simulatorSize.width * gain,
            y: anchor.y + (gesture.initialCentroid.y - gesture.centroid.y) * mapper.simulatorSize.height * gain
        )
        return mode == .edge ? mapper.clamped(point) : point
    }

    public func capturePointForVirtualFinger() -> CapturePoint? {
        virtualFingerPoint.flatMap(mapper.capturePoint(fromSimulator:))
    }

    public func simulatorPoint(fromCapture point: CapturePoint) -> SimulatorPoint? {
        mapper.simulatorPoint(fromCapture: point)
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
        let targetAngle = -gesture.rotationDelta
        let angleDifference = normalizedAngle(targetAngle - pinchCurrentAngle)
        let angleStep = min(max(angleDifference * 0.35, -0.10), 0.10)
        pinchCurrentAngle = normalizedAngle(pinchCurrentAngle + angleStep)

        let xOffset = cos(pinchCurrentAngle) * pinchCurrentRadius
        let yOffset = sin(pinchCurrentAngle) * pinchCurrentRadius

        return [
            TouchContactPoint(identifier: 0, point: mapper.clamped(SimulatorPoint(x: anchor.x - xOffset, y: anchor.y - yOffset))),
            TouchContactPoint(identifier: 1, point: mapper.clamped(SimulatorPoint(x: anchor.x + xOffset, y: anchor.y + yOffset))),
        ]
    }

    private func normalizedAngle(_ angle: CGFloat) -> CGFloat {
        atan2(sin(angle), cos(angle))
    }

    private func clampedPinchRadius(_ radius: CGFloat) -> CGFloat {
        min(max(radius, 32), min(mapper.simulatorSize.width, mapper.simulatorSize.height) * 0.34)
    }
}
