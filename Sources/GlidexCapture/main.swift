import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import GlidexCore

@main
struct GlidexCaptureMain {
    @MainActor
    static func main() {
        let logger = Logger()
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let contentView = CaptureView(logger: logger)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let windowDelegate = CaptureWindowDelegate()

        window.title = "Glidex Capture"
        window.delegate = windowDelegate
        window.center()
        window.contentView = contentView
        contentView.hostWindow = window
        window.makeKeyAndOrderFront(nil)

        app.finishLaunching()
        app.activate(ignoringOtherApps: true)
        logger.info("capture app ready")

        withExtendedLifetime((window, windowDelegate, logger)) {
            app.run()
        }
    }
}

@MainActor
private final class CaptureWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}

private final class CaptureView: NSView {
    private enum CalibrationDragMode {
        case move(startRect: CGRect, startPoint: CGPoint)
        case resize(startRect: CGRect, startPoint: CGPoint)
    }

    private enum RawTouchInjectionMode {
        case single
        case twoFingerScroll
        case twoFingerPinch
    }

    private struct RawTwoFingerGestureState {
        var contactIDs: (Int32, Int32)
        var initialTimestamp: Double
        var initialCentroid: CGPoint
        var initialDistance: CGFloat
        var initialSimulatorPoint: CGPoint
        var initialPinchRadius: CGFloat
        var currentPinchRadius: CGFloat
        var intent: RawTouchInjectionMode?
    }

    private struct MouseEventSignature: Equatable {
        var type: NSEvent.EventType
        var timestamp: TimeInterval
    }

    private let logger: Logger
    private let injector: SimulatorInjector
    weak var hostWindow: NSWindow?
    private var calibration = CalibrationState.defaultState
    private var calibrationDragMode: CalibrationDragMode?
    private var pendingMouseDownLocalPoint: CGPoint?
    private var pendingMouseDownSimulatorPoint: CGPoint?
    private var mouseTouchSession: LiveTouchSession?
    private var liveDragSession: LiveTouchSession?
    private var liveDragPoint: CGPoint?
    private var isOverlayMode = false
    private var followsSimulatorWindow = false
    private var followTimer: Timer?
    private var isRawTouchEnabled = false
    private var rawTouchStream: MultitouchSupportRawTouchStream?
    private var rawTouchMode: RawTouchInjectionMode?
    private var rawSingleFingerSession: LiveTouchSession?
    private var rawSingleFingerPoint: CGPoint?
    private var rawReusableSingleFingerSession: LiveTouchSession?
    private var rawTwoFingerSession: LiveTwoFingerTouchSession?
    private var rawTwoFingerPoints: (CGPoint, CGPoint)?
    private var rawReusableTwoFingerSession: LiveTwoFingerTouchSession?
    private var rawTwoFingerGesture: RawTwoFingerGestureState?
    private var rawTwoFingerScrollPoint: CGPoint?
    private var mouseTrackingArea: NSTrackingArea?
    private var lastMouseSimulatorPoint: CGPoint?
    private nonisolated(unsafe) var localMouseEventMonitor: Any?
    private var locallyHandledMouseEvents: [MouseEventSignature] = []

    init(logger: Logger) {
        self.logger = logger
        do {
            self.injector = try SimulatorInjector(logger: logger)
        } catch {
            logger.error("failed to initialize injector: \(error)")
            fatalError("failed to initialize injector: \(error)")
        }

        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        setupLocalMouseEventMonitor()
    }

    deinit {
        if let localMouseEventMonitor {
            NSEvent.removeMonitor(localMouseEventMonitor)
        }
        rawTouchStream?.stop()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
        window?.acceptsMouseMovedEvents = true
    }

    override func layout() {
        super.layout()
        if calibration.captureRect == .zero {
            calibration.captureRect = defaultCaptureRect(in: bounds)
        }
        calibration.captureRect = constrainedCaptureRect(calibration.captureRect)
        updateMouseTrackingArea()
    }

    private func updateMouseTrackingArea() {
        if let mouseTrackingArea {
            removeTrackingArea(mouseTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        mouseTrackingArea = trackingArea
        addTrackingArea(trackingArea)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        drawCaptureRect()
        drawChrome()
    }

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "l":
            calibration.isLocked.toggle()
            if calibration.isLocked {
                startRawTouchBackend()
            } else {
                stopRawTouchBackend()
            }
            logger.info("capture calibration \(calibration.isLocked ? "locked" : "unlocked") rect=\(format(calibration.captureRect))")
            needsDisplay = true
        case "o":
            attachToSimulatorWindow()
        case "f":
            toggleSimulatorFollow()
        case "t":
            toggleOverlayMode()
        case "r":
            calibration.captureRect = defaultCaptureRect(in: bounds)
            calibration.isLocked = false
            stopRawTouchBackend()
            logger.info("capture calibration reset rect=\(format(calibration.captureRect))")
            needsDisplay = true
        default:
            super.keyDown(with: event)
        }
    }

    private func startRawTouchBackend() {
        guard !isRawTouchEnabled else { return }
        endLiveDrag(at: liveDragPoint)

        do {
            rawReusableSingleFingerSession = try injector.makeLiveTouchSession()
            rawReusableTwoFingerSession = try injector.makeLiveTwoFingerTouchSession()
            let stream = MultitouchSupportRawTouchStream(logger: logger) { [weak self] frame in
                DispatchQueue.main.async {
                    self?.handleRawTouchFrame(frame)
                }
            }
            try stream.start(source: .default, mode: 0)
            rawTouchStream = stream
            isRawTouchEnabled = true
            logger.info("capture raw touch backend enabled")
        } catch {
            logger.error("capture raw touch backend failed to start: \(error)")
            rawReusableSingleFingerSession = nil
            rawReusableTwoFingerSession = nil
        }
    }

    private func stopRawTouchBackend() {
        guard isRawTouchEnabled else { return }
        endRawTouchInjection()
        rawTouchStream?.stop()
        rawTouchStream = nil
        rawReusableSingleFingerSession = nil
        rawReusableTwoFingerSession = nil
        isRawTouchEnabled = false
        logger.info("capture raw touch backend disabled")
    }

    private func handleRawTouchFrame(_ frame: RawTouchFrame) {
        guard isRawTouchEnabled, calibration.isLocked else {
            endRawTouchInjection()
            return
        }

        let contacts = frame.contacts
            .sorted { $0.identifier < $1.identifier }

        if shouldEndRawTrackedTouch(from: contacts) {
            endRawTouchInjection()
            return
        }

        let activeContacts = contacts
            .filter(\.isActive)

        if activeContacts.count >= 2 {
            updateRawTwoFingerGesture(contacts: (activeContacts[0], activeContacts[1]), timestamp: frame.timestamp)
        } else if let contact = activeContacts.first {
            if rawTouchMode != .twoFingerScroll && rawTouchMode != .twoFingerPinch {
                resetRawTwoFingerGesture()
            }
            ignoreRawSingleFingerTouch(contact)
        } else {
            if rawTouchMode != .twoFingerScroll && rawTouchMode != .twoFingerPinch {
                endRawTouchInjection()
            }
        }
    }

    private func shouldEndRawTrackedTouch(from contacts: [RawTouchContact]) -> Bool {
        guard rawTouchMode == .twoFingerScroll || rawTouchMode == .twoFingerPinch,
              let gesture = rawTwoFingerGesture else {
            return false
        }

        return contacts.contains { contact in
            (contact.identifier == gesture.contactIDs.0 || contact.identifier == gesture.contactIDs.1)
                && !contact.isActive
        }
    }

    private func ignoreRawSingleFingerTouch(_ contact: RawTouchContact) {
        endRawSingleFingerTouchIfModeIsSingle()
    }

    private func updateRawTwoFingerGesture(contacts: (RawTouchContact, RawTouchContact), timestamp: Double) {
        endRawSingleFingerTouchIfModeIsSingle()

        let first = contacts.0
        let second = contacts.1
        let contactIDs = (first.identifier, second.identifier)
        let centroid = CGPoint(
            x: (first.normalizedPosition.x + second.normalizedPosition.x) / 2,
            y: (first.normalizedPosition.y + second.normalizedPosition.y) / 2
        )
        let distance = first.normalizedPosition.distance(to: second.normalizedPosition)

        if rawTwoFingerGesture?.contactIDs.0 != contactIDs.0 || rawTwoFingerGesture?.contactIDs.1 != contactIDs.1 {
            resetRawTwoFingerGesture()
            let anchor = rawGestureAnchorPoint(fallbackCentroid: centroid)
            let pinchRadius = rawInitialPinchRadius(anchor: anchor)
            rawTwoFingerGesture = RawTwoFingerGestureState(
                contactIDs: contactIDs,
                initialTimestamp: timestamp,
                initialCentroid: centroid,
                initialDistance: distance,
                initialSimulatorPoint: anchor,
                initialPinchRadius: pinchRadius,
                currentPinchRadius: pinchRadius,
                intent: nil
            )
        }

        guard var gesture = rawTwoFingerGesture else { return }
        if gesture.intent == nil {
            gesture.intent = resolvedRawTwoFingerIntent(gesture: gesture, centroid: centroid, distance: distance, timestamp: timestamp)
            rawTwoFingerGesture = gesture
            guard gesture.intent != nil else { return }
        }

        switch gesture.intent {
        case .twoFingerPinch:
            let fingers = rawPinchFingers(gesture: &gesture, distance: distance)
            rawTwoFingerGesture = gesture
            let finger1 = fingers.0
            let finger2 = fingers.1
            updateRawTwoFingerPinch(finger1: finger1, finger2: finger2)
        case .twoFingerScroll:
            let point = rawTwoFingerScrollPoint(
                initialPoint: gesture.initialSimulatorPoint,
                initialCentroid: gesture.initialCentroid,
                centroid: centroid
            )
            updateRawTwoFingerScroll(to: point)
        default:
            break
        }
    }

    private func resolvedRawTwoFingerIntent(
        gesture: RawTwoFingerGestureState,
        centroid: CGPoint,
        distance: CGFloat,
        timestamp: Double
    ) -> RawTouchInjectionMode? {
        let elapsed = timestamp - gesture.initialTimestamp
        let centroidDelta = gesture.initialCentroid.distance(to: centroid)
        let distanceDelta = abs(distance - gesture.initialDistance)
        let pinchThreshold: CGFloat = 0.010
        let scrollThreshold: CGFloat = 0.010

        if distanceDelta >= pinchThreshold && distanceDelta > centroidDelta * 1.15 {
            logger.info("capture raw two-finger intent=pinch distance_delta=\(format(distanceDelta)) centroid_delta=\(format(centroidDelta))")
            return .twoFingerPinch
        }

        if distanceDelta >= 0.018 {
            logger.info("capture raw two-finger intent=pinch distance_delta=\(format(distanceDelta)) centroid_delta=\(format(centroidDelta))")
            return .twoFingerPinch
        }

        if centroidDelta >= scrollThreshold && distanceDelta < centroidDelta * 1.2 {
            logger.info("capture raw two-finger intent=scroll distance_delta=\(format(distanceDelta)) centroid_delta=\(format(centroidDelta))")
            return .twoFingerScroll
        }

        if elapsed >= 0.070 && centroidDelta >= 0.006 {
            logger.info("capture raw two-finger intent=scroll distance_delta=\(format(distanceDelta)) centroid_delta=\(format(centroidDelta))")
            return .twoFingerScroll
        }

        return nil
    }

    private func updateRawTwoFingerScroll(to point: CGPoint) {
        if rawTouchMode == .twoFingerPinch {
            endRawTwoFingerTouch()
        }

        if rawSingleFingerSession == nil {
            let session = rawReusableSingleFingerSession
            rawSingleFingerSession = session
            rawSingleFingerPoint = point
            rawTwoFingerScrollPoint = point
            rawTouchMode = .twoFingerScroll
            logger.info("capture raw two-finger scroll began point=\(format(point))")
            session?.begin(at: point)
            return
        }

        guard let session = rawSingleFingerSession else { return }
        rawSingleFingerPoint = point
        rawTwoFingerScrollPoint = point
        session.update(to: point)
    }

    private func updateRawTwoFingerPinch(finger1: CGPoint, finger2: CGPoint) {
        if rawTouchMode == .single {
            endRawSingleFingerTouch()
        } else if rawTouchMode == .twoFingerScroll {
            endRawSingleFingerTouch()
        }

        if rawTwoFingerSession == nil {
            let session = rawReusableTwoFingerSession
            rawTwoFingerSession = session
            rawTwoFingerPoints = (finger1, finger2)
            rawTouchMode = .twoFingerPinch
            logger.info("capture raw two-finger pinch began finger1=\(format(finger1)) finger2=\(format(finger2))")
            session?.begin(finger1: finger1, finger2: finger2)
            return
        }

        guard let session = rawTwoFingerSession else { return }
        rawTwoFingerPoints = (finger1, finger2)
        session.update(finger1: finger1, finger2: finger2)
    }

    private func endRawTouchInjection() {
        endRawSingleFingerTouch()
        endRawTwoFingerTouch()
        resetRawTwoFingerGesture()
        rawTouchMode = nil
    }

    private func endRawSingleFingerTouchIfModeIsSingle() {
        guard rawTouchMode == .single else { return }
        endRawSingleFingerTouch()
    }

    private func endRawSingleFingerTouch() {
        guard let session = rawSingleFingerSession else { return }
        logger.info("capture raw single touch ended point=\(rawSingleFingerPoint.map(format) ?? "nil")")
        session.end(at: rawSingleFingerPoint)
        rawSingleFingerSession = nil
        rawSingleFingerPoint = nil
        rawTwoFingerScrollPoint = nil
        if rawTouchMode == .single || rawTouchMode == .twoFingerScroll {
            rawTouchMode = nil
        }
    }

    private func endRawTwoFingerTouch() {
        guard let session = rawTwoFingerSession else { return }
        logger.info("capture raw two-finger touch ended")
        session.end(finger1: rawTwoFingerPoints?.0, finger2: rawTwoFingerPoints?.1)
        rawTwoFingerSession = nil
        rawTwoFingerPoints = nil
        if rawTouchMode == .twoFingerPinch {
            rawTouchMode = nil
        }
    }

    private func simulatorPoint(fromNormalizedRawTouch point: CGPoint) -> CGPoint {
        let x = min(max(point.x, 0), 1)
        let y = min(max(point.y, 0), 1)
        return calibration.clampedSimulatorPoint(CGPoint(
            x: x * calibration.simulatorSize.width,
            y: (1 - y) * calibration.simulatorSize.height
        ))
    }

    private func rawTwoFingerScrollPoint(initialPoint: CGPoint, initialCentroid: CGPoint, centroid: CGPoint) -> CGPoint {
        let gain: CGFloat = 1.35
        let delta = CGPoint(
            x: (centroid.x - initialCentroid.x) * calibration.simulatorSize.width * gain,
            y: (initialCentroid.y - centroid.y) * calibration.simulatorSize.height * gain
        )
        return calibration.clampedSimulatorPoint(CGPoint(
            x: initialPoint.x + delta.x,
            y: initialPoint.y + delta.y
        ))
    }

    private func rawGestureAnchorPoint(fallbackCentroid: CGPoint) -> CGPoint {
        lastMouseSimulatorPoint
            ?? simulatorPoint(fromNormalizedRawTouch: fallbackCentroid)
    }

    private func rawInitialPinchRadius(anchor: CGPoint) -> CGFloat {
        let screenMaxRadius = min(calibration.simulatorSize.width, calibration.simulatorSize.height) * 0.34
        let edgeMaxRadius = min(anchor.x, calibration.simulatorSize.width - anchor.x)
        return min(72, max(24, min(screenMaxRadius, edgeMaxRadius)))
    }

    private func rawPinchFingers(gesture: inout RawTwoFingerGestureState, distance: CGFloat) -> (CGPoint, CGPoint) {
        let distanceDelta = distance - gesture.initialDistance
        let radiusGain = min(calibration.simulatorSize.width, calibration.simulatorSize.height) * 0.45
        let targetRadius = clampedRawPinchRadius(gesture.initialPinchRadius + distanceDelta * radiusGain)
        let filteredTarget = gesture.currentPinchRadius * 0.82 + targetRadius * 0.18
        let maximumStep: CGFloat = 2.5
        let step = min(max(filteredTarget - gesture.currentPinchRadius, -maximumStep), maximumStep)
        let filteredRadius = clampedRawPinchRadius(gesture.currentPinchRadius + step)
        gesture.currentPinchRadius = filteredRadius
        return (
            calibration.clampedSimulatorPoint(CGPoint(x: gesture.initialSimulatorPoint.x - filteredRadius, y: gesture.initialSimulatorPoint.y)),
            calibration.clampedSimulatorPoint(CGPoint(x: gesture.initialSimulatorPoint.x + filteredRadius, y: gesture.initialSimulatorPoint.y))
        )
    }

    private func clampedRawPinchRadius(_ radius: CGFloat) -> CGFloat {
        min(max(radius, 32), min(calibration.simulatorSize.width, calibration.simulatorSize.height) * 0.34)
    }

    private func resetRawTwoFingerGesture() {
        rawTwoFingerGesture = nil
        rawTwoFingerScrollPoint = nil
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.4f", Double(value))
    }

    override func mouseDown(with event: NSEvent) {
        guard !consumeIfAlreadyHandledByLocalMonitor(event) else { return }
        updateLastMousePoint(from: event)
        handleCaptureMouseDown(event)
    }

    private func handleCaptureMouseDown(_ event: NSEvent) {
        logger.info("capture mouse down button=\(event.buttonNumber) clicks=\(event.clickCount)")
        guard calibration.isLocked else {
            beginCalibrationMouseDrag(event)
            return
        }

        beginPendingTouch(event)
    }

    private func beginPendingTouch(_ event: NSEvent) {
        if isRawTouchEnabled {
            endRawTouchInjection()
        }
        let localPoint = convert(event.locationInWindow, from: nil)
        guard let simulatorPoint = calibration.simulatorPoint(from: localPoint) else {
            logger.warn("capture touch ignored outside calibration rect local=\(format(localPoint))")
            pendingMouseDownLocalPoint = nil
            pendingMouseDownSimulatorPoint = nil
            return
        }

        pendingMouseDownLocalPoint = localPoint
        pendingMouseDownSimulatorPoint = simulatorPoint
        beginLiveDrag(at: simulatorPoint)
    }

    private func beginCalibrationMouseDrag(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if resizeHandleRect.contains(point) {
            calibrationDragMode = .resize(startRect: calibration.captureRect, startPoint: point)
        } else if calibration.captureRect.contains(point) {
            calibrationDragMode = .move(startRect: calibration.captureRect, startPoint: point)
        } else {
            calibrationDragMode = nil
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard !consumeIfAlreadyHandledByLocalMonitor(event) else { return }
        updateLastMousePoint(from: event)
        handleCaptureMouseDragged(event)
    }

    private func handleCaptureMouseDragged(_ event: NSEvent) {
        guard calibration.isLocked else {
            updateCalibrationMouseDrag(event)
            return
        }

        updateLiveDrag(event)
    }

    private func updateCalibrationMouseDrag(_ event: NSEvent) {
        guard let calibrationDragMode else { return }
        let point = convert(event.locationInWindow, from: nil)
        switch calibrationDragMode {
        case let .move(startRect, startPoint):
            let delta = CGPoint(x: point.x - startPoint.x, y: point.y - startPoint.y)
            calibration.captureRect = constrainedCaptureRect(startRect.offsetBy(dx: delta.x, dy: delta.y))
        case let .resize(startRect, startPoint):
            let delta = CGPoint(x: point.x - startPoint.x, y: point.y - startPoint.y)
            calibration.captureRect = constrainedCaptureRect(resizedRect(from: startRect, delta: delta))
        }
        needsDisplay = true
    }

    private func endCalibrationMouseDrag() {
        guard calibrationDragMode != nil else { return }
        logger.info("capture calibration updated rect=\(format(calibration.captureRect))")
        calibrationDragMode = nil
        needsDisplay = true
    }

    private func beginLiveDrag(at simulatorPoint: CGPoint) {
        guard liveDragSession == nil else { return }
        do {
            let session = try mouseTouchSession ?? injector.makeLiveTouchSession()
            mouseTouchSession = session
            liveDragSession = session
            liveDragPoint = simulatorPoint
            logger.info("capture live drag began simulator=\(format(simulatorPoint))")
            session.begin(at: simulatorPoint)
        } catch {
            logger.error("capture live drag failed to begin: \(error)")
        }
    }

    private func updateLiveDrag(_ event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        guard let simulatorPoint = calibration.simulatorPoint(from: localPoint) else {
            logger.warn("capture live drag ended outside calibration rect local=\(format(localPoint))")
            endLiveDrag(at: liveDragPoint)
            return
        }

        guard let startLocalPoint = pendingMouseDownLocalPoint else { return }
        guard startLocalPoint.distance(to: localPoint) >= 3 else { return }

        if liveDragSession == nil {
            guard let startSimulatorPoint = pendingMouseDownSimulatorPoint else { return }
            beginLiveDrag(at: startSimulatorPoint)
        }

        guard let session = liveDragSession else { return }
        liveDragPoint = simulatorPoint
        session.update(to: simulatorPoint)
    }

    private func endLiveDrag(_ event: NSEvent) {
        let localPoint = convert(event.locationInWindow, from: nil)
        endLiveDrag(at: calibration.simulatorPoint(from: localPoint) ?? liveDragPoint)
    }

    private func endLiveDrag(at point: CGPoint?) {
        guard let session = liveDragSession else { return }
        logger.info("capture live drag ended simulator=\(point.map(format) ?? "nil")")
        session.end(at: point)
        liveDragSession = nil
        liveDragPoint = nil
        pendingMouseDownLocalPoint = nil
        pendingMouseDownSimulatorPoint = nil
    }

    override func mouseUp(with event: NSEvent) {
        guard !consumeIfAlreadyHandledByLocalMonitor(event) else { return }
        updateLastMousePoint(from: event)
        handleCaptureMouseUp(event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateLastMousePoint(from: event)
    }

    private func handleCaptureMouseUp(_ event: NSEvent) {
        logger.info("capture mouse up button=\(event.buttonNumber) clicks=\(event.clickCount)")
        guard calibration.isLocked else {
            endCalibrationMouseDrag()
            return
        }

        endLiveDrag(event)
        pendingMouseDownLocalPoint = nil
        pendingMouseDownSimulatorPoint = nil
    }

    private func setupLocalMouseEventMonitor() {
        localMouseEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.handleLocalMouseEvent(event) ?? event
        }
    }

    private func handleLocalMouseEvent(_ event: NSEvent) -> NSEvent? {
        guard let hostWindow,
              let eventWindow = event.window,
              eventWindow === hostWindow else {
            return event
        }

        switch event.type {
        case .leftMouseDown:
            rememberLocallyHandledMouseEvent(event)
            updateLastMousePoint(from: event)
            handleCaptureMouseDown(event)
            return nil
        case .leftMouseDragged:
            rememberLocallyHandledMouseEvent(event)
            updateLastMousePoint(from: event)
            handleCaptureMouseDragged(event)
            return nil
        case .leftMouseUp:
            rememberLocallyHandledMouseEvent(event)
            updateLastMousePoint(from: event)
            handleCaptureMouseUp(event)
            return nil
        default:
            return event
        }
    }

    private func updateLastMousePoint(from event: NSEvent) {
        updateLastMousePoint(localPoint: convert(event.locationInWindow, from: nil))
    }

    private func updateLastMousePoint(localPoint: CGPoint) {
        guard let simulatorPoint = calibration.simulatorPoint(from: localPoint) else {
            return
        }
        lastMouseSimulatorPoint = calibration.clampedSimulatorPoint(simulatorPoint)
    }

    private func rememberLocallyHandledMouseEvent(_ event: NSEvent) {
        locallyHandledMouseEvents.append(MouseEventSignature(type: event.type, timestamp: event.timestamp))
        if locallyHandledMouseEvents.count > 32 {
            locallyHandledMouseEvents.removeFirst(locallyHandledMouseEvents.count - 32)
        }
    }

    private func consumeIfAlreadyHandledByLocalMonitor(_ event: NSEvent) -> Bool {
        let signature = MouseEventSignature(type: event.type, timestamp: event.timestamp)
        guard let index = locallyHandledMouseEvents.firstIndex(of: signature) else {
            return false
        }
        locallyHandledMouseEvents.remove(at: index)
        logger.info("capture ignored delayed mouse event type=\(event.type.rawValue) timestamp=\(event.timestamp)")
        return true
    }

    private func attachToSimulatorWindow() {
        if let screenFrame = SimulatorWindowLocator.findSimulatorScreenFrame(simulatorSize: calibration.simulatorSize) {
            moveOverlayToSimulatorScreen(screenFrame, animate: true)
            hostWindow?.level = .floating
            hostWindow?.makeKeyAndOrderFront(nil)
            startSimulatorFollow()
            logger.info("capture attached to Simulator screen frame=\(format(screenFrame))")
            needsDisplay = true
            return
        }

        guard let frame = SimulatorWindowLocator.findSimulatorWindowFrame() else {
            logger.warn("capture overlay attach failed: Simulator window not found")
            return
        }

        moveOverlay(to: frame, resetCalibration: true, animate: true)
        hostWindow?.level = .floating
        hostWindow?.makeKeyAndOrderFront(nil)
        startSimulatorFollow()
        logger.info("capture attached to Simulator window frame=\(format(frame)) calibration=\(format(calibration.captureRect))")
        needsDisplay = true
    }

    private func toggleSimulatorFollow() {
        if followsSimulatorWindow {
            stopSimulatorFollow()
        } else {
            startSimulatorFollow()
        }
    }

    private func startSimulatorFollow() {
        guard !followsSimulatorWindow else { return }
        followsSimulatorWindow = true
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncToSimulatorWindow()
            }
        }
        followTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        logger.info("capture simulator follow enabled")
        needsDisplay = true
    }

    private func stopSimulatorFollow() {
        guard followsSimulatorWindow else { return }
        followsSimulatorWindow = false
        followTimer?.invalidate()
        followTimer = nil
        logger.info("capture simulator follow disabled")
        needsDisplay = true
    }

    private func syncToSimulatorWindow() {
        if let screenFrame = SimulatorWindowLocator.findSimulatorScreenFrame(simulatorSize: calibration.simulatorSize) {
            guard let currentFrame = hostWindow?.frame, !currentFrame.isNearlyEqual(to: screenFrame) else {
                return
            }
            moveOverlayToSimulatorScreen(screenFrame, animate: false)
            logger.info("capture followed Simulator screen frame=\(format(screenFrame))")
            needsDisplay = true
            return
        }

        guard let frame = SimulatorWindowLocator.findSimulatorWindowFrame() else {
            logger.warn("capture simulator follow skipped: Simulator window not found")
            return
        }

        guard let currentFrame = hostWindow?.frame, !currentFrame.isNearlyEqual(to: frame) else {
            return
        }

        moveOverlay(to: frame, resetCalibration: false, animate: false)
        logger.info("capture followed Simulator window frame=\(format(frame)) calibration=\(format(calibration.captureRect))")
        needsDisplay = true
    }

    private func moveOverlay(to frame: CGRect, resetCalibration: Bool, animate: Bool) {
        let previousSize = hostWindow?.frame.size ?? bounds.size
        hostWindow?.setFrame(frame, display: true, animate: animate)

        if resetCalibration {
            stopRawTouchBackend()
            calibration.captureRect = defaultCaptureRect(in: CGRect(origin: .zero, size: frame.size))
            calibration.isLocked = false
            return
        }

        calibration.captureRect = scaledCaptureRect(
            calibration.captureRect,
            from: previousSize,
            to: frame.size
        )
    }

    private func moveOverlayToSimulatorScreen(_ frame: CGRect, animate: Bool) {
        hostWindow?.setFrame(frame, display: true, animate: animate)
        calibration.captureRect = CGRect(origin: .zero, size: frame.size)
        calibration.isLocked = true
        startRawTouchBackend()
    }

    private func toggleOverlayMode() {
        isOverlayMode.toggle()
        hostWindow?.isOpaque = !isOverlayMode
        hostWindow?.backgroundColor = isOverlayMode ? .clear : .windowBackgroundColor
        hostWindow?.alphaValue = isOverlayMode ? 0.72 : 1.0
        hostWindow?.level = isOverlayMode ? .floating : .normal
        hostWindow?.hasShadow = !isOverlayMode
        layer?.backgroundColor = isOverlayMode ? NSColor.clear.cgColor : NSColor.windowBackgroundColor.cgColor
        logger.info("capture overlay mode \(isOverlayMode ? "enabled" : "disabled")")
        needsDisplay = true
    }

    private func drawCaptureRect() {
        let rect = calibration.captureRect
        NSColor.controlAccentColor.withAlphaComponent(calibration.isLocked ? 0.18 : 0.10).setFill()
        rect.fill()

        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = calibration.isLocked ? 3 : 2
        border.stroke()

        if !calibration.isLocked {
            NSColor.controlAccentColor.setFill()
            resizeHandleRect.fill()
        }
    }

    private func drawChrome() {
        let status = calibration.isLocked ? "Locked" : "Calibration"
        let follow = followsSimulatorWindow ? "follow on" : "follow off"
        let raw = isRawTouchEnabled ? "raw on" : "raw starting"
        let detail = calibration.isLocked ? "Click/hold with mouse, use trackpad raw gestures (\(raw))" : "Drag frame, drag corner to resize, L locks and starts raw, R resets, O attaches, F follows, T fades (\(follow))"
        drawCenteredLabel("Glidex Capture - \(status)", y: bounds.maxY - 38, fontSize: 18, weight: .semibold)
        drawCenteredLabel(detail, y: bounds.maxY - 64, fontSize: 12, weight: .regular)
    }

    private var resizeHandleRect: CGRect {
        CGRect(
            x: calibration.captureRect.maxX - 16,
            y: calibration.captureRect.minY,
            width: 16,
            height: 16
        )
    }

    private func defaultCaptureRect(in bounds: CGRect) -> CGRect {
        let horizontalInset: CGFloat = 48
        let maxWidth = max(260, bounds.width - horizontalInset * 2)
        let maxHeight = max(560, bounds.height - 112)
        let aspect = calibration.simulatorSize.width / calibration.simulatorSize.height
        var width = min(maxWidth, maxHeight * aspect)
        var height = width / aspect
        if height > maxHeight {
            height = maxHeight
            width = height * aspect
        }
        return CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2 - 8, width: width, height: height)
    }

    private func resizedRect(from rect: CGRect, delta: CGPoint) -> CGRect {
        let minimumWidth: CGFloat = 180
        let aspect = calibration.simulatorSize.width / calibration.simulatorSize.height
        let proposedWidth = max(minimumWidth, rect.width + delta.x)
        let proposedHeight = proposedWidth / aspect
        return CGRect(x: rect.minX, y: rect.maxY - proposedHeight, width: proposedWidth, height: proposedHeight)
    }

    private func constrainedCaptureRect(_ rect: CGRect) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return rect }
        let width = min(rect.width, bounds.width)
        let height = min(rect.height, bounds.height)
        let x = min(max(rect.minX, bounds.minX), bounds.maxX - width)
        let y = min(max(rect.minY, bounds.minY), bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func scaledCaptureRect(_ rect: CGRect, from oldSize: CGSize, to newSize: CGSize) -> CGRect {
        guard oldSize.width > 0, oldSize.height > 0, newSize.width > 0, newSize.height > 0 else {
            return constrainedCaptureRect(rect)
        }

        let scaleX = newSize.width / oldSize.width
        let scaleY = newSize.height / oldSize.height
        return constrainedCaptureRect(CGRect(
            x: rect.minX * scaleX,
            y: rect.minY * scaleY,
            width: rect.width * scaleX,
            height: rect.height * scaleY
        ))
    }

    private func drawCenteredLabel(_ text: String, y: CGFloat, fontSize: CGFloat, weight: NSFont.Weight) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: NSColor.labelColor,
        ]
        let size = text.size(withAttributes: attributes)
        let point = CGPoint(x: bounds.midX - size.width / 2, y: y - size.height / 2)
        text.draw(at: point, withAttributes: attributes)
    }

    private func format(_ point: CGPoint) -> String {
        "(\(Int(point.x)), \(Int(point.y)))"
    }

    private func format(_ rect: CGRect) -> String {
        "(x: \(Int(rect.minX)), y: \(Int(rect.minY)), w: \(Int(rect.width)), h: \(Int(rect.height)))"
    }
}

private struct CalibrationState {
    static let defaultState = CalibrationState(
        captureRect: .zero,
        simulatorSize: CGSize(width: 402, height: 874),
        isLocked: false
    )

    var captureRect: CGRect
    var simulatorSize: CGSize
    var isLocked: Bool

    func simulatorPoint(from localPoint: CGPoint) -> CGPoint? {
        guard captureRect.contains(localPoint), captureRect.width > 0, captureRect.height > 0 else {
            return nil
        }

        let normalizedX = (localPoint.x - captureRect.minX) / captureRect.width
        let normalizedYFromTop = (captureRect.maxY - localPoint.y) / captureRect.height

        return CGPoint(
            x: normalizedX * simulatorSize.width,
            y: normalizedYFromTop * simulatorSize.height
        )
    }

    func clampedSimulatorPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(point.x, 0), simulatorSize.width),
            y: min(max(point.y, 0), simulatorSize.height)
        )
    }
}

private enum SimulatorWindowLocator {
    private struct AXFrameCandidate {
        var frame: CGRect
        var role: String
        var score: CGFloat
    }

    static func findSimulatorScreenFrame(simulatorSize: CGSize) -> CGRect? {
        guard AXIsProcessTrustedWithOptions([
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary) else {
            return nil
        }

        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.iphonesimulator" }) else {
            return nil
        }

        guard let windowFrame = findSimulatorWindowFrame() else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let windows: [AXUIElement] = copyAXAttribute(appElement, kAXWindowsAttribute) else {
            return nil
        }

        let targetAspect = simulatorSize.width / simulatorSize.height
        var candidates: [AXFrameCandidate] = []
        var visited = 0

        for window in windows {
            collectScreenCandidates(
                from: window,
                windowFrame: windowFrame,
                targetAspect: targetAspect,
                depth: 0,
                visited: &visited,
                candidates: &candidates
            )
        }

        return candidates
            .sorted { $0.score > $1.score }
            .first?
            .frame
    }

    static func findSimulatorWindowFrame() -> CGRect? {
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windowList {
            let owner = window[kCGWindowOwnerName as String] as? String ?? ""
            guard owner == "Simulator" else { continue }
            guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"],
                  let y = bounds["Y"],
                  let width = bounds["Width"],
                  let height = bounds["Height"] else {
                continue
            }
            return appKitFrameFromCGWindowBounds(CGRect(x: x, y: y, width: width, height: height))
        }
        return nil
    }

    private static func appKitFrameFromCGWindowBounds(_ bounds: CGRect) -> CGRect {
        let screenFrame = NSScreen.screens.first?.frame ?? .zero
        return CGRect(
            x: bounds.minX,
            y: screenFrame.maxY - bounds.minY - bounds.height,
            width: bounds.width,
            height: bounds.height
        )
    }

    private static func collectScreenCandidates(
        from element: AXUIElement,
        windowFrame: CGRect,
        targetAspect: CGFloat,
        depth: Int,
        visited: inout Int,
        candidates: inout [AXFrameCandidate]
    ) {
        guard depth <= 8, visited < 1_000 else { return }
        visited += 1

        if let frame = elementFrame(element, containingWindowFrame: windowFrame) {
            let role: String = copyAXAttribute(element, kAXRoleAttribute) ?? ""
            if let candidate = screenCandidate(frame: frame, role: role, windowFrame: windowFrame, targetAspect: targetAspect) {
                candidates.append(candidate)
            }
        }

        guard let children: [AXUIElement] = copyAXAttribute(element, kAXChildrenAttribute) else {
            return
        }

        for child in children {
            collectScreenCandidates(
                from: child,
                windowFrame: windowFrame,
                targetAspect: targetAspect,
                depth: depth + 1,
                visited: &visited,
                candidates: &candidates
            )
        }
    }

    private static func screenCandidate(frame: CGRect, role: String, windowFrame: CGRect, targetAspect: CGFloat) -> AXFrameCandidate? {
        guard frame.width >= 160, frame.height >= 320 else { return nil }
        guard frame.width < windowFrame.width * 0.98 || frame.height < windowFrame.height * 0.98 else { return nil }
        guard windowFrame.insetBy(dx: -2, dy: -2).contains(frame) else { return nil }

        let aspect = frame.width / frame.height
        let aspectError = abs(aspect - targetAspect) / targetAspect
        guard aspectError <= 0.18 else { return nil }

        let area = frame.width * frame.height
        let areaRatio = area / max(windowFrame.width * windowFrame.height, 1)
        guard areaRatio >= 0.25 else { return nil }

        let horizontalCenterError = abs(frame.midX - windowFrame.midX) / max(windowFrame.width, 1)
        let topToolbarGap = windowFrame.maxY - frame.maxY
        let toolbarBonus: CGFloat = topToolbarGap > 20 ? 0.15 : 0
        let score = areaRatio * 1.4 - aspectError * 2.2 - horizontalCenterError + toolbarBonus
        return AXFrameCandidate(frame: frame, role: role, score: score)
    }

    private static func elementFrame(_ element: AXUIElement, containingWindowFrame windowFrame: CGRect) -> CGRect? {
        guard let positionValue: AXValue = copyAXAttribute(element, kAXPositionAttribute),
              let sizeValue: AXValue = copyAXAttribute(element, kAXSizeAttribute) else {
            return nil
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size),
              size.width > 0,
              size.height > 0 else {
            return nil
        }

        let rawFrame = CGRect(origin: position, size: size)
        let convertedFrame = appKitFrameFromCGWindowBounds(rawFrame)
        if windowFrame.insetBy(dx: -2, dy: -2).contains(convertedFrame) {
            return convertedFrame
        }
        if windowFrame.insetBy(dx: -2, dy: -2).contains(rawFrame) {
            return rawFrame
        }
        return convertedFrame
    }

    private static func copyAXAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let value else {
            return nil
        }
        return value as? T
    }
}

private extension CGRect {
    func isNearlyEqual(to other: CGRect, tolerance: CGFloat = 1) -> Bool {
        abs(minX - other.minX) <= tolerance &&
            abs(minY - other.minY) <= tolerance &&
            abs(width - other.width) <= tolerance &&
            abs(height - other.height) <= tolerance
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}
