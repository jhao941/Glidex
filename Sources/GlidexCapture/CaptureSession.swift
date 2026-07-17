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
        case .simulatorUnavailable: L10n.text("Glidex must be active and attached to a Simulator.")
        case .automationBusy: L10n.text("Stop the current recording or replay first.")
        case .notRecording: L10n.text("No gesture recording is active.")
        case .noRecording: L10n.text("No saved gesture recording is available.")
        }
    }
}

@MainActor
final class CaptureSession {
    private struct ReplayRequest {
        let stored: StoredGestureRecording
        let playbackRate: Double
        let loops: Bool
    }

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
    private let calibrationStore: CalibrationProfileStore

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
    private var calibrationProfileKey: CalibrationProfileKey?
    private var lastEnabled: Bool
    private var lastCalibrationMode: Bool
    private var isAttaching = false
    private var globalModifierMonitor: Any?
    private var localModifierMonitor: Any?
    private var globalShortcutMonitor: Any?
    private var localShortcutMonitor: Any?
    private var rawInputAdmission: RawInputAdmission = .idle
    private var replayRequest: ReplayRequest?
    private(set) var availableSimulators: [BootedSimulatorRecord] = []
    private(set) var automationState: CaptureAutomationState {
        didSet { onAutomationStateChange?(automationState) }
    }
    var onAutomationStateChange: ((CaptureAutomationState) -> Void)?
    var onAvailableSimulatorsChange: (([BootedSimulatorRecord]) -> Void)? {
        didSet { onAvailableSimulatorsChange?(availableSimulators) }
    }

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
        self.calibrationStore = CalibrationProfileStore()
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

    func followFocusedSimulator() {
        state.followFocusedSimulator()
        if let ownerPID = windowTracker.frontmostHostPID {
            handleHostApplicationActivated(ownerPID: ownerPID)
        }
    }

    func pinCurrentSimulator() {
        guard let udid = nativeTarget?.udid else { return }
        state.pinSimulator(udid: udid)
    }

    func selectSimulator(udid: String) {
        guard automationState.isIdle else {
            logger.warn("ignoring manual device switch while gesture automation is active target=\(udid)")
            return
        }
        guard let currentTarget = nativeTarget else {
            state.pinSimulator(udid: udid)
            reattach()
            return
        }
        if currentTarget.udid.caseInsensitiveCompare(udid) == .orderedSame {
            state.pinSimulator(udid: udid)
            return
        }

        do {
            let devices = try loadAvailableSimulators()
            let displays = windowTracker.discoverTargets(
                simulatorSize: currentTarget.pointSize.cgSize
            )
            let decision = SimulatorAttachmentPolicy.decide(
                displays: displays.map(\.descriptor),
                devices: devices,
                targetingMode: .pinned,
                pinnedUDID: udid,
                currentUDID: currentTarget.udid,
                currentDisplay: lastHostTarget?.descriptor
            )
            switch decision {
            case let .switchDevice(descriptor, record):
                guard let tracked = displays.first(where: { $0.descriptor == descriptor }),
                      switchToDisplay(record: record, tracked: tracked, currentTarget: currentTarget) else { return }
                state.pinSimulator(udid: udid)
            case .keepCurrent, .switchHost:
                state.pinSimulator(udid: udid)
            case .unavailable, .ambiguous, .attach:
                logger.warn("manual Simulator target is unavailable or ambiguous target=\(udid)")
            }
        } catch {
            logger.error("manual Simulator target switch failed: \(error)")
        }
    }

    func startRecording() throws {
        guard automationState.isIdle else { throw CaptureAutomationError.automationBusy }
        guard canOperateAutomation, let target = selectedTarget else {
            throw CaptureAutomationError.simulatorUnavailable
        }
        try recorder.start(
            name: L10n.text("Recording %@", Self.recordingNameFormatter.string(from: Date())),
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

    func recordings() throws -> [StoredGestureRecording] {
        try recordingStore.recordings()
    }

    @discardableResult
    func importRecording(from url: URL) throws -> StoredGestureRecording {
        let stored = try recordingStore.importRecording(from: url)
        refreshRecordingAvailability()
        return stored
    }

    @discardableResult
    func renameRecording(_ stored: StoredGestureRecording, to name: String) throws -> StoredGestureRecording {
        let renamed = try recordingStore.rename(stored, to: name)
        refreshRecordingAvailability()
        return renamed
    }

    func deleteRecording(_ stored: StoredGestureRecording) throws {
        guard automationState.isIdle else { throw CaptureAutomationError.automationBusy }
        try recordingStore.delete(stored)
        refreshRecordingAvailability()
    }

    func exportRecording(_ stored: StoredGestureRecording, to url: URL) throws {
        try recordingStore.export(stored, to: url)
    }

    func replayRecording(
        _ stored: StoredGestureRecording,
        playbackRate: Double,
        loops: Bool
    ) throws {
        guard automationState.isIdle else { throw CaptureAutomationError.automationBusy }
        guard canOperateAutomation else { throw CaptureAutomationError.simulatorUnavailable }
        try replay(stored, playbackRate: playbackRate, loops: loops)
    }

    func prepareRecordingsDirectory() throws -> URL {
        try recordingStore.prepareDirectory()
        return recordingStore.directoryURL
    }

    private func replay(
        _ stored: StoredGestureRecording,
        playbackRate: Double = 1,
        loops: Bool = false
    ) throws {
        guard let target = selectedTarget else {
            throw CaptureAutomationError.simulatorUnavailable
        }

        coordinator.cancelAll(reason: "gesture replay started")
        state.setOptionAnchorAvailability(.inactive)
        state.clearIndicators()
        rawInputAdmission = .blocked
        automationState = .replaying(stored.recording.name)
        replayRequest = ReplayRequest(
            stored: stored,
            playbackRate: playbackRate,
            loops: loops
        )
        do {
            try startReplayCycle(target: target)
            logger.info("gesture replay started name=\(stored.recording.name) events=\(stored.recording.events.count)")
        } catch {
            replayRequest = nil
            rawInputAdmission = .idle
            automationState = .idle(hasRecording: true)
            throw error
        }
    }

    private func startReplayCycle(target: SimulatorTarget) throws {
        guard let replayRequest else { return }
        try replayEngine.play(
            replayRequest.stored.recording,
            targetScreen: target.pointSize,
            playbackRate: replayRequest.playbackRate
        ) { [weak self] outcome in
            self?.finishReplay(outcome)
        }
    }

    func stopReplay() {
        replayEngine.stop()
    }

    func diagnostics() -> CaptureDiagnostics {
        let compatibility = CompatibilitySelfCheck.run(
            hostBundleURL: lastHostTarget?.hostBundleURL,
            hostDetected: lastHostTarget != nil,
            bootedSimulatorCount: availableSimulators.count,
            rawTouchStreamRunning: rawTouchStream != nil,
            hidTargetReady: selectedTarget != nil && state.snapshot.status == .active
        )
        return CaptureDiagnostics(
            snapshot: state.snapshot,
            rawTouchStreamRunning: rawTouchStream != nil,
            windowTrackingRunning: windowTracker.isFollowing,
            hostDescriptor: lastHostTarget?.descriptor,
            overlayFrame: overlay.frame,
            overlayVisible: overlay.isVisible,
            compatibility: compatibility
        )
    }

    func shutdown() {
        retryTimer?.invalidate()
        retryTimer = nil
        removeModifierMonitors()
        stopActiveInput(reason: "application shutdown")
        windowTracker.shutdown()
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
        windowTracker.onHostApplicationActivated = { [weak self] ownerPID in
            self?.handleHostApplicationActivated(ownerPID: ownerPID)
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

        let devices: [BootedSimulatorRecord]
        do {
            devices = try loadAvailableSimulators()
        } catch {
            fail(.other("Simulator discovery failed: \(error)"), retry: true)
            return
        }

        let discoveredDisplays = windowTracker.discoverTargets(simulatorSize: Self.fallbackSimulatorSize.cgSize)
        let displays: [SimulatorWindowTracker.Target]
        if state.snapshot.preferences.simulatorTargetingMode == .followFocus,
           let frontmostHostPID = windowTracker.frontmostHostPID {
            let focusedDisplays = windowTracker.discoverTargets(
                ownerPID: frontmostHostPID,
                simulatorSize: Self.fallbackSimulatorSize.cgSize
            )
            displays = focusedDisplays.isEmpty ? discoveredDisplays : focusedDisplays
        } else {
            displays = discoveredDisplays
        }
        if !displays.isEmpty {
            logger.info("discovered display hosts: \(displays.map { "\($0.descriptor.hostKind.rawValue):\($0.descriptor.deviceUDID ?? "unknown")" }.joined(separator: ","))")
        }
        guard !displays.isEmpty else {
            wait(reason: "Looking for Simulator window")
            return
        }
        switch SimulatorAttachmentPolicy.decide(
            displays: displays.map(\.descriptor),
            devices: devices,
            targetingMode: state.snapshot.preferences.simulatorTargetingMode,
            pinnedUDID: state.snapshot.preferences.pinnedSimulatorUDID,
            currentUDID: nil,
            currentDisplay: nil
        ) {
        case .unavailable:
            if state.snapshot.preferences.simulatorTargetingMode == .pinned {
                wait(reason: "Pinned Simulator is unavailable")
            } else {
                wait(reason: devices.isEmpty ? "No booted Simulator" : "Looking for Simulator window")
            }
        case .ambiguous:
            fail(.ambiguousTarget, retry: true)
        case let .attach(descriptor, record):
            guard let tracked = displays.first(where: { $0.descriptor == descriptor }) else {
                wait(reason: "Simulator display changed during attachment")
                return
            }
            logger.info(
                "selected display host=\(descriptor.hostKind.rawValue) pid=\(descriptor.ownerPID) displayUDID=\(descriptor.deviceUDID ?? "unavailable") targetUDID=\(record.udid)"
            )
            attach(record: record, tracked: tracked)
        case .keepCurrent, .switchHost, .switchDevice:
            break
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
            calibrationProfileKey = nil
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

    private func handleHostApplicationActivated(ownerPID: pid_t) {
        guard state.snapshot.preferences.isEnabled,
              state.snapshot.preferences.simulatorTargetingMode == .followFocus,
              !state.snapshot.isCalibrationMode,
              !isAttaching else { return }
        guard let nativeTarget else {
            attemptAttach(promptForAccessibility: false)
            return
        }

        let displays = windowTracker.discoverTargets(
            ownerPID: ownerPID,
            simulatorSize: nativeTarget.pointSize.cgSize
        )
        do {
            let devices = try loadAvailableSimulators()
            switch SimulatorAttachmentPolicy.decide(
                displays: displays.map(\.descriptor),
                devices: devices,
                targetingMode: .followFocus,
                pinnedUDID: nil,
                currentUDID: nativeTarget.udid,
                currentDisplay: lastHostTarget?.descriptor,
                activatedOwnerPID: ownerPID
            ) {
            case .unavailable:
                logger.warn("activated display host has no attachable Simulator screen pid=\(ownerPID)")
            case .ambiguous:
                logger.warn("activated display host is ambiguous pid=\(ownerPID)")
            case .keepCurrent:
                return
            case let .switchHost(descriptor, record), let .switchDevice(descriptor, record):
                guard let tracked = displays.first(where: { $0.descriptor == descriptor }) else { return }
                _ = switchToDisplay(record: record, tracked: tracked, currentTarget: nativeTarget)
            case let .attach(descriptor, record):
                guard let tracked = displays.first(where: { $0.descriptor == descriptor }) else { return }
                attach(record: record, tracked: tracked)
            }
        } catch {
            logger.error("activated display host discovery failed: \(error)")
        }
    }

    @discardableResult
    private func switchToDisplay(
        record: BootedSimulatorRecord,
        tracked: SimulatorWindowTracker.Target,
        currentTarget: SimulatorTarget
    ) -> Bool {
        guard tracked.kind == .screen else {
            logger.warn("activated display host screen is not ready pid=\(tracked.ownerPID)")
            return false
        }
        if lastHostTarget?.descriptor.representsSameDisplay(as: tracked.descriptor) == true {
            return true
        }

        let isSameDevice = record.udid.caseInsensitiveCompare(currentTarget.udid) == .orderedSame
        guard isSameDevice || automationState.isIdle else {
            logger.warn("ignoring device switch while gesture automation is active target=\(record.udid)")
            return false
        }

        let previousAdjustment = frameAdjustment
        let previousCalibrationKey = calibrationProfileKey
        do {
            let target: SimulatorTarget
            let preparedTarget: SimulatorInjector.PreparedTarget?
            if isSameDevice {
                target = currentTarget
                preparedTarget = nil
            } else {
                let prepared = try injector.prepareTarget(udid: record.udid)
                target = prepared.target
                preparedTarget = prepared
                coordinator.prepareForDeviceChange()
                state.resetAnchorLockForAttachment()
            }

            windowTracker.stop()
            calibrationProfileKey = nil
            applyTrackedTarget(
                tracked,
                nativeTarget: target,
                reason: isSameDevice ? "Display host focus changed" : "Focused Simulator device changed"
            )
            startWindowTracking(for: target, hostTarget: tracked)
            if let preparedTarget {
                injector.commitTarget(preparedTarget)
                nativeTarget = target
            }
            retryTimer?.invalidate()
            retryTimer = nil
            state.transition(to: .active, target: selectedTarget)
            logger.info(
                "capture display focus switched host=\(tracked.descriptor.hostKind.rawValue) pid=\(tracked.ownerPID) target=\(target.udid)"
            )
            return true
        } catch {
            logger.error("focused Simulator target switch failed: \(error)")
            frameAdjustment = previousAdjustment
            calibrationProfileKey = previousCalibrationKey
            startWindowTracking(for: currentTarget, hostTarget: lastHostTarget ?? tracked)
            return false
        }
    }

    private func loadAvailableSimulators() throws -> [BootedSimulatorRecord] {
        let devices = try injector.listBootedSimulators()
        if devices != availableSimulators {
            availableSimulators = devices
            onAvailableSimulatorsChange?(devices)
        }
        return devices
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
        let profileKey = CalibrationProfileKey(
            hostKind: tracked.descriptor.hostKind,
            deviceUDID: nativeTarget.udid,
            displayFrame: tracked.frame,
            nativeSize: nativeTarget.pointSize
        )
        if calibrationProfileKey != profileKey {
            calibrationProfileKey = profileKey
            frameAdjustment = calibrationStore.adjustment(for: profileKey) ?? OverlayFrameAdjustment()
        }
        let adjustedFrame = frameAdjustment.applying(to: tracked.frame)
        let geometry = SimulatorDisplayGeometry(
            desktopFrame: adjustedFrame,
            nativeSimulatorSize: nativeTarget.pointSize
        )
        let orientedTarget = nativeTarget.withPointSize(geometry.simulatorSize)
        let isSameDisplay = lastHostTarget?.descriptor.representsSameDisplay(as: tracked.descriptor) == true
        guard selectedTarget != orientedTarget ||
                !overlay.frame.isNearlyEqual(to: adjustedFrame) ||
                !isSameDisplay else {
            lastTrackedFrame = tracked.frame
            lastHostTarget = tracked
            return
        }

        coordinator.cancelAll(reason: reason)
        awaitsTouchRelease = true
        selectedTarget = orientedTarget
        lastTrackedFrame = tracked.frame
        lastHostTarget = tracked
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
            if let calibrationProfileKey {
                calibrationStore.save(frameAdjustment, for: calibrationProfileKey)
            }
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
        calibrationProfileKey = nil
        frameAdjustment = OverlayFrameAdjustment()
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
        replayRequest = nil
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
        if outcome == .completed,
           let replayRequest,
           replayRequest.loops,
           canOperateAutomation,
           let target = selectedTarget {
            do {
                try startReplayCycle(target: target)
                logger.info("gesture replay loop restarted name=\(replayRequest.stored.recording.name)")
                return
            } catch {
                logger.error("gesture replay loop failed: \(error)")
            }
        }
        replayRequest = nil
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

    private func refreshRecordingAvailability() {
        if automationState.isIdle {
            automationState = .idle(hasRecording: hasStoredRecording)
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
