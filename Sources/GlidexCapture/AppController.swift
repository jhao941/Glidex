import AppKit
import GlidexCore

@MainActor
final class AppController {
    private let logger: Logger
    private let preferences: GlidexPreferences
    private let state: GlidexAppState
    private let statusItemController: StatusItemController
    private var stateObserver: UUID?

    init(logger: Logger) {
        self.logger = logger
        self.preferences = GlidexPreferences()
        self.state = GlidexAppState(snapshot: GlidexAppSnapshot(
            preferences: preferences.load()
        ))
        self.statusItemController = StatusItemController(state: state)
        configureCommands()
    }

    func start() {
        stateObserver = state.observe { [weak self] snapshot in
            self?.preferences.save(snapshot.preferences)
        }
        logger.info("Glidex menu bar app ready")
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
        statusItemController.onSetShowsTouchIndicator = { [weak state] shows in
            state?.setShowsTouchIndicator(shows)
        }
        statusItemController.onSetCalibrationMode = { [weak state] enabled in
            state?.setCalibrationMode(enabled)
        }
        statusItemController.onReattach = { [weak state] in
            state?.transition(to: .waiting("Reattaching to Simulator"))
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
        statusItemController.onQuit = {
            NSApp.terminate(nil)
        }
    }

    private var diagnosticsMessage: String {
        let snapshot = state.snapshot
        let target = snapshot.target.map { "\($0.name) [\($0.udid)]" } ?? "None"
        let detail: String
        switch snapshot.status {
        case let .waiting(reason): detail = reason
        case let .error(error): detail = error.message
        default: detail = snapshot.status.title
        }
        return "Status: \(detail)\nTarget: \(target)\nMode: \(snapshot.preferences.inputMode.rawValue)"
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
