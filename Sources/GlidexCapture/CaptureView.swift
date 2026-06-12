import AppKit
import GlidexCore

@MainActor
final class CaptureView: NSView {
    private enum MouseEventPhase: String {
        case down
        case dragged
        case up
    }

    var onMouseDown: ((CapturePoint) -> Void)?
    var onMouseDragged: ((CapturePoint) -> Void)?
    var onMouseUp: ((CapturePoint) -> Void)?
    var onMouseMoved: ((CapturePoint) -> Void)?

    private var presentation = OverlayPresentation(snapshot: GlidexAppSnapshot())
    private var mouseTrackingArea: NSTrackingArea?
    private let logger: Logger

    init(frame frameRect: NSRect, logger: Logger) {
        self.logger = logger
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
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

    override func updateTrackingAreas() {
        if let mouseTrackingArea {
            removeTrackingArea(mouseTrackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        mouseTrackingArea = area
        addTrackingArea(area)
        super.updateTrackingAreas()
    }

    func render(snapshot: GlidexAppSnapshot) {
        presentation = OverlayPresentation(snapshot: snapshot)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawBorder()
        drawAnchorIndicator()
        drawActiveTouches()
    }

    override func mouseDown(with event: NSEvent) {
        logMouseEvent(event, phase: .down)
        onMouseDown?(CapturePoint(convert(event.locationInWindow, from: nil)))
    }

    override func mouseDragged(with event: NSEvent) {
        logMouseEvent(event, phase: .dragged)
        onMouseDragged?(CapturePoint(convert(event.locationInWindow, from: nil)))
    }

    override func mouseUp(with event: NSEvent) {
        logMouseEvent(event, phase: .up)
        onMouseUp?(CapturePoint(convert(event.locationInWindow, from: nil)))
    }

    override func mouseMoved(with event: NSEvent) {
        onMouseMoved?(CapturePoint(convert(event.locationInWindow, from: nil)))
    }

    private func logMouseEvent(_ event: NSEvent, phase: MouseEventPhase) {
        let isTouchDerived = event.subtype == .touch
        let location = convert(event.locationInWindow, from: nil)
        let eventTimestamp = String(format: "%.6f", event.timestamp)
        var message = "event=input-diagnostic path=mouse phase=\(phase.rawValue)"
        message += " touchDerived=\(isTouchDerived)"
        message += " subtype=\(event.subtype.rawValue) eventNumber=\(event.eventNumber)"
        message += " clickCount=\(event.clickCount) button=\(event.buttonNumber)"
        message += " pressure=\(format(CGFloat(event.pressure))) timestamp=\(eventTimestamp)"
        message += " location=\(format(location.x)),\(format(location.y))"
        logger.info(message)
    }

    private func format(_ value: CGFloat) -> String {
        String(format: "%.2f", Double(value))
    }

    private func drawBorder() {
        guard presentation.borderAlpha > 0 else { return }
        if presentation.isCalibrationMode {
            NSColor.systemBlue.withAlphaComponent(max(0.7, presentation.borderAlpha)).setStroke()
            let border = NSBezierPath(rect: bounds.insetBy(dx: 2.5, dy: 2.5))
            border.lineWidth = 3
            border.setLineDash([7, 5], count: 2, phase: 0)
            border.stroke()
            return
        }
        if presentation.anchorLockState == .unlocked,
           presentation.inputMode == .point || presentation.inputMode == .edge {
            NSColor.systemOrange.withAlphaComponent(max(0.7, presentation.borderAlpha)).setStroke()
            let border = NSBezierPath(rect: bounds.insetBy(dx: 2.5, dy: 2.5))
            border.lineWidth = 3
            border.setLineDash([7, 5], count: 2, phase: 0)
            border.stroke()
            return
        }
        borderColor.withAlphaComponent(presentation.borderAlpha).setStroke()
        let inset: CGFloat = 1.5
        let border = NSBezierPath(rect: bounds.insetBy(dx: inset, dy: inset))
        border.lineWidth = 2
        border.stroke()
    }

    private func drawAnchorIndicator() {
        let requiredForEditing = presentation.anchorLockState == .unlocked &&
            (presentation.inputMode == .point || presentation.inputMode == .edge)
        guard presentation.showsAnchorIndicator || requiredForEditing,
              let simulatorPoint = presentation.anchorIndicator.point,
              let point = capturePoint(from: simulatorPoint) else { return }
        let ring = CGRect(x: point.x - 11, y: point.y - 11, width: 22, height: 22)
        NSColor.systemOrange.withAlphaComponent(0.25).setFill()
        NSBezierPath(ovalIn: ring).fill()
        NSColor.systemOrange.setStroke()
        let path = NSBezierPath(ovalIn: ring)
        path.lineWidth = 2
        path.stroke()
    }

    private func drawActiveTouches() {
        guard presentation.showsActiveTouches else { return }
        for contact in presentation.activeTouches {
            guard let point = capturePoint(from: contact.point) else { continue }
            let dot = CGRect(x: point.x - 8, y: point.y - 8, width: 16, height: 16)
            NSColor.controlAccentColor.withAlphaComponent(0.42).setFill()
            NSBezierPath(ovalIn: dot).fill()
            NSColor.white.withAlphaComponent(0.9).setStroke()
            let outline = NSBezierPath(ovalIn: dot)
            outline.lineWidth = 1.5
            outline.stroke()
        }
    }

    private func capturePoint(from point: SimulatorPoint) -> CGPoint? {
        guard let size = presentation.simulatorSize, size.width > 0, size.height > 0 else { return nil }
        return CGPoint(
            x: point.x / size.width * bounds.width,
            y: bounds.height - point.y / size.height * bounds.height
        )
    }

    private var borderColor: NSColor {
        if case .available = presentation.optionAnchorAvailability {
            return .systemOrange
        }
        switch presentation.status {
        case .active:
            return .controlAccentColor
        case .connecting, .waiting:
            return .systemYellow
        case .paused:
            return .systemGray
        case .error:
            return .systemRed
        }
    }
}

private extension OptionAnchorAvailability {
    var isAvailable: Bool {
        if case .available = self { true } else { false }
    }
}

private extension AnchorIndicatorState {
    var point: SimulatorPoint? {
        switch self {
        case .none: nil
        case let .fixed(point), let .temporary(point): point
        }
    }
}
