import AppKit
import CoreGraphics
import Foundation
import GlidexCore

@MainActor
final class CaptureView: NSView {
    private enum CalibrationDragMode {
        case move(startRect: CGRect, startPoint: CGPoint)
        case resize(startRect: CGRect, startPoint: CGPoint)
    }

    private let logger: Logger
    private let coordinator: GestureCoordinator
    private let windowTracker: SimulatorWindowTracker

    weak var hostWindow: NSWindow?
    private var calibration = CalibrationState.defaultState
    private var calibrationDragMode: CalibrationDragMode?
    private var isOverlayMode = false
    private var rawTouchStream: MultitouchSupportRawTouchStream?
    private var isRawTouchEnabled = false
    private var mouseTrackingArea: NSTrackingArea?

    init(logger: Logger) {
        self.logger = logger
        do {
            let injector = try SimulatorInjector(logger: logger)
            let sink = IndigoTouchSink(injector: injector, logger: logger)
            self.coordinator = GestureCoordinator(
                mapper: CoordinateMapper(
                    captureRect: .zero,
                    simulatorSize: SimulatorPointSize(CalibrationState.defaultState.simulatorSize)
                ),
                sink: sink,
                logger: logger
            )
        } catch {
            logger.error("failed to initialize injector: \(error)")
            fatalError("failed to initialize injector: \(error)")
        }
        self.windowTracker = SimulatorWindowTracker(logger: logger)

        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
        updateCoordinatorMapper()
        updateMouseTrackingArea()
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
            calibration.isLocked ? startRawTouchBackend() : stopRawTouchBackend()
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
            updateCoordinatorMapper()
            logger.info("capture calibration reset rect=\(format(calibration.captureRect))")
            needsDisplay = true
        default:
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        coordinator.updatePointer(CapturePoint(point))
        guard calibration.isLocked else {
            beginCalibrationDrag(at: point)
            return
        }
        coordinator.beginMouse(at: CapturePoint(point))
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        coordinator.updatePointer(CapturePoint(point))
        guard calibration.isLocked else {
            updateCalibrationDrag(to: point)
            return
        }
        coordinator.updateMouse(at: CapturePoint(point))
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        coordinator.updatePointer(CapturePoint(point))
        guard calibration.isLocked else {
            endCalibrationDrag()
            return
        }
        coordinator.endMouse(at: CapturePoint(point))
    }

    override func mouseMoved(with event: NSEvent) {
        coordinator.updatePointer(CapturePoint(convert(event.locationInWindow, from: nil)))
    }

    func cancelInput(reason: String) {
        coordinator.cancelAll(reason: reason)
    }

    func shutdown() {
        cancelInput(reason: "capture shutdown")
        stopRawTouchBackend()
        windowTracker.stop()
    }

    private func startRawTouchBackend() {
        guard !isRawTouchEnabled else { return }
        coordinator.prepareForDeviceChange()
        do {
            let stream = MultitouchSupportRawTouchStream(logger: logger) { [weak self] frame in
                DispatchQueue.main.async {
                    self?.coordinator.handleRawFrame(frame)
                }
            }
            try stream.start(source: .default, mode: 0)
            rawTouchStream = stream
            isRawTouchEnabled = true
            logger.info("capture raw touch backend enabled")
        } catch {
            logger.error("capture raw touch backend failed to start: \(error)")
        }
    }

    private func stopRawTouchBackend() {
        guard isRawTouchEnabled else { return }
        coordinator.cancelAll(reason: "raw touch backend stopped")
        rawTouchStream?.stop()
        rawTouchStream = nil
        isRawTouchEnabled = false
        logger.info("capture raw touch backend disabled")
    }

    private func updateCoordinatorMapper() {
        coordinator.updateMapper(CoordinateMapper(
            captureRect: calibration.captureRect,
            simulatorSize: SimulatorPointSize(calibration.simulatorSize)
        ))
    }

    private func updateMouseTrackingArea() {
        if let mouseTrackingArea { removeTrackingArea(mouseTrackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        mouseTrackingArea = area
        addTrackingArea(area)
    }

    private func beginCalibrationDrag(at point: CGPoint) {
        if resizeHandleRect.contains(point) {
            calibrationDragMode = .resize(startRect: calibration.captureRect, startPoint: point)
        } else if calibration.captureRect.contains(point) {
            calibrationDragMode = .move(startRect: calibration.captureRect, startPoint: point)
        } else {
            calibrationDragMode = nil
        }
    }

    private func updateCalibrationDrag(to point: CGPoint) {
        guard let mode = calibrationDragMode else { return }
        switch mode {
        case let .move(startRect, startPoint):
            calibration.captureRect = constrainedCaptureRect(startRect.offsetBy(
                dx: point.x - startPoint.x,
                dy: point.y - startPoint.y
            ))
        case let .resize(startRect, startPoint):
            calibration.captureRect = constrainedCaptureRect(resizedRect(
                from: startRect,
                delta: CGPoint(x: point.x - startPoint.x, y: point.y - startPoint.y)
            ))
        }
        updateCoordinatorMapper()
        needsDisplay = true
    }

    private func endCalibrationDrag() {
        guard calibrationDragMode != nil else { return }
        calibrationDragMode = nil
        logger.info("capture calibration updated rect=\(format(calibration.captureRect))")
        needsDisplay = true
    }

    private func attachToSimulatorWindow() {
        guard let target = windowTracker.currentTarget(simulatorSize: calibration.simulatorSize) else {
            logger.warn("capture overlay attach failed: Simulator window not found")
            return
        }
        coordinator.prepareForDeviceChange()
        applyTrackedTarget(target, animate: true, resetCalibration: true)
        hostWindow?.level = .floating
        hostWindow?.makeKeyAndOrderFront(nil)
        startSimulatorFollow()
    }

    private func toggleSimulatorFollow() {
        windowTracker.isFollowing ? windowTracker.stop() : startSimulatorFollow()
        needsDisplay = true
    }

    private func startSimulatorFollow() {
        windowTracker.start(simulatorSize: calibration.simulatorSize) { [weak self] target in
            self?.applyTrackedTarget(target, animate: false, resetCalibration: false)
        }
        needsDisplay = true
    }

    private func applyTrackedTarget(_ target: SimulatorWindowTracker.Target, animate: Bool, resetCalibration: Bool) {
        guard hostWindow?.frame.isNearlyEqual(to: target.frame) != true else { return }
        let previousSize = hostWindow?.frame.size ?? bounds.size
        hostWindow?.setFrame(target.frame, display: true, animate: animate)

        switch target.kind {
        case .screen:
            calibration.captureRect = CGRect(origin: .zero, size: target.frame.size)
            calibration.isLocked = true
            startRawTouchBackend()
        case .window:
            if resetCalibration {
                stopRawTouchBackend()
                calibration.captureRect = defaultCaptureRect(in: CGRect(origin: .zero, size: target.frame.size))
                calibration.isLocked = false
            } else {
                calibration.captureRect = scaledCaptureRect(calibration.captureRect, from: previousSize, to: target.frame.size)
            }
        }
        updateCoordinatorMapper()
        logger.info("capture tracked Simulator kind=\(target.kind) frame=\(format(target.frame))")
        needsDisplay = true
    }

    private func toggleOverlayMode() {
        isOverlayMode.toggle()
        hostWindow?.isOpaque = !isOverlayMode
        hostWindow?.backgroundColor = isOverlayMode ? .clear : .windowBackgroundColor
        hostWindow?.alphaValue = isOverlayMode ? 0.72 : 1
        hostWindow?.level = isOverlayMode ? .floating : .normal
        hostWindow?.hasShadow = !isOverlayMode
        layer?.backgroundColor = isOverlayMode ? NSColor.clear.cgColor : NSColor.windowBackgroundColor.cgColor
        logger.info("capture overlay mode \(isOverlayMode ? "enabled" : "disabled")")
        needsDisplay = true
    }

    private func drawCaptureRect() {
        NSColor.controlAccentColor.withAlphaComponent(calibration.isLocked ? 0.18 : 0.10).setFill()
        calibration.captureRect.fill()
        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: calibration.captureRect)
        border.lineWidth = calibration.isLocked ? 3 : 2
        border.stroke()
        if !calibration.isLocked {
            NSColor.controlAccentColor.setFill()
            resizeHandleRect.fill()
        }
    }

    private func drawChrome() {
        let status = calibration.isLocked ? "Locked" : "Calibration"
        let follow = windowTracker.isFollowing ? "follow on" : "follow off"
        let raw = isRawTouchEnabled ? "raw on" : "raw starting"
        let detail = calibration.isLocked
            ? "Click/hold with mouse, use trackpad raw gestures (\(raw))"
            : "Drag frame, drag corner to resize, L locks and starts raw, R resets, O attaches, F follows, T fades (\(follow))"
        drawCenteredLabel("Glidex Capture - \(status)", y: bounds.maxY - 38, fontSize: 18, weight: .semibold)
        drawCenteredLabel(detail, y: bounds.maxY - 64, fontSize: 12, weight: .regular)
    }

    private var resizeHandleRect: CGRect {
        CGRect(x: calibration.captureRect.maxX - 16, y: calibration.captureRect.minY, width: 16, height: 16)
    }

    private func defaultCaptureRect(in bounds: CGRect) -> CGRect {
        let maxWidth = max(260, bounds.width - 96)
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
        let width = max(180, rect.width + delta.x)
        let height = width / (calibration.simulatorSize.width / calibration.simulatorSize.height)
        return CGRect(x: rect.minX, y: rect.maxY - height, width: width, height: height)
    }

    private func constrainedCaptureRect(_ rect: CGRect) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return rect }
        let width = min(rect.width, bounds.width)
        let height = min(rect.height, bounds.height)
        return CGRect(
            x: min(max(rect.minX, bounds.minX), bounds.maxX - width),
            y: min(max(rect.minY, bounds.minY), bounds.maxY - height),
            width: width,
            height: height
        )
    }

    private func scaledCaptureRect(_ rect: CGRect, from oldSize: CGSize, to newSize: CGSize) -> CGRect {
        guard oldSize.width > 0, oldSize.height > 0, newSize.width > 0, newSize.height > 0 else {
            return constrainedCaptureRect(rect)
        }
        return constrainedCaptureRect(CGRect(
            x: rect.minX * newSize.width / oldSize.width,
            y: rect.minY * newSize.height / oldSize.height,
            width: rect.width * newSize.width / oldSize.width,
            height: rect.height * newSize.height / oldSize.height
        ))
    }

    private func drawCenteredLabel(_ text: String, y: CGFloat, fontSize: CGFloat, weight: NSFont.Weight) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: NSColor.labelColor,
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: bounds.midX - size.width / 2, y: y - size.height / 2), withAttributes: attributes)
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
}

private extension CGRect {
    func isNearlyEqual(to other: CGRect, tolerance: CGFloat = 1) -> Bool {
        abs(minX - other.minX) <= tolerance &&
            abs(minY - other.minY) <= tolerance &&
            abs(width - other.width) <= tolerance &&
            abs(height - other.height) <= tolerance
    }
}
