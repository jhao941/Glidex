import AppKit
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

    private enum LiveScrollAxis {
        case horizontal
        case vertical
    }

    private let logger: Logger
    private let injector: SimulatorInjector
    private let injectionQueue = DispatchQueue(label: "glidex.capture.injection", qos: .userInitiated)
    weak var hostWindow: NSWindow?
    private var calibration = CalibrationState.defaultState
    private var calibrationDragMode: CalibrationDragMode?
    private var pendingMouseDownLocalPoint: CGPoint?
    private var pendingMouseDownSimulatorPoint: CGPoint?
    private var liveTapSession: LiveTouchSession?
    private var liveDragSession: LiveTouchSession?
    private var liveDragPoint: CGPoint?
    private var livePinchSession: LiveTwoFingerTouchSession?
    private var livePinchCenter: CGPoint?
    private var livePinchBaseRadius: CGFloat = 90
    private var livePinchCurrentRadius: CGFloat = 90
    private var livePinchLastMagnification: CGFloat = 0
    private var livePinchStartTime: TimeInterval?
    private var livePinchUpdateCount = 0
    private var suppressClickUntil: TimeInterval = 0
    private var accumulatedMagnification: CGFloat = 0
    private var isOverlayMode = false
    private var followsSimulatorWindow = false
    private var followTimer: Timer?
    private var isInjectionInFlight = false
    private var liveScrollSession: LiveTouchSession?
    private var liveScrollPoint: CGPoint?
    private var liveScrollAxis: LiveScrollAxis?
    private var liveScrollVelocity = CGPoint.zero
    private var liveScrollImpulseVelocity = CGPoint.zero
    private var liveScrollLastUpdateTime: TimeInterval?
    private var liveScrollEndTimer: Timer?
    private var liveScrollFlingTimer: Timer?
    private var liveScrollFlingVelocity = CGPoint.zero
    private var liveScrollFlingFramesRemaining = 0

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
        setupGestures()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
    }

    override func layout() {
        super.layout()
        if calibration.captureRect == .zero {
            calibration.captureRect = defaultCaptureRect(in: bounds)
        }
        calibration.captureRect = constrainedCaptureRect(calibration.captureRect)
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
            logger.info("capture calibration reset rect=\(format(calibration.captureRect))")
            needsDisplay = true
        default:
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard calibration.isLocked else {
            beginCalibrationMouseDrag(event)
            return
        }

        beginPendingTouch(event)
    }

    private func beginPendingTouch(_ event: NSEvent) {
        endLiveScroll()
        endLivePinch()
        let localPoint = convert(event.locationInWindow, from: nil)
        guard let simulatorPoint = calibration.simulatorPoint(from: localPoint) else {
            logger.warn("capture touch ignored outside calibration rect local=\(format(localPoint))")
            pendingMouseDownLocalPoint = nil
            pendingMouseDownSimulatorPoint = nil
            return
        }

        pendingMouseDownLocalPoint = localPoint
        pendingMouseDownSimulatorPoint = simulatorPoint
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
        do {
            let session = try injector.makeLiveTouchSession()
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

        if liveDragSession == nil {
            guard let startLocalPoint = pendingMouseDownLocalPoint,
                  let startSimulatorPoint = pendingMouseDownSimulatorPoint else { return }
            guard startLocalPoint.distance(to: localPoint) >= 3 else { return }
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
        guard calibration.isLocked else {
            endCalibrationMouseDrag()
            return
        }

        if liveDragSession != nil {
            endLiveDrag(event)
        } else if let simulatorPoint = pendingMouseDownSimulatorPoint {
            performTap(at: simulatorPoint)
        }
        pendingMouseDownLocalPoint = nil
        pendingMouseDownSimulatorPoint = nil
    }

    override func scrollWheel(with event: NSEvent) {
        guard calibration.isLocked else {
            endLiveScroll()
            super.scrollWheel(with: event)
            return
        }

        if shouldEndLiveScroll(event) {
            finishLiveScroll(allowFling: true)
            return
        }
        guard shouldUpdateLiveScroll(event) else { return }

        let localPoint = convert(event.locationInWindow, from: nil)
        guard let center = calibration.simulatorPoint(from: localPoint) else {
            endLiveScroll()
            super.scrollWheel(with: event)
            return
        }

        if event.phase.contains(.began), liveScrollSession != nil {
            endLiveScroll()
        }

        let rawDeltaX = event.scrollingDeltaX
        let rawDeltaY = event.scrollingDeltaY
        let magnitude = hypot(rawDeltaX, rawDeltaY)
        let minimumMagnitude: CGFloat = event.hasPreciseScrollingDeltas ? 0.5 : 2.0
        guard magnitude >= minimumMagnitude else { return }

        let axis = liveScrollAxis ?? resolvedLiveScrollAxis(deltaX: rawDeltaX, deltaY: rawDeltaY)
        liveScrollAxis = axis
        let delta = mappedLiveScrollDelta(deltaX: rawDeltaX, deltaY: rawDeltaY, axis: axis)
        let gain: CGFloat = event.hasPreciseScrollingDeltas ? 2.0 : 8.0
        let basePoint = liveScrollPoint ?? center
        let desiredDelta = CGPoint(x: delta.x * gain, y: delta.y * gain)
        let nextPoint = liveScrollPoint(
            from: basePoint,
            desiredDelta: desiredDelta,
            precise: event.hasPreciseScrollingDeltas
        )
        guard basePoint.distance(to: nextPoint) >= 0.5 else { return }

        guard let session = ensureLiveScrollSession(startingAt: center) else { return }
        updateLiveScrollImpulseVelocity(desiredDelta: desiredDelta)
        updateLiveScrollVelocity(from: basePoint, to: nextPoint, eventTime: event.timestamp)
        liveScrollPoint = nextPoint
        logger.info("capture live scroll update axis=\(axis) point=\(format(nextPoint)) delta=(\(String(format: "%.2f", delta.x)), \(String(format: "%.2f", delta.y)))")
        session.update(to: nextPoint)
        scheduleLiveScrollEndTimer()
    }

    private func shouldEndLiveScroll(_ event: NSEvent) -> Bool {
        event.phase.contains(.ended)
            || event.phase.contains(.cancelled)
            || event.momentumPhase.contains(.ended)
            || event.momentumPhase.contains(.cancelled)
    }

    private func shouldUpdateLiveScroll(_ event: NSEvent) -> Bool {
        guard event.momentumPhase.isEmpty else { return false }
        return true
    }

    private func resolvedLiveScrollAxis(deltaX: CGFloat, deltaY: CGFloat) -> LiveScrollAxis {
        abs(deltaX) >= abs(deltaY) ? .horizontal : .vertical
    }

    private func mappedLiveScrollDelta(deltaX: CGFloat, deltaY: CGFloat, axis: LiveScrollAxis) -> CGPoint {
        let xSign: CGFloat = 1
        let ySign: CGFloat = 1

        switch axis {
        case .horizontal:
            return CGPoint(x: deltaX * xSign, y: 0)
        case .vertical:
            return CGPoint(x: 0, y: deltaY * ySign)
        }
    }

    private func liveScrollPoint(from point: CGPoint, desiredDelta: CGPoint, precise: Bool) -> CGPoint {
        let maximumStep: CGFloat = precise ? 36 : 48
        let distance = hypot(desiredDelta.x, desiredDelta.y)
        let scale = distance > maximumStep ? maximumStep / distance : 1
        return calibration.clampedSimulatorPoint(CGPoint(
            x: point.x + desiredDelta.x * scale,
            y: point.y + desiredDelta.y * scale
        ))
    }

    private func ensureLiveScrollSession(startingAt point: CGPoint) -> LiveTouchSession? {
        if let liveScrollSession {
            return liveScrollSession
        }

        endLivePinch()
        do {
            let session = try injector.makeLiveTouchSession()
            let startPoint = calibration.clampedSimulatorPoint(point)
            liveScrollSession = session
            liveScrollPoint = startPoint
            liveScrollVelocity = .zero
            liveScrollImpulseVelocity = .zero
            liveScrollLastUpdateTime = nil
            liveScrollFlingTimer?.invalidate()
            liveScrollFlingTimer = nil
            logger.info("capture live scroll began point=\(format(startPoint))")
            session.begin(at: startPoint)
            return session
        } catch {
            logger.error("capture live scroll failed to begin: \(error)")
            return nil
        }
    }

    private func updateLiveScrollVelocity(from oldPoint: CGPoint, to newPoint: CGPoint, eventTime: TimeInterval) {
        let previousTime = liveScrollLastUpdateTime
        liveScrollLastUpdateTime = eventTime
        guard let previousTime else { return }

        let dt = min(max(eventTime - previousTime, 1.0 / 120.0), 0.05)
        let instantVelocity = CGPoint(
            x: (newPoint.x - oldPoint.x) / dt,
            y: (newPoint.y - oldPoint.y) / dt
        )
        liveScrollVelocity = CGPoint(
            x: liveScrollVelocity.x * 0.35 + instantVelocity.x * 0.65,
            y: liveScrollVelocity.y * 0.35 + instantVelocity.y * 0.65
        )
    }

    private func updateLiveScrollImpulseVelocity(desiredDelta: CGPoint) {
        let instantVelocity = CGPoint(x: desiredDelta.x * 60.0, y: desiredDelta.y * 60.0)
        liveScrollImpulseVelocity = CGPoint(
            x: liveScrollImpulseVelocity.x * 0.25 + instantVelocity.x * 0.75,
            y: liveScrollImpulseVelocity.y * 0.25 + instantVelocity.y * 0.75
        )
    }

    private func finishLiveScroll(allowFling: Bool) {
        liveScrollEndTimer?.invalidate()
        liveScrollEndTimer = nil
        guard allowFling, startLiveScrollFlingIfNeeded() else {
            endLiveScroll()
            return
        }
    }

    private func startLiveScrollFlingIfNeeded() -> Bool {
        guard liveScrollSession != nil, liveScrollPoint != nil else { return false }
        let velocity = strongerLiveScrollVelocity()
        let speed = hypot(velocity.x, velocity.y)
        guard speed >= 650 else {
            logger.info("capture live scroll fling skipped speed=\(Int(speed))")
            return false
        }

        liveScrollFlingVelocity = clampedLiveScrollVelocity(velocity)
        liveScrollFlingFramesRemaining = 5
        liveScrollFlingTimer?.invalidate()
        logger.info("capture live scroll fling began velocity=(\(Int(liveScrollFlingVelocity.x)), \(Int(liveScrollFlingVelocity.y))) speed=\(Int(speed))")

        let timer = Timer(
            timeInterval: 1.0 / 60.0,
            target: self,
            selector: #selector(handleLiveScrollFlingTimer(_:)),
            userInfo: nil,
            repeats: true
        )
        liveScrollFlingTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        return true
    }

    @objc private func handleLiveScrollFlingTimer(_ timer: Timer) {
        advanceLiveScrollFling(timer: timer)
    }

    private func advanceLiveScrollFling(timer: Timer) {
        guard let session = liveScrollSession, let point = liveScrollPoint else {
            timer.invalidate()
            liveScrollFlingTimer = nil
            return
        }

        let nextPoint = calibration.clampedSimulatorPoint(CGPoint(
            x: point.x + liveScrollFlingVelocity.x / 60.0,
            y: point.y + liveScrollFlingVelocity.y / 60.0
        ))
        liveScrollPoint = nextPoint
        session.update(to: nextPoint)

        liveScrollFlingVelocity.x *= 0.72
        liveScrollFlingVelocity.y *= 0.72
        liveScrollFlingFramesRemaining -= 1

        if liveScrollFlingFramesRemaining <= 0 || point.distance(to: nextPoint) < 0.5 {
            timer.invalidate()
            liveScrollFlingTimer = nil
            endLiveScroll()
        }
    }

    private func strongerLiveScrollVelocity() -> CGPoint {
        let streamSpeed = hypot(liveScrollVelocity.x, liveScrollVelocity.y)
        let impulseSpeed = hypot(liveScrollImpulseVelocity.x, liveScrollImpulseVelocity.y)
        return impulseSpeed > streamSpeed ? liveScrollImpulseVelocity : liveScrollVelocity
    }

    private func clampedLiveScrollVelocity(_ velocity: CGPoint) -> CGPoint {
        let maximumSpeed: CGFloat = 3800
        let speed = hypot(velocity.x, velocity.y)
        guard speed > maximumSpeed else { return velocity }
        let scale = maximumSpeed / speed
        return CGPoint(x: velocity.x * scale, y: velocity.y * scale)
    }

    private func endLiveScroll() {
        guard let session = liveScrollSession else { return }
        liveScrollEndTimer?.invalidate()
        liveScrollEndTimer = nil
        liveScrollFlingTimer?.invalidate()
        liveScrollFlingTimer = nil
        logger.info("capture live scroll ended point=\(liveScrollPoint.map(format) ?? "nil")")
        session.end(at: liveScrollPoint)
        liveScrollSession = nil
        liveScrollPoint = nil
        liveScrollAxis = nil
        liveScrollVelocity = .zero
        liveScrollImpulseVelocity = .zero
        liveScrollLastUpdateTime = nil
        liveScrollFlingVelocity = .zero
        liveScrollFlingFramesRemaining = 0
    }

    private func scheduleLiveScrollEndTimer() {
        liveScrollEndTimer?.invalidate()
        let timer = Timer(
            timeInterval: 0.045,
            target: self,
            selector: #selector(handleLiveScrollEndTimer(_:)),
            userInfo: nil,
            repeats: false
        )
        liveScrollEndTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    @objc private func handleLiveScrollEndTimer(_ timer: Timer) {
        finishLiveScroll(allowFling: true)
    }

    private func setupGestures() {
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)

        let magnify = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnification(_:)))
        addGestureRecognizer(magnify)
    }

    private func attachToSimulatorWindow() {
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

    @objc private func handleClick(_ gesture: NSClickGestureRecognizer) {
        guard calibration.isLocked, gesture.state == .ended else { return }
        guard livePinchSession == nil, Date().timeIntervalSinceReferenceDate >= suppressClickUntil else {
            logger.info("capture click suppressed during pinch")
            return
        }
        let localPoint = gesture.location(in: self)
        guard let simulatorPoint = calibration.simulatorPoint(from: localPoint) else {
            logger.warn("capture click ignored outside calibration rect local=\(format(localPoint))")
            return
        }
        logger.info("capture click local=\(format(localPoint)) simulator=\(format(simulatorPoint))")
        performTap(at: simulatorPoint)
    }

    private func performTap(at simulatorPoint: CGPoint) {
        guard Date().timeIntervalSinceReferenceDate >= suppressClickUntil else {
            logger.info("capture tap suppressed during pinch")
            return
        }
        logger.info("capture tap simulator=\(format(simulatorPoint))")
        do {
            let session = try liveTapSession ?? injector.makeLiveTouchSession()
            liveTapSession = session
            session.begin(at: simulatorPoint)
            session.end(at: simulatorPoint, delay: 0.055)
        } catch {
            logger.error("capture tap failed: \(error)")
        }
    }

    @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
        guard calibration.isLocked else {
            handleCalibrationPan(gesture)
            return
        }
    }

    private func handleCalibrationPan(_ gesture: NSPanGestureRecognizer) {
        let point = gesture.location(in: self)

        switch gesture.state {
        case .began:
            if resizeHandleRect.contains(point) {
                calibrationDragMode = .resize(startRect: calibration.captureRect, startPoint: point)
            } else if calibration.captureRect.contains(point) {
                calibrationDragMode = .move(startRect: calibration.captureRect, startPoint: point)
            } else {
                calibrationDragMode = nil
            }
        case .changed:
            guard let calibrationDragMode else { return }
            switch calibrationDragMode {
            case let .move(startRect, startPoint):
                let delta = CGPoint(x: point.x - startPoint.x, y: point.y - startPoint.y)
                calibration.captureRect = constrainedCaptureRect(startRect.offsetBy(dx: delta.x, dy: delta.y))
            case let .resize(startRect, startPoint):
                let delta = CGPoint(x: point.x - startPoint.x, y: point.y - startPoint.y)
                calibration.captureRect = constrainedCaptureRect(resizedRect(from: startRect, delta: delta))
            }
            needsDisplay = true
        case .ended, .cancelled:
            guard calibrationDragMode != nil else { return }
            calibrationDragMode = nil
            logger.info("capture calibration updated rect=\(format(calibration.captureRect))")
            needsDisplay = true
        default:
            break
        }
    }

    @objc private func handleMagnification(_ gesture: NSMagnificationGestureRecognizer) {
        guard calibration.isLocked else { return }
        let localPoint = gesture.location(in: self)

        switch gesture.state {
        case .began:
            beginLivePinch(at: localPoint)
        case .changed:
            updateLivePinch(magnification: gesture.magnification)
        case .ended, .cancelled:
            endLivePinch()
        default:
            break
        }
    }

    private func beginLivePinch(at localPoint: CGPoint) {
        guard let center = calibration.simulatorPoint(from: localPoint) else {
            logger.warn("capture live pinch ignored outside calibration rect local=\(format(localPoint))")
            return
        }

        endLiveScroll()
        endLiveDrag(at: liveDragPoint)

        do {
            let session = try injector.makeLiveTwoFingerTouchSession()
            let radius = pinchRadius(for: 1)
            let fingers = pinchFingers(center: center, radius: radius)
            livePinchSession = session
            livePinchCenter = center
            livePinchBaseRadius = radius
            livePinchCurrentRadius = radius
            livePinchLastMagnification = 0
            livePinchStartTime = Date().timeIntervalSinceReferenceDate
            livePinchUpdateCount = 0
            suppressClickUntil = Date().timeIntervalSinceReferenceDate + 0.35
            accumulatedMagnification = 0
            logger.info("capture live pinch began center=\(format(center)) radius=\(Int(radius))")
            session.begin(finger1: fingers.0, finger2: fingers.1)
        } catch {
            logger.error("capture live pinch failed to begin: \(error)")
        }
    }

    private func updateLivePinch(magnification: CGFloat) {
        guard let session = livePinchSession, let center = livePinchCenter else { return }
        let delta = magnification - livePinchLastMagnification
        livePinchLastMagnification = magnification
        accumulatedMagnification = magnification
        let radius = clampedPinchRadius(livePinchCurrentRadius + delta * 130)
        guard abs(radius - livePinchCurrentRadius) >= 0.75 else { return }
        let fingers = pinchFingers(center: center, radius: radius)
        livePinchCurrentRadius = radius
        livePinchUpdateCount += 1
        logger.info("capture live pinch update center=\(format(center)) magnification=\(String(format: "%.3f", Double(magnification))) delta=\(String(format: "%.3f", Double(delta))) radius=\(Int(radius))")
        session.update(finger1: fingers.0, finger2: fingers.1)
    }

    private func endLivePinch() {
        guard let session = livePinchSession else { return }
        let center = livePinchCenter
        if let center {
            sendPinchTailIfNeeded(session: session, center: center)
        }
        let fingers = center.map { pinchFingers(center: $0, radius: livePinchCurrentRadius) }
        logger.info("capture live pinch ended center=\(center.map(format) ?? "nil")")
        session.end(finger1: fingers?.0, finger2: fingers?.1, delay: 1.0 / 60.0)
        suppressClickUntil = Date().timeIntervalSinceReferenceDate + 0.12
        livePinchSession = nil
        livePinchCenter = nil
        livePinchBaseRadius = 90
        livePinchCurrentRadius = 90
        livePinchLastMagnification = 0
        livePinchStartTime = nil
        livePinchUpdateCount = 0
        accumulatedMagnification = 0
    }

    private func sendPinchTailIfNeeded(session: LiveTwoFingerTouchSession, center: CGPoint) {
        let elapsed = Date().timeIntervalSinceReferenceDate - (livePinchStartTime ?? Date().timeIntervalSinceReferenceDate)
        let radiusDelta = livePinchCurrentRadius - livePinchBaseRadius
        let minimumFrames = 5
        let needsTail = elapsed < 0.12 || livePinchUpdateCount < minimumFrames || abs(radiusDelta) < 12
        guard needsTail else { return }

        let direction: CGFloat
        if abs(radiusDelta) >= 1 {
            direction = radiusDelta.sign == .minus ? -1 : 1
        } else {
            direction = accumulatedMagnification < 0 ? -1 : 1
        }
        let minimumDelta = max(abs(radiusDelta), 24)
        let targetRadius = clampedPinchRadius(livePinchBaseRadius + direction * minimumDelta)
        let startRadius = livePinchCurrentRadius
        let frames = max(1, minimumFrames - livePinchUpdateCount)

        logger.info("capture live pinch tail frames=\(frames) from_radius=\(Int(startRadius)) to_radius=\(Int(targetRadius)) elapsed_ms=\(Int(elapsed * 1000)) updates=\(livePinchUpdateCount)")
        for index in 1...frames {
            let progress = CGFloat(index) / CGFloat(frames)
            let radius = startRadius + (targetRadius - startRadius) * progress
            let fingers = pinchFingers(center: center, radius: radius)
            session.update(finger1: fingers.0, finger2: fingers.1, delay: 1.0 / 60.0)
            livePinchCurrentRadius = radius
        }
    }

    private func pinchRadius(for scale: CGFloat) -> CGFloat {
        clampedPinchRadius(livePinchBaseRadius * scale)
    }

    private func clampedPinchRadius(_ radius: CGFloat) -> CGFloat {
        min(max(radius, 8), min(calibration.simulatorSize.width, calibration.simulatorSize.height) * 0.49)
    }

    private func pinchFingers(center: CGPoint, radius: CGFloat) -> (CGPoint, CGPoint) {
        let finger1 = calibration.clampedSimulatorPoint(CGPoint(x: center.x - radius, y: center.y))
        let finger2 = calibration.clampedSimulatorPoint(CGPoint(x: center.x + radius, y: center.y))
        return (finger1, finger2)
    }

    private func runInjection(_ action: @escaping @Sendable () throws -> Void) {
        injectionQueue.async { [logger] in
            do {
                try action()
            } catch {
                logger.error("capture injection failed: \(error)")
            }
        }
    }

    private func runInjectionIfIdle(_ action: @escaping @Sendable () throws -> Void) {
        guard !isInjectionInFlight else { return }
        isInjectionInFlight = true

        injectionQueue.async { [logger] in
            do {
                try action()
            } catch {
                logger.error("capture injection failed: \(error)")
            }

            DispatchQueue.main.async { [weak self] in
                self?.isInjectionInFlight = false
            }
        }
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
        let detail = calibration.isLocked ? "Click, drag, scroll, or pinch inside the frame" : "Drag frame, drag corner to resize, L locks, R resets, O attaches, F follows, T fades (\(follow))"
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
