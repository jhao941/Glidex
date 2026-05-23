import AppKit
import CoreGraphics
import Foundation
import SimTouchCore

@main
struct SimTouchCaptureMain {
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

        window.title = "SimTouch Capture"
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

    private let logger: Logger
    private let injector: SimulatorInjector
    private let injectionQueue = DispatchQueue(label: "simtouch.capture.injection", qos: .userInitiated)
    weak var hostWindow: NSWindow?
    private var calibration = CalibrationState.defaultState
    private var calibrationDragMode: CalibrationDragMode?
    private var gesturePanStart: CGPoint?
    private var magnificationStartTime: Date?
    private var accumulatedMagnification: CGFloat = 0
    private var isOverlayMode = false

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
        guard !calibration.isLocked else {
            super.mouseDown(with: event)
            return
        }

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
        guard !calibration.isLocked, let calibrationDragMode else {
            super.mouseDragged(with: event)
            return
        }

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

    override func mouseUp(with event: NSEvent) {
        if calibrationDragMode != nil {
            logger.info("capture calibration updated rect=\(format(calibration.captureRect))")
            calibrationDragMode = nil
            needsDisplay = true
            return
        }
        super.mouseUp(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        guard calibration.isLocked else {
            super.scrollWheel(with: event)
            return
        }

        let localPoint = convert(event.locationInWindow, from: nil)
        guard let center = calibration.simulatorPoint(from: localPoint) else {
            super.scrollWheel(with: event)
            return
        }

        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY
        let magnitude = hypot(deltaX, deltaY)
        guard magnitude >= 1 else { return }

        let gain: CGFloat = event.hasPreciseScrollingDeltas ? 2.0 : 8.0
        let end = calibration.clampedSimulatorPoint(CGPoint(
            x: center.x + deltaX * gain,
            y: center.y + deltaY * gain
        ))
        logger.info("capture two-finger swipe center=\(format(center)) end=\(format(end)) delta=(\(Int(deltaX)), \(Int(deltaY)))")
        let injector = self.injector

        runInjection {
            try injector.drag(from: center, to: end, duration: 0.18)
        }
    }

    private func setupGestures() {
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        click.numberOfClicksRequired = 1
        addGestureRecognizer(click)

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

        hostWindow?.setFrame(frame, display: true, animate: true)
        hostWindow?.level = .floating
        hostWindow?.makeKeyAndOrderFront(nil)
        calibration.captureRect = defaultCaptureRect(in: CGRect(origin: .zero, size: frame.size))
        calibration.isLocked = false
        logger.info("capture attached to Simulator window frame=\(format(frame)) calibration=\(format(calibration.captureRect))")
        needsDisplay = true
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
        let localPoint = gesture.location(in: self)
        guard let simulatorPoint = calibration.simulatorPoint(from: localPoint) else {
            logger.warn("capture click ignored outside calibration rect local=\(format(localPoint))")
            return
        }
        logger.info("capture click local=\(format(localPoint)) simulator=\(format(simulatorPoint))")
        let injector = self.injector

        runInjection {
            try injector.tap(at: simulatorPoint)
        }
    }

    @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
        guard calibration.isLocked else {
            handleCalibrationPan(gesture)
            return
        }

        let localPoint = gesture.location(in: self)

        switch gesture.state {
        case .began:
            guard calibration.captureRect.contains(localPoint) else { return }
            gesturePanStart = localPoint
            logger.info("capture drag began local=\(format(localPoint))")
        case .ended, .cancelled:
            guard let gesturePanStart else { return }
            self.gesturePanStart = nil

            guard let start = calibration.simulatorPoint(from: gesturePanStart),
                  let end = calibration.simulatorPoint(from: localPoint) else {
                logger.warn("capture drag ignored outside calibration rect")
                return
            }
            logger.info("capture drag ended simulator=\(format(start))->\(format(end))")
            let injector = self.injector

            runInjection {
                try injector.drag(from: start, to: end, duration: 0.35)
            }
        default:
            break
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
            guard calibration.captureRect.contains(localPoint) else { return }
            magnificationStartTime = Date()
            accumulatedMagnification = 0
            logger.info("capture pinch began local=\(format(localPoint))")
        case .changed:
            accumulatedMagnification += gesture.magnification
        case .ended, .cancelled:
            guard let center = calibration.simulatorPoint(from: localPoint) else {
                logger.warn("capture pinch ignored outside calibration rect")
                return
            }
            let scale = max(0.2, Double(1 + accumulatedMagnification))
            let duration = Date().timeIntervalSince(magnificationStartTime ?? Date())
            magnificationStartTime = nil
            accumulatedMagnification = 0
            logger.info("capture pinch ended center=\(format(center)) scale=\(String(format: "%.3f", scale)) duration=\(String(format: "%.3f", duration))")
            let injector = self.injector

            runInjection {
                try injector.pinch(center: center, scale: scale, duration: max(0.2, duration))
            }
        default:
            break
        }
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
        let detail = calibration.isLocked ? "Click, drag, scroll, or pinch inside the frame" : "Drag frame, drag corner to resize, L locks, R resets, O attaches, T fades"
        drawCenteredLabel("SimTouch Capture - \(status)", y: bounds.maxY - 38, fontSize: 18, weight: .semibold)
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
