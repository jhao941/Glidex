import AppKit
import GlidexCore
import UniformTypeIdentifiers

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let logger: Logger
    private let preferences: GlidexPreferences
    private let state: GlidexAppState
    private let statusItemController: StatusItemController
    private let overlayWindowController: OverlayWindowController
    private let diagnosticsWindowController: DiagnosticsWindowController
    private let recordingLibraryWindowController: RecordingLibraryWindowController
    private var captureSession: CaptureSession?
    private var stateObserver: UUID?
    private var lastSavedPreferences: GlidexPreferenceValues?
    private var lastLoggedState: String?

    init(logger: Logger) {
        self.logger = logger
        self.preferences = GlidexPreferences()
        self.state = GlidexAppState(snapshot: GlidexAppSnapshot(
            preferences: preferences.load()
        ))
        self.statusItemController = StatusItemController(state: state)
        self.overlayWindowController = OverlayWindowController(state: state, logger: logger)
        self.diagnosticsWindowController = DiagnosticsWindowController()
        self.recordingLibraryWindowController = RecordingLibraryWindowController()
        super.init()
        do {
            self.captureSession = try CaptureSession(
                logger: logger,
                state: state,
                overlay: overlayWindowController
            )
        } catch {
            state.transition(to: .error(.hidInitialization(String(describing: error))))
        }
        configureCommands()
    }

    func start() {
        stateObserver = state.observe { [weak self] snapshot in
            guard let self else { return }
            if lastSavedPreferences != snapshot.preferences {
                preferences.save(snapshot.preferences)
                lastSavedPreferences = snapshot.preferences
            }
            let logState = "app status=\(snapshot.status.title) enabled=\(snapshot.preferences.isEnabled) mode=\(snapshot.preferences.inputMode.rawValue) targeting=\(snapshot.preferences.simulatorTargetingMode.rawValue) pinned=\(snapshot.preferences.pinnedSimulatorUDID ?? "none") requirePointer=\(snapshot.preferences.requiresPointerOverSimulator) anchorLock=\(snapshot.anchorLockState.rawValue) anchorIndicator=\(snapshot.preferences.showsAnchorIndicator) activeTouchIndicator=\(snapshot.preferences.showsActiveTouches) activeTouches=\(snapshot.activeTouches.count) optionAnchor=\(optionAnchorLogValue(snapshot.optionAnchorAvailability)) target=\(snapshot.target?.udid ?? "none")"
            if lastLoggedState != logState {
                logger.info(logState)
                lastLoggedState = logState
            }
        }
        captureSession?.start()
        if let compatibility = captureSession?.diagnostics().compatibility {
            let issues = compatibility.checks
                .filter { $0.status != .passed }
                .map { "\($0.name)=\($0.status.rawValue)" }
                .joined(separator: ",")
            logger.info(
                "compatibility status=\(compatibility.overallStatus.rawValue) issues=\(issues.isEmpty ? "none" : issues)"
            )
        }
        logger.info("Glidex menu bar app ready")
    }

    func applicationWillTerminate(_ notification: Notification) {
        captureSession?.shutdown()
    }

    private func configureCommands() {
        statusItemController.onSetEnabled = { [weak state] enabled in
            state?.setEnabled(enabled)
        }
        statusItemController.onSetMode = { [weak state] mode in
            state?.setInputMode(mode)
        }
        statusItemController.onSetBorderVisibility = { [weak state] visibility in
            state?.setBorderVisibility(visibility)
        }
        statusItemController.onSetShowsAnchorIndicator = { [weak state] shows in
            state?.setShowsAnchorIndicator(shows)
        }
        statusItemController.onSetShowsActiveTouches = { [weak state] shows in
            state?.setShowsActiveTouches(shows)
        }
        statusItemController.onSetRequiresPointerOverSimulator = { [weak state] requires in
            state?.setRequiresPointerOverSimulator(requires)
        }
        statusItemController.onSetAnchorLocked = { [weak state] locked in
            state?.setAnchorLocked(locked)
        }
        statusItemController.onFollowFocusedSimulator = { [weak self] in
            self?.captureSession?.followFocusedSimulator()
        }
        statusItemController.onPinCurrentSimulator = { [weak self] in
            self?.captureSession?.pinCurrentSimulator()
        }
        statusItemController.onSelectSimulator = { [weak self] udid in
            self?.captureSession?.selectSimulator(udid: udid)
        }
        statusItemController.onReattach = { [weak self] in
            self?.captureSession?.reattach()
        }
        captureSession?.onAutomationStateChange = { [weak statusItemController] automationState in
            statusItemController?.setAutomationState(automationState)
        }
        captureSession?.onAvailableSimulatorsChange = { [weak statusItemController] simulators in
            statusItemController?.setAvailableSimulators(simulators)
        }
        if let captureSession {
            statusItemController.setAutomationState(captureSession.automationState)
        }
        statusItemController.onStartRecording = { [weak self] in
            self?.performAutomationCommand { try self?.captureSession?.startRecording() }
        }
        statusItemController.onStopRecording = { [weak self] in
            self?.performAutomationCommand { _ = try self?.captureSession?.stopRecording() }
        }
        statusItemController.onReplayLatestRecording = { [weak self] in
            self?.performAutomationCommand { try self?.captureSession?.replayLatestRecording() }
        }
        statusItemController.onChooseRecording = { [weak self] in
            self?.chooseRecordingForReplay()
        }
        statusItemController.onManageRecordings = { [weak self] in
            self?.recordingLibraryWindowController.show()
        }
        statusItemController.onStopReplay = { [weak self] in
            self?.captureSession?.stopReplay()
        }
        statusItemController.onDiagnostics = { [weak self] in
            guard let self else { return }
            diagnosticsWindowController.show(
                report: diagnosticsReport,
                calibrationEnabled: state.snapshot.isCalibrationMode
            )
        }
        diagnosticsWindowController.onRefresh = { [weak self] in
            self?.diagnosticsReport ?? L10n.text("Diagnostics unavailable")
        }
        diagnosticsWindowController.onReconnect = { [weak self] in
            self?.captureSession?.reattach()
        }
        diagnosticsWindowController.onSetCalibrationMode = { [weak state] enabled in
            state?.setCalibrationMode(enabled)
        }
        diagnosticsWindowController.onExport = { [weak self] in
            self?.exportDiagnostics()
        }
        recordingLibraryWindowController.onLoad = { [weak self] in
            try self?.captureSession?.recordings() ?? []
        }
        recordingLibraryWindowController.onReplay = { [weak self] stored, rate, loops in
            try self?.captureSession?.replayRecording(stored, playbackRate: rate, loops: loops)
        }
        recordingLibraryWindowController.onRename = { [weak self] stored, name in
            guard let session = self?.captureSession else { return stored }
            return try session.renameRecording(stored, to: name)
        }
        recordingLibraryWindowController.onDelete = { [weak self] stored in
            try self?.captureSession?.deleteRecording(stored)
        }
        recordingLibraryWindowController.onImport = { [weak self] url in
            guard let session = self?.captureSession else {
                throw CaptureAutomationError.simulatorUnavailable
            }
            return try session.importRecording(from: url)
        }
        recordingLibraryWindowController.onExport = { [weak self] stored, url in
            try self?.captureSession?.exportRecording(stored, to: url)
        }
        statusItemController.onAbout = {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(options: [
                .applicationName: "Glidex",
                .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development",
                .version: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "SwiftPM",
                .credits: NSAttributedString(string: "\(L10n.text("Trackpad control for iOS Simulator"))\nhttps://github.com/jhao941/Glidex"),
            ])
        }
        statusItemController.onQuit = { [weak self] in
            self?.captureSession?.shutdown()
            NSApp.terminate(nil)
        }
    }

    private var diagnosticsReport: String {
        let snapshot = state.snapshot
        let recovery: String?
        if case let .error(error) = snapshot.status {
            recovery = recoveryMessage(for: error)
        } else {
            recovery = nil
        }
        return currentDiagnostics.report(recovery: recovery)
    }

    private var currentDiagnostics: CaptureDiagnostics {
        let snapshot = state.snapshot
        let compatibility = CompatibilitySelfCheck.run(
            hostBundleURL: nil,
            hostDetected: false,
            bootedSimulatorCount: 0,
            rawTouchStreamRunning: false,
            hidTargetReady: false
        )
        return captureSession?.diagnostics() ?? CaptureDiagnostics(
            snapshot: snapshot,
            rawTouchStreamRunning: false,
            windowTrackingRunning: false,
            hostDescriptor: nil,
            overlayFrame: overlayWindowController.frame,
            overlayVisible: overlayWindowController.isVisible,
            compatibility: compatibility
        )
    }

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.title = L10n.text("Export Diagnostics")
        panel.prompt = L10n.text("Export")
        panel.nameFieldStringValue = "Glidex-Diagnostics.zip"
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let diagnostics = currentDiagnostics
        do {
            try DiagnosticsExporter.export(
                report: diagnosticsReport,
                compatibility: diagnostics.compatibility,
                recentLogs: logger.recentEntries(),
                to: url
            )
        } catch {
            logger.error("diagnostics export failed: \(error)")
            NSAlert(error: error).runModal()
        }
    }

    private func recoveryMessage(for error: GlidexRuntimeError) -> String {
        switch error {
        case .accessibilityPermission:
            L10n.text("Allow Glidex under System Settings > Privacy & Security > Accessibility, then choose Reconnect to Simulator.")
        case .simulatorNotRunning:
            L10n.text("Boot and show one Simulator device, then choose Reconnect to Simulator.")
        case .ambiguousTarget:
            L10n.text("Leave one Simulator window visible or close unrelated Simulator windows, then choose Reconnect to Simulator.")
        case .multitouchUnavailable:
            L10n.text("Reconnect the trackpad or restart Glidex. Diagnostics remain available from the CLI.")
        case .hidInitialization:
            L10n.text("Restart Simulator and Glidex. If the issue persists, run glidex probe from Terminal.")
        case .other:
            L10n.text("Choose Reconnect to Simulator. If the issue persists, run glidex probe from Terminal.")
        }
    }

    private func optionAnchorLogValue(_ availability: OptionAnchorAvailability) -> String {
        switch availability {
        case .inactive:
            "inactive"
        case .outsideSimulator:
            "outside"
        case let .available(point):
            "available(\(Int(point.x)),\(Int(point.y)))"
        }
    }

    private func performAutomationCommand(_ command: () throws -> Void) {
        do {
            try command()
        } catch {
            logger.error("automation command failed: \(error)")
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = L10n.text("Glidex Automation")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private func chooseRecordingForReplay() {
        guard let captureSession else { return }
        let directoryURL: URL
        do {
            directoryURL = try captureSession.prepareRecordingsDirectory()
        } catch {
            performAutomationCommand { throw error }
            return
        }
        let panel = NSOpenPanel()
        panel.title = L10n.text("Replay Gesture Recording")
        panel.prompt = L10n.text("Replay")
        panel.message = L10n.text("Choose a Glidex gesture recording.")
        panel.directoryURL = directoryURL
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        performAutomationCommand {
            try captureSession.replayRecording(at: url)
        }
    }
}
