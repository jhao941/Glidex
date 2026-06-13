import AppKit
import GlidexCore

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private let logger: Logger
    private let preferences: GlidexPreferences
    private let state: GlidexAppState
    private let statusItemController: StatusItemController
    private let overlayWindowController: OverlayWindowController
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
            let logState = "app status=\(snapshot.status.title) enabled=\(snapshot.preferences.isEnabled) mode=\(snapshot.preferences.inputMode.rawValue) requirePointer=\(snapshot.preferences.requiresPointerOverSimulator) anchorLock=\(snapshot.anchorLockState.rawValue) anchorIndicator=\(snapshot.preferences.showsAnchorIndicator) activeTouchIndicator=\(snapshot.preferences.showsActiveTouches) activeTouches=\(snapshot.activeTouches.count) optionAnchor=\(optionAnchorLogValue(snapshot.optionAnchorAvailability)) target=\(snapshot.target?.udid ?? "none")"
            if lastLoggedState != logState {
                logger.info(logState)
                lastLoggedState = logState
            }
        }
        captureSession?.start()
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
        statusItemController.onSetCalibrationMode = { [weak state] enabled in
            state?.setCalibrationMode(enabled)
        }
        statusItemController.onReattach = { [weak self] in
            self?.captureSession?.reattach()
        }
        statusItemController.onDiagnostics = { [weak self] in
            self?.showInformation(
                title: "Glidex Diagnostics",
                message: self?.diagnosticsMessage ?? "No diagnostics available"
            )
        }
        statusItemController.onSettings = { [weak self] in
            self?.showInformation(
                title: "Glidex Settings",
                message: "Use the menu bar controls to configure input mode, border visibility, and touch indicators."
            )
        }
        statusItemController.onQuit = { [weak self] in
            self?.captureSession?.shutdown()
            NSApp.terminate(nil)
        }
    }

    private var diagnosticsMessage: String {
        let snapshot = state.snapshot
        let target = snapshot.target.map { "\($0.name) [\($0.udid)]" } ?? "None"
        let detail: String
        switch snapshot.status {
        case let .waiting(reason): detail = reason
        case let .error(error): detail = "\(error.message)\n\(recoveryMessage(for: error))"
        default: detail = snapshot.status.title
        }
        return "Status: \(detail)\nTarget: \(target)\nMode: \(snapshot.preferences.inputMode.rawValue)"
    }

    private func recoveryMessage(for error: GlidexRuntimeError) -> String {
        switch error {
        case .accessibilityPermission:
            "Allow Glidex under System Settings > Privacy & Security > Accessibility, then choose Reattach to Simulator."
        case .simulatorNotRunning:
            "Boot and show one Simulator device, then choose Reattach to Simulator."
        case .ambiguousTarget:
            "Leave one Simulator window visible or close unrelated Simulator windows, then reattach."
        case .multitouchUnavailable:
            "Reconnect the trackpad or restart Glidex. Diagnostics remain available from the CLI."
        case .hidInitialization:
            "Restart Simulator and Glidex. If the issue persists, run glidex probe from Terminal."
        case .other:
            "Choose Reattach to Simulator. If the issue persists, run glidex probe from Terminal."
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

    private func showInformation(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
