import AppKit
import ApplicationServices
import GlidexCore

@MainActor
final class CaptureSession {
    private static let fallbackSimulatorSize = SimulatorPointSize(width: 402, height: 874)

    private let logger: Logger
    private let state: GlidexAppState
    private let overlay: OverlayWindowController
    private let injector: SimulatorInjector
    private let sink: IndigoTouchSink
    private let observingSink: TouchObservingSink
    private let coordinator: GestureCoordinator
    private let windowTracker: SimulatorWindowTracker

    private var rawTouchStream: MultitouchSupportRawTouchStream?
    private var rawStreamGeneration = 0
    private var awaitsTouchRelease = false
    private var retryTimer: Timer?
    private var stateObserver: UUID?
    private var selectedTarget: SimulatorTarget?
    private var nativeTarget: SimulatorTarget?
    private var lastTrackedFrame: CGRect?
    private var lastHostTarget: SimulatorWindowTracker.Target?
    private var lastSimulatorPID: pid_t?
    private var frameAdjustment = OverlayFrameAdjustment()
    private var lastEnabled: Bool
    private var lastCalibrationMode: Bool
    private var isAttaching = false
    private var globalModifierMonitor: Any?
    private var localModifierMonitor: Any?

    init(
        logger: Logger,
        state: GlidexAppState,
        overlay: OverlayWindowController
    ) throws {
        self.logger = logger
        self.state = state
        self.overlay = overlay
        self.injector = try SimulatorInjector(logger: logger)
        let sink = IndigoTouchSink(injector: injector, logger: logger)
        self.sink = sink
        self.observingSink = TouchObservingSink(downstream: sink) { event in
            Task { @MainActor in
                state.setActiveTouches(ActiveTouchIndicatorLifecycle.contacts(for: event))
            }
        }
        self.coordinator = GestureCoordinator(
            mapper: CoordinateMapper(
                captureRect: .zero,
                simulatorSize: Self.fallbackSimulatorSize
            ),
            sink: observingSink,
            logger: logger
        )
        self.windowTracker = SimulatorWindowTracker(logger: logger)
        self.lastEnabled = state.snapshot.preferences.isEnabled
        self.lastCalibrationMode = state.snapshot.isCalibrationMode

        configureCallbacks()
        stateObserver = state.observe { [weak self] snapshot in
            self?.apply(snapshot)
        }
    }

    func start() {
        installModifierMonitors()
        guard state.snapshot.preferences.isEnabled else { return }
        attemptAttach(promptForAccessibility: true)
    }

    func reattach() {
        stopActiveInput(reason: "manual reattach")
        state.transition(to: .waiting("Reattaching to Simulator"))
        attemptAttach(promptForAccessibility: true)
    }

    func shutdown() {
        retryTimer?.invalidate()
        retryTimer = nil
        removeModifierMonitors()
        stopActiveInput(reason: "application shutdown")
        overlay.hide()
    }

    private func configureCallbacks() {
        overlay.onInputDeactivated = { [weak self] in
            self?.coordinator.cancelAll(reason: "overlay input deactivated")
        }
        overlay.onMouseDown = { [weak self] point in
            guard self?.canInjectInput == true else { return }
            self?.coordinator.beginMouse(at: point)
        }
        overlay.onMouseDragged = { [weak self] point in
            guard self?.canInjectInput == true else { return }
            self?.coordinator.updateMouse(at: point)
        }
        overlay.onMouseUp = { [weak self] point in
            guard self?.canInjectInput == true else { return }
            self?.coordinator.endMouse(at: point)
        }
        overlay.onMouseMoved = { [weak self] point in
            guard let self, canInjectInput else { return }
            let snapshot = state.snapshot
            if (snapshot.preferences.inputMode == .point || snapshot.preferences.inputMode == .edge),
               snapshot.anchorLockState == .unlocked {
                coordinator.updatePointer(point)
            } else if isOptionPressed {
                refreshOptionPreview()
            }
        }
        overlay.onCalibrationFrameChange = { [weak self] frame in
            self?.finishCalibration(frame: frame)
        }
        coordinator.onStateChange = { [weak self] in
            self?.refreshAnchorIndicator()
        }
        sink.onError = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.fail(.hidInitialization(message))
            }
        }
        coordinator.setRawGestureInputProvider { [weak self] in
            self?.currentRawGestureInputSample() ?? .none
        }
    }

    private func apply(_ snapshot: GlidexAppSnapshot) {
        coordinator.setMode(snapshot.preferences.inputMode)
        coordinator.setAnchorLocked(snapshot.anchorLockState == .locked)
        refreshAnchorIndicator()
        refreshOptionPreview()

        let becameEnabled = snapshot.preferences.isEnabled && !lastEnabled
        let becameDisabled = !snapshot.preferences.isEnabled && lastEnabled
        let enteredCalibration = snapshot.isCalibrationMode && !lastCalibrationMode
        let exitedCalibration = !snapshot.isCalibrationMode && lastCalibrationMode
        lastEnabled = snapshot.preferences.isEnabled
        lastCalibrationMode = snapshot.isCalibrationMode

        if becameDisabled {
            retryTimer?.invalidate()
            retryTimer = nil
            stopActiveInput(reason: "Glidex paused")
        } else if becameEnabled {
            attemptAttach(promptForAccessibility: true)
        } else if enteredCalibration {
            coordinator.cancelAll(reason: "calibration started")
            windowTracker.stop()
        } else if exitedCalibration {
            resumeAfterCalibration()
        }
    }

    private func attemptAttach(promptForAccessibility: Bool) {
        guard state.snapshot.preferences.isEnabled, !isAttaching else { return }
        isAttaching = true
        defer { isAttaching = false }

        let options = ["AXTrustedCheckOptionPrompt": promptForAccessibility]
        guard AXIsProcessTrustedWithOptions(options as CFDictionary) else {
            fail(.accessibilityPermission, retry: true)
            return
        }
        installModifierMonitors()

        let displays = windowTracker.discoverTargets(simulatorSize: Self.fallbackSimulatorSize.cgSize)
        guard !displays.isEmpty else {
            wait(reason: "Looking for Simulator window")
            return
        }
        do {
            let devices = try injector.listBootedSimulators()
            switch SimulatorDisplaySelector.resolve(
                displays: displays.map(\.descriptor),
                devices: devices
            ) {
            case .unavailable:
                wait(reason: devices.isEmpty ? "No booted Simulator" : "Looking for Simulator window")
            case .ambiguous:
                fail(.ambiguousTarget, retry: true)
            case let .selected(descriptor, record):
                guard let tracked = displays.first(where: { $0.descriptor == descriptor }) else {
                    wait(reason: "Simulator display changed during attachment")
                    return
                }
                logger.info(
                    "selected display host=\(descriptor.hostKind.rawValue) pid=\(descriptor.ownerPID) displayUDID=\(descriptor.deviceUDID ?? "unavailable") targetUDID=\(record.udid)"
                )
                attach(record: record, tracked: tracked)
            }
        } catch {
            fail(.other("Simulator discovery failed: \(error)"), retry: true)
        }
    }

    private func attach(record: BootedSimulatorRecord, tracked: SimulatorWindowTracker.Target) {
        do {
            state.transition(to: .connecting)
            stopActiveInput(reason: "Simulator target changing")
            coordinator.prepareForDeviceChange()

            guard tracked.kind == .screen else {
                wait(reason: "Locating Simulator screen")
                return
            }
            guard let resolution = DeveloperDirectoryResolver().resolve(hostBundleURL: tracked.hostBundleURL) else {
                fail(.hidInitialization("No compatible SimulatorKit found for \(tracked.descriptor.hostKind.rawValue)"), retry: true)
                return
            }
            injector.useDeveloperDirectory(resolution)
            let target = try injector.selectTarget(udid: record.udid)

            nativeTarget = target
            state.resetAnchorLockForAttachment()
            lastSimulatorPID = tracked.ownerPID
            lastHostTarget = tracked
            frameAdjustment = OverlayFrameAdjustment()
            applyTrackedTarget(
                tracked,
                nativeTarget: target,
                reason: "Simulator attached",
                activate: false
            )
            guard startRawTouchStream() else { return }
            startWindowTracking(for: target, hostTarget: tracked)
            retryTimer?.invalidate()
            retryTimer = nil
            state.transition(to: .active, target: selectedTarget)
            logger.info("capture session active target=\(target.name) udid=\(target.udid)")
        } catch {
            fail(.hidInitialization(String(describing: error)), retry: true)
        }
    }

    private func startRawTouchStream() -> Bool {
        guard rawTouchStream == nil else { return true }
        rawStreamGeneration += 1
        let generation = rawStreamGeneration
        let stream = MultitouchSupportRawTouchStream(logger: logger) { [weak self] frame in
            DispatchQueue.main.async {
                guard let self,
                      self.rawStreamGeneration == generation,
                      self.canInjectInput else { return }
                if self.awaitsTouchRelease {
                    if frame.contacts.isEmpty { self.awaitsTouchRelease = false }
                    return
                }
                self.coordinator.handleRawFrame(frame)
            }
        }
        do {
            try stream.start(source: .default, mode: 0)
            rawTouchStream = stream
            awaitsTouchRelease = false
            return true
        } catch {
            fail(.multitouchUnavailable(String(describing: error)), retry: true)
            return false
        }
    }

    private func startWindowTracking(
        for target: SimulatorTarget,
        hostTarget: SimulatorWindowTracker.Target
    ) {
        windowTracker.stop()
        windowTracker.start(target: hostTarget, simulatorSize: target.pointSize.cgSize) { [weak self] lookup in
            self?.handleTrackedLookup(lookup, expectedTarget: target)
        }
    }

    private func handleTrackedLookup(
        _ lookup: SimulatorWindowTracker.Lookup,
        expectedTarget: SimulatorTarget
    ) {
        switch lookup {
        case .none:
            wait(reason: "Simulator window closed")
        case .ambiguous:
            fail(.ambiguousTarget, retry: true)
        case let .target(tracked):
            guard tracked.kind == .screen else {
                wait(reason: "Locating Simulator screen")
                return
            }
            if let udid = tracked.descriptor.deviceUDID,
               udid.caseInsensitiveCompare(expectedTarget.udid) != .orderedSame {
                reattach()
                return
            }
            if tracked.descriptor.hostKind == .legacySimulator,
               let title = tracked.windowTitle,
               !title.localizedCaseInsensitiveContains(expectedTarget.name) {
                reattach()
                return
            }
            if let lastSimulatorPID, tracked.ownerPID != lastSimulatorPID {
                reattach()
                return
            }
            guard !state.snapshot.isCalibrationMode else { return }
            lastHostTarget = tracked
            applyTrackedTarget(
                tracked,
                nativeTarget: expectedTarget,
                reason: "Simulator geometry changed"
            )
        }
    }

    private func applyTrackedTarget(
        _ tracked: SimulatorWindowTracker.Target,
        nativeTarget: SimulatorTarget,
        reason: String,
        activate: Bool = true
    ) {
        let adjustedFrame = frameAdjustment.applying(to: tracked.frame)
        let geometry = SimulatorDisplayGeometry(
            desktopFrame: adjustedFrame,
            nativeSimulatorSize: nativeTarget.pointSize
        )
        let orientedTarget = nativeTarget.withPointSize(geometry.simulatorSize)
        guard selectedTarget != orientedTarget || !overlay.frame.isNearlyEqual(to: adjustedFrame) else {
            lastTrackedFrame = tracked.frame
            return
        }

        coordinator.cancelAll(reason: reason)
        awaitsTouchRelease = true
        selectedTarget = orientedTarget
        lastTrackedFrame = tracked.frame
        lastSimulatorPID = tracked.ownerPID
        overlay.show(frame: geometry.desktopFrame)
        coordinator.updateMapper(geometry.mapper)
        state.setActiveTouches([])
        refreshAnchorIndicator()
        if activate {
            state.transition(to: .active, target: orientedTarget)
        }
        refreshOptionPreview()
    }

    private func finishCalibration(frame: CGRect) {
        if let lastTrackedFrame {
            frameAdjustment = OverlayFrameAdjustment(base: lastTrackedFrame, adjusted: frame)
        }
        guard let nativeTarget else { return }
        let geometry = SimulatorDisplayGeometry(
            desktopFrame: frame,
            nativeSimulatorSize: nativeTarget.pointSize
        )
        selectedTarget = nativeTarget.withPointSize(geometry.simulatorSize)
        coordinator.updateMapper(geometry.mapper)
        state.setActiveTouches([])
        refreshAnchorIndicator()
        state.transition(to: .active, target: selectedTarget)
    }

    private func resumeAfterCalibration() {
        guard let nativeTarget else {
            attemptAttach(promptForAccessibility: false)
            return
        }
        finishCalibration(frame: overlay.frame)
        guard let lastHostTarget else {
            attemptAttach(promptForAccessibility: false)
            return
        }
        startWindowTracking(for: nativeTarget, hostTarget: lastHostTarget)
    }

    private func wait(reason: String) {
        stopActiveInput(reason: reason)
        selectedTarget = nil
        nativeTarget = nil
        lastTrackedFrame = nil
        lastHostTarget = nil
        lastSimulatorPID = nil
        overlay.hide()
        state.transition(to: .waiting(reason))
        scheduleRetry()
    }

    private func fail(_ error: GlidexRuntimeError, retry: Bool = false) {
        stopActiveInput(reason: error.message)
        state.transition(to: .error(error), target: selectedTarget)
        if retry { scheduleRetry() }
    }

    private func stopActiveInput(reason: String) {
        coordinator.cancelAll(reason: reason)
        state.setOptionAnchorAvailability(.inactive)
        state.clearIndicators()
        rawTouchStream?.stop()
        rawTouchStream = nil
        rawStreamGeneration += 1
        awaitsTouchRelease = false
        windowTracker.stop()
    }

    private func scheduleRetry() {
        guard retryTimer == nil, state.snapshot.preferences.isEnabled else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.attemptAttach(promptForAccessibility: false)
            }
        }
        retryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private var canInjectInput: Bool {
        state.snapshot.preferences.isEnabled &&
            state.snapshot.status == .active &&
            !state.snapshot.isCalibrationMode
    }

    private var isOptionPressed: Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate)
    }

    private func currentRawGestureInputSample() -> GestureInputSample {
        let desktopPoint = DesktopPoint(NSEvent.mouseLocation)
        let capturePoint = overlay.capturePoint(fromDesktop: desktopPoint)
        let optionPressed = isOptionPressed
        updateOptionPreview(
            optionPressed: optionPressed,
            capturePoint: capturePoint
        )
        return GestureInputSample(
            optionPressed: optionPressed,
            globalMouseLocation: desktopPoint,
            captureMouseLocation: capturePoint
        )
    }

    private func refreshOptionPreview() {
        guard state.snapshot.preferences.inputMode == .navigate, canInjectInput else {
            state.setOptionAnchorAvailability(.inactive)
            refreshAnchorIndicator()
            return
        }
        let desktopPoint = DesktopPoint(NSEvent.mouseLocation)
        updateOptionPreview(
            optionPressed: isOptionPressed,
            capturePoint: overlay.capturePoint(fromDesktop: desktopPoint)
        )
    }

    private func updateOptionPreview(optionPressed: Bool, capturePoint: CapturePoint?) {
        guard state.snapshot.preferences.inputMode == .navigate, optionPressed else {
            state.setOptionAnchorAvailability(.inactive)
            refreshAnchorIndicator()
            return
        }
        guard let capturePoint,
              let simulatorPoint = coordinator.simulatorPoint(fromCapture: capturePoint) else {
            state.setOptionAnchorAvailability(.outsideSimulator)
            state.setAnchorIndicator(.none)
            return
        }
        state.setOptionAnchorAvailability(.available(simulatorPoint))
        state.setAnchorIndicator(.temporary(simulatorPoint))
    }

    private func refreshAnchorIndicator() {
        if case let .available(point) = state.snapshot.optionAnchorAvailability {
            state.setAnchorIndicator(.temporary(point))
            return
        }
        let mode = state.snapshot.preferences.inputMode
        if (mode == .point || mode == .edge), let point = coordinator.virtualFingerPoint {
            state.setAnchorIndicator(.fixed(point))
        } else {
            state.setAnchorIndicator(.none)
        }
    }

    private func installModifierMonitors() {
        if globalModifierMonitor == nil {
            globalModifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] _ in
                Task { @MainActor [weak self] in self?.refreshOptionPreview() }
            }
        }
        if localModifierMonitor == nil {
            localModifierMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.refreshOptionPreview()
                return event
            }
        }
    }

    private func removeModifierMonitors() {
        if let globalModifierMonitor {
            NSEvent.removeMonitor(globalModifierMonitor)
            self.globalModifierMonitor = nil
        }
        if let localModifierMonitor {
            NSEvent.removeMonitor(localModifierMonitor)
            self.localModifierMonitor = nil
        }
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
