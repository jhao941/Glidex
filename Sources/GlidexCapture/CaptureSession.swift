import AppKit
import ApplicationServices
import GlidexCore

enum CaptureAutomationState: Equatable {
    case idle(hasRecording: Bool)
    case recording
    case replaying(String)

    var isIdle: Bool {
        if case .idle = self { true } else { false }
    }

    var acceptsLiveInput: Bool {
        if case .replaying = self { false } else { true }
    }
}

enum CaptureAutomationError: LocalizedError {
    case simulatorUnavailable
    case automationBusy
    case notRecording
    case noRecording

    var errorDescription: String? {
        switch self {
        case .simulatorUnavailable: "Glidex must be active and attached to a Simulator."
        case .automationBusy: "Stop the current recording or replay first."
        case .notRecording: "No gesture recording is active."
        case .noRecording: "No saved gesture recording is available."
        }
    }
}

@MainActor
final class CaptureSession {
    private enum RawInputAdmission: Equatable {
        case idle
        case allowed
        case blocked
    }

    private static let fallbackSimulatorSize = SimulatorPointSize(width: 402, height: 874)

    private let logger: Logger
    private let state: GlidexAppState
    private let overlay: OverlayWindowController
    private let injector: SimulatorInjector
    private let sink: IndigoTouchSink
    private let observingSink: TouchObservingSink
    private let coordinator: GestureCoordinator
    private let windowTracker: SimulatorWindowTracker
    private let recorder: GestureRecorder
    private let replayEngine: GestureReplayEngine
    private let recordingStore: GestureRecordingStore

    private var rawTouchStream: MultitouchSupportRawTouchStream?
    private var rawStreamGeneration = 0
    private var awaitsTouchRelease = false
    private var physicalActiveContactCount = 0
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
    private var globalShortcutMonitor: Any?
    private var localShortcutMonitor: Any?
    private var rawInputAdmission: RawInputAdmission = .idle
    private(set) var automationState: CaptureAutomationState {
        didSet { onAutomationStateChange?(automationState) }
    }
    var onAutomationStateChange: ((CaptureAutomationState) -> Void)?

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
        let recorder = GestureRecorder()
        self.sink = sink
        self.recorder = recorder
        self.observingSink = TouchObservingSink(downstream: sink) { event in
            recorder.record(event)
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
        self.replayEngine = GestureReplayEngine(sink: observingSink)
        let recordingDirectory = try GestureRecordingStore.defaultDirectoryURL()
        self.recordingStore = GestureRecordingStore(directoryURL: recordingDirectory)
        self.windowTracker = SimulatorWindowTracker(logger: logger)
        self.lastEnabled = state.snapshot.preferences.isEnabled
        self.lastCalibrationMode = state.snapshot.isCalibrationMode
        self.automationState = .idle(hasRecording: (try? recordingStore.latest()) != nil)

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

    func startRecording() throws {
        guard automationState.isIdle else { throw CaptureAutomationError.automationBusy }
        guard canOperateAutomation, let target = selectedTarget else {
            throw CaptureAutomationError.simulatorUnavailable
        }
        try recorder.start(
            name: "Recording \(Self.recordingNameFormatter.string(from: Date()))",
            sourceScreen: target.pointSize
        )
        automationState = .recording
        logger.info("gesture recording started target=\(target.udid) size=\(target.pointSize.width)x\(target.pointSize.height)")
    }

    @discardableResult
    func stopRecording() throws -> StoredGestureRecording {
        guard automationState == .recording,
              let recording = recorder.stop() else {
            throw CaptureAutomationError.notRecording
        }
        do {
            let stored = try recordingStore.save(recording)
            automationState = .idle(hasRecording: true)
            logger.info("gesture recording saved events=\(recording.events.count) path=\(stored.url.path)")
            return stored
        } catch {
            automationState = .idle(hasRecording: hasStoredRecording)
            throw error
        }
    }

    func replayLatestRecording() throws {
        guard automationState.isIdle else { throw CaptureAutomationError.automationBusy }
        guard canOperateAutomation, selectedTarget != nil else {
            throw CaptureAutomationError.simulatorUnavailable
        }
        guard let stored = try recordingStore.latest() else {
            throw CaptureAutomationError.noRecording
        }

        try replay(stored)
    }

    func replayRecording(at url: URL) throws {
        guard automationState.isIdle else { throw CaptureAutomationError.automationBusy }
        guard canOperateAutomation else { throw CaptureAutomationError.simulatorUnavailable }
        try replay(recordingStore.load(from: url))
    }

    func prepareRecordingsDirectory() throws -> URL {
        try recordingStore.prepareDirectory()
        return recordingStore.directoryURL
    }

    private func replay(_ stored: StoredGestureRecording) throws {
        guard let target = selectedTarget else {
            throw CaptureAutomationError.simulatorUnavailable
        }

        coordinator.cancelAll(reason: "gesture replay started")
        state.setOptionAnchorAvailability(.inactive)
        state.clearIndicators()
        rawInputAdmission = .blocked
        automationState = .replaying(stored.recording.name)
        do {
            try replayEngine.play(
                stored.recording,
                targetScreen: target.pointSize
            ) { [weak self] outcome in
                self?.finishReplay(outcome)
            }
            logger.info("gesture replay started name=\(stored.recording.name) events=\(stored.recording.events.count)")
        } catch {
            rawInputAdmission = .idle
            automationState = .idle(hasRecording: true)
            throw error
        }
    }

    func stopReplay() {
        replayEngine.stop()
    }

    func diagnostics() -> CaptureDiagnostics {
        CaptureDiagnostics(
            snapshot: state.snapshot,
            rawTouchStreamRunning: rawTouchStream != nil,
            windowTrackingRunning: windowTracker.isFollowing,
            hostDescriptor: lastHostTarget?.descriptor,
            overlayFrame: overlay.frame,
            overlayVisible: overlay.isVisible
        )
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
            guard let self, canInjectInput else { return }
            coordinator.beginMouse(at: point)
        }
        overlay.onMouseDragged = { [weak self] point in
            guard let self, canInjectInput else { return }
            coordinator.updateMouse(at: point)
        }
        overlay.onMouseUp = { [weak self] point in
            guard let self, canInjectInput else { return }
            coordinator.endMouse(at: point)
        }
        overlay.onMouseMoved = { [weak self] _ in
            guard let self, canInjectInput else { return }
            if isOptionPressed {
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
        overlay.setFollowsHostOcclusion(snapshot.preferences.requiresPointerOverSimulator)
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
        if !displays.isEmpty {
            logger.info("discovered display hosts: \(displays.map { "\($0.descriptor.hostKind.rawValue):\($0.descriptor.deviceUDID ?? "unknown")" }.joined(separator: ","))")
        }
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
            logger.info(
                "selected injection toolchain=\(resolution.developerDirectory) displayHost=\(tracked.descriptor.hostKind.rawValue) displayHostToolchain=\(tracked.descriptor.developerDirectory ?? "unknown")"
            )
            try injector.useDeveloperDirectory(resolution)
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
                      self.rawStreamGeneration == generation else { return }
                self.physicalActiveContactCount = frame.contacts.filter(\.isActive).count
                guard self.canInjectInput else { return }
                if self.awaitsTouchRelease {
                    if frame.contacts.isEmpty { self.awaitsTouchRelease = false }
                    return
                }
                self.handleRawFrameWithAdmission(frame)
            }
        }
        do {
            try stream.start(source: .default, mode: 0)
            rawTouchStream = stream
            awaitsTouchRelease = false
            physicalActiveContactCount = 0
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
        overlay.show(
            frame: geometry.desktopFrame,
            hostWindowNumber: PointerInputEligibility.hostWindowNumber(for: tracked),
            hostOwnerPID: tracked.ownerPID
        )
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
        replayEngine.stop()
        recorder.discard()
        automationState = .idle(hasRecording: hasStoredRecording)
        coordinator.cancelAll(reason: reason)
        state.setOptionAnchorAvailability(.inactive)
        state.clearIndicators()
        rawTouchStream?.stop()
        rawTouchStream = nil
        rawStreamGeneration += 1
        awaitsTouchRelease = false
        physicalActiveContactCount = 0
        rawInputAdmission = .idle
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
        automationState.acceptsLiveInput &&
            canOperateAutomation
    }

    private var canOperateAutomation: Bool {
        state.snapshot.preferences.isEnabled &&
            state.snapshot.status == .active &&
            !state.snapshot.isCalibrationMode
    }

    private var hasStoredRecording: Bool {
        (try? recordingStore.latest()) != nil
    }

    private func finishReplay(_ outcome: GestureReplayOutcome) {
        guard case .replaying = automationState else { return }
        rawInputAdmission = .idle
        awaitsTouchRelease = physicalActiveContactCount > 0
        automationState = .idle(hasRecording: hasStoredRecording)
        switch outcome {
        case .completed:
            logger.info("gesture replay completed")
        case .stopped:
            logger.info("gesture replay stopped")
        case let .failed(message):
            logger.error("gesture replay failed: \(message)")
        }
    }

    private var isOptionPressed: Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskAlternate)
    }

    private func handleRawFrameWithAdmission(_ frame: RawTouchFrame) {
        let activeContactCount = frame.contacts.filter(\.isActive).count
        switch rawInputAdmission {
        case .idle:
            if activeContactCount >= state.snapshot.preferences.inputMode.rawInputStartContactCount {
                rawInputAdmission = allowsNewInputAtPointer() ? .allowed : .blocked
            }
            if rawInputAdmission != .blocked {
                coordinator.handleRawFrame(frame)
            }
        case .allowed:
            coordinator.handleRawFrame(frame)
        case .blocked:
            break
        }
        if activeContactCount == 0 {
            rawInputAdmission = .idle
        }
    }

    private func allowsNewInputAtPointer() -> Bool {
        guard state.snapshot.preferences.requiresPointerOverSimulator else { return true }
        if state.snapshot.preferences.inputMode == .directTouch {
            return PointerInputEligibility.isSimulatorVisible(overlay: overlay)
        }
        return PointerInputEligibility.isEligible(
            pointer: DesktopPoint(NSEvent.mouseLocation),
            overlay: overlay
        )
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
        if globalShortcutMonitor == nil {
            globalShortcutMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard Self.isDirectTouchShortcut(event) else { return }
                Task { @MainActor [weak self] in self?.state.toggleDirectTouchMode() }
            }
        }
        if localShortcutMonitor == nil {
            localShortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard Self.isDirectTouchShortcut(event) else { return event }
                self?.state.toggleDirectTouchMode()
                return nil
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
        if let globalShortcutMonitor {
            NSEvent.removeMonitor(globalShortcutMonitor)
            self.globalShortcutMonitor = nil
        }
        if let localShortcutMonitor {
            NSEvent.removeMonitor(localShortcutMonitor)
            self.localShortcutMonitor = nil
        }
    }

    private static func isDirectTouchShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.charactersIgnoringModifiers?.lowercased() == "d" &&
            modifiers == [.control, .option]
    }

    private static let recordingNameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

private extension CGRect {
    func isNearlyEqual(to other: CGRect, tolerance: CGFloat = 1) -> Bool {
        abs(minX - other.minX) <= tolerance &&
            abs(minY - other.minY) <= tolerance &&
            abs(width - other.width) <= tolerance &&
            abs(height - other.height) <= tolerance
    }
}
