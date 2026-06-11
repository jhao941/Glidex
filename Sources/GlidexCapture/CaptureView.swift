import AppKit
import GlidexCore

@MainActor
final class CaptureView: NSView {
    var onMouseDown: ((CapturePoint) -> Void)?
    var onMouseDragged: ((CapturePoint) -> Void)?
    var onMouseUp: ((CapturePoint) -> Void)?
    var onMouseMoved: ((CapturePoint) -> Void)?

    private var presentation = OverlayPresentation(snapshot: GlidexAppSnapshot())
    private var virtualFinger: CapturePoint?
    private var mouseTrackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
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

    func render(snapshot: GlidexAppSnapshot, virtualFinger: CapturePoint?) {
        presentation = OverlayPresentation(snapshot: snapshot)
        self.virtualFinger = virtualFinger
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawBorder()
        drawVirtualFinger()
    }

    override func mouseDown(with event: NSEvent) {
        onMouseDown?(CapturePoint(convert(event.locationInWindow, from: nil)))
    }

    override func mouseDragged(with event: NSEvent) {
        onMouseDragged?(CapturePoint(convert(event.locationInWindow, from: nil)))
    }

    override func mouseUp(with event: NSEvent) {
        onMouseUp?(CapturePoint(convert(event.locationInWindow, from: nil)))
    }

    override func mouseMoved(with event: NSEvent) {
        onMouseMoved?(CapturePoint(convert(event.locationInWindow, from: nil)))
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

    private func drawVirtualFinger() {
        guard presentation.showsTouchIndicator,
              presentation.inputMode == .point || presentation.inputMode == .edge || presentation.optionAnchorAvailability.isAvailable,
              let point = virtualFinger?.cgPoint else { return }
        let ring = CGRect(x: point.x - 11, y: point.y - 11, width: 22, height: 22)
        NSColor.systemOrange.withAlphaComponent(0.25).setFill()
        NSBezierPath(ovalIn: ring).fill()
        NSColor.systemOrange.setStroke()
        let path = NSBezierPath(ovalIn: ring)
        path.lineWidth = 2
        path.stroke()
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
