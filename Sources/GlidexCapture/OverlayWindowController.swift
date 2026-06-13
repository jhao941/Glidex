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
    private var acceptedInput = false
    private var hostWindowNumber: Int?
    private var hostOwnerPID: pid_t?
    private var followsHostOcclusion = false
    private var workspaceObservers: [NSObjectProtocol] = []

    var onInputDeactivated: (() -> Void)?
    var onMouseDown: ((CapturePoint) -> Void)?
    var onMouseDragged: ((CapturePoint) -> Void)?
    var onMouseUp: ((CapturePoint) -> Void)?
    var onMouseMoved: ((CapturePoint) -> Void)?
    var onCalibrationFrameChange: ((CGRect) -> Void)?

    init(state: GlidexAppState, logger: Logger) {
        self.state = state
        self.window = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.captureView = CaptureView(frame: .zero, logger: logger)

        configureWindow()
        configureInput()
        observeWorkspace()
        stateObserver = state.observe { [weak self] snapshot in
            self?.apply(snapshot)
        }
    }

    func show(frame: CGRect, hostWindowNumber: Int?, hostOwnerPID: pid_t) {
        guard frame.width > 0, frame.height > 0 else { return }
        self.hostWindowNumber = hostWindowNumber
        self.hostOwnerPID = hostOwnerPID
        window.setFrame(frame, display: true)
        orderRelativeToHost()
    }

    func hide() {
        window.orderOut(nil)
    }

    func capturePoint(fromDesktop point: DesktopPoint) -> CapturePoint? {
        guard window.frame.contains(point.cgPoint) else { return nil }
        return CapturePoint(
            x: point.x - window.frame.minX,
            y: point.y - window.frame.minY
        )
    }

    var frame: CGRect { window.frame }

    var windowAlpha: CGFloat { window.alphaValue }

    var ignoresMouseEvents: Bool { window.ignoresMouseEvents }
    var windowNumber: Int { window.windowNumber }

    func setFollowsHostOcclusion(_ follows: Bool) {
        guard followsHostOcclusion != follows else { return }
        followsHostOcclusion = follows
        orderRelativeToHost()
    }

    private func configureWindow() {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.alphaValue = OverlayPresentation.windowAlpha
        window.hasShadow = false
        window.level = .normal
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
        captureView.render(snapshot: snapshot)
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in
                guard let self, application.processIdentifier == hostOwnerPID else { return }
                orderRelativeToHost()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.orderRelativeToHost()
                }
            }
        })
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                DispatchQueue.main.async { [weak self] in self?.orderRelativeToHost() }
            }
        })
    }

    private func orderRelativeToHost() {
        guard window.isVisible || window.frame.width > 0 else { return }
        guard followsHostOcclusion, let hostWindowNumber else {
            window.level = .floating
            window.orderFrontRegardless()
            return
        }
        window.level = .normal
        window.order(.above, relativeTo: hostWindowNumber)
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
