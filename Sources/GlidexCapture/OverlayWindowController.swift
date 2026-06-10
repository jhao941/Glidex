import AppKit
import GlidexCore

@MainActor
final class OverlayWindowController {
    private enum CalibrationDrag {
        case move(startFrame: CGRect, startPoint: CapturePoint)
        case resize(startFrame: CGRect, startPoint: CapturePoint)
    }

    private let state: GlidexAppState
    private let window: NSPanel
    private let captureView: CaptureView
    private var stateObserver: UUID?
    private var calibrationDrag: CalibrationDrag?
    private var virtualFinger: CapturePoint?
    private var acceptedInput = false

    var onInputDeactivated: (() -> Void)?
    var onMouseDown: ((CapturePoint) -> Void)?
    var onMouseDragged: ((CapturePoint) -> Void)?
    var onMouseUp: ((CapturePoint) -> Void)?
    var onMouseMoved: ((CapturePoint) -> Void)?
    var onCalibrationFrameChange: ((CGRect) -> Void)?

    init(state: GlidexAppState) {
        self.state = state
        self.window = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.captureView = CaptureView(frame: .zero)

        configureWindow()
        configureInput()
        stateObserver = state.observe { [weak self] snapshot in
            self?.apply(snapshot)
        }
    }

    func show(frame: CGRect) {
        guard frame.width > 0, frame.height > 0 else { return }
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
    }

    func hide() {
        window.orderOut(nil)
    }

    func updateVirtualFinger(_ point: CapturePoint?) {
        virtualFinger = point
        captureView.render(snapshot: state.snapshot, virtualFinger: virtualFinger)
    }

    var frame: CGRect { window.frame }

    var windowAlpha: CGFloat { window.alphaValue }

    var ignoresMouseEvents: Bool { window.ignoresMouseEvents }

    private func configureWindow() {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = OverlayPresentation.windowAlpha
        window.hasShadow = false
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = captureView
    }

    private func configureInput() {
        captureView.onMouseDown = { [weak self] point in
            guard let self else { return }
            if state.snapshot.isCalibrationMode {
                beginCalibration(at: point)
            } else {
                onMouseDown?(point)
            }
        }
        captureView.onMouseDragged = { [weak self] point in
            guard let self else { return }
            if state.snapshot.isCalibrationMode {
                updateCalibration(to: point)
            } else {
                onMouseDragged?(point)
            }
        }
        captureView.onMouseUp = { [weak self] point in
            guard let self else { return }
            if state.snapshot.isCalibrationMode {
                calibrationDrag = nil
                onCalibrationFrameChange?(window.frame)
            } else {
                onMouseUp?(point)
            }
        }
        captureView.onMouseMoved = { [weak self] point in
            self?.onMouseMoved?(point)
        }
    }

    private func apply(_ snapshot: GlidexAppSnapshot) {
        let presentation = OverlayPresentation(snapshot: snapshot)
        if OverlayPresentation.requiresCancellation(
            previouslyAcceptedInput: acceptedInput,
            presentation: presentation
        ) {
            onInputDeactivated?()
        }
        acceptedInput = presentation.acceptsInput
        window.ignoresMouseEvents = !presentation.acceptsInput
        window.alphaValue = OverlayPresentation.windowAlpha
        captureView.render(snapshot: snapshot, virtualFinger: virtualFinger)
    }

    private func beginCalibration(at point: CapturePoint) {
        let resizeSize: CGFloat = 28
        let resizeRect = CGRect(
            x: window.frame.width - resizeSize,
            y: 0,
            width: resizeSize,
            height: resizeSize
        )
        if resizeRect.contains(point.cgPoint) {
            calibrationDrag = .resize(startFrame: window.frame, startPoint: point)
        } else {
            calibrationDrag = .move(startFrame: window.frame, startPoint: point)
        }
    }

    private func updateCalibration(to point: CapturePoint) {
        guard let calibrationDrag else { return }
        switch calibrationDrag {
        case let .move(startFrame, startPoint):
            window.setFrameOrigin(CGPoint(
                x: startFrame.minX + point.x - startPoint.x,
                y: startFrame.minY + point.y - startPoint.y
            ))
        case let .resize(startFrame, startPoint):
            let width = max(180, startFrame.width + point.x - startPoint.x)
            let height = max(320, startFrame.height - point.y + startPoint.y)
            let frame = CGRect(
                x: startFrame.minX,
                y: startFrame.maxY - height,
                width: width,
                height: height
            )
            window.setFrame(frame, display: true)
        }
    }
}
