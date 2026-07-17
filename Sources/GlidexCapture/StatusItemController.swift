import AppKit
import GlidexCore

@MainActor
final class StatusItemController: NSObject {
    var onSetEnabled: ((Bool) -> Void)?
    var onSetMode: ((CaptureInputMode) -> Void)?
    var onSetBorderVisibility: ((BorderVisibility) -> Void)?
    var onSetShowsAnchorIndicator: ((Bool) -> Void)?
    var onSetShowsActiveTouches: ((Bool) -> Void)?
    var onSetRequiresPointerOverSimulator: ((Bool) -> Void)?
    var onSetAnchorLocked: ((Bool) -> Void)?
    var onFollowFocusedSimulator: (() -> Void)?
    var onPinCurrentSimulator: (() -> Void)?
    var onSelectSimulator: ((String) -> Void)?
    var onReattach: (() -> Void)?
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onReplayLatestRecording: (() -> Void)?
    var onChooseRecording: (() -> Void)?
    var onManageRecordings: (() -> Void)?
    var onStopReplay: (() -> Void)?
    var onDiagnostics: (() -> Void)?
    var onAbout: (() -> Void)?
    var onQuit: (() -> Void)?

    private let state: GlidexAppState
    private let statusItem: NSStatusItem
    private var stateObserver: UUID?
    private var automationState: CaptureAutomationState = .idle(hasRecording: false)
    private var availableSimulators: [BootedSimulatorRecord] = []

    init(state: GlidexAppState) {
        self.state = state
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        stateObserver = state.observe { [weak self] snapshot in
            self?.render(snapshot)
        }
    }

    func setAutomationState(_ automationState: CaptureAutomationState) {
        guard self.automationState != automationState else { return }
        self.automationState = automationState
        render(state.snapshot)
    }

    func setAvailableSimulators(_ simulators: [BootedSimulatorRecord]) {
        guard availableSimulators != simulators else { return }
        availableSimulators = simulators
        render(state.snapshot)
    }

    deinit {
        if let stateObserver {
            MainActor.assumeIsolated {
                state.removeObserver(stateObserver)
            }
        }
    }

    private func render(_ snapshot: GlidexAppSnapshot) {
        let presentation = StatusItemPresentation(snapshot: snapshot)
        let image = NSImage(
            systemSymbolName: presentation.symbolName,
            accessibilityDescription: "Glidex \(snapshot.status.title)"
        )
        image?.isTemplate = presentation.usesTemplateImage
        statusItem.button?.image = image
        statusItem.button?.contentTintColor = nil
        statusItem.button?.toolTip = "Glidex: \(snapshot.status.title)"

        let menu = NSMenu()
        menu.addItem(labelItem(L10n.text("Status: %@", statusText(snapshot.status))))
        menu.addItem(labelItem(L10n.text("Device: %@", snapshot.target?.name ?? L10n.text("None"))))
        menu.addItem(labelItem(L10n.text("Mode: %@", modeTitle(snapshot.preferences.inputMode))))
        if presentation.showsOptionAnchorStatus {
            menu.addItem(labelItem(L10n.text("Option Anchor: %@", L10n.text(presentation.optionAnchorText))))
        }
        menu.addItem(.separator())

        menu.addItem(actionItem(
            L10n.text("Enabled"),
            action: #selector(toggleEnabled(_:)),
            state: snapshot.preferences.isEnabled
        ))
        menu.addItem(submenuItem(
            title: L10n.text("Mode"),
            values: [CaptureInputMode.navigate, .directTouch, .point, .edge],
            selected: snapshot.preferences.inputMode,
            selector: #selector(selectMode(_:)),
            itemTitle: { value in
                value == .directTouch ? "\(L10n.text("Direct Touch"))  ⌃⌥D" : modeTitle(value)
            }
        ))
        menu.addItem(targetMenu(snapshot))
        menu.addItem(appearanceMenu(snapshot))
        menu.addItem(inputMenu(snapshot))
        menu.addItem(automationMenu(snapshot))
        menu.addItem(.separator())
        menu.addItem(actionItem(L10n.text("Reconnect to Simulator"), action: #selector(reattach(_:))))
        menu.addItem(actionItem(L10n.text("Diagnostics…"), action: #selector(showDiagnostics(_:))))
        menu.addItem(.separator())
        menu.addItem(actionItem(L10n.text("About Glidex"), action: #selector(showAbout(_:))))
        menu.addItem(actionItem(L10n.text("Quit Glidex"), action: #selector(quit(_:))))
        statusItem.menu = menu
    }

    private func appearanceMenu(_ snapshot: GlidexAppSnapshot) -> NSMenuItem {
        let parent = NSMenuItem(title: L10n.text("Appearance"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(submenuItem(
            title: L10n.text("Border Visibility"),
            values: BorderVisibility.allCases,
            selected: snapshot.preferences.borderVisibility,
            selector: #selector(selectBorderVisibility(_:)),
            itemTitle: { L10n.text($0.rawValue.capitalized) }
        ))
        submenu.addItem(actionItem(
            L10n.text("Show Anchor Indicator"),
            action: #selector(toggleAnchorIndicator(_:)),
            state: snapshot.preferences.showsAnchorIndicator
        ))
        submenu.addItem(actionItem(
            L10n.text("Show Active Touches"),
            action: #selector(toggleActiveTouches(_:)),
            state: snapshot.preferences.showsActiveTouches
        ))
        parent.submenu = submenu
        return parent
    }

    private func targetMenu(_ snapshot: GlidexAppSnapshot) -> NSMenuItem {
        let parent = NSMenuItem(title: L10n.text("Simulator Target"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(actionItem(
            L10n.text("Follow App Focus"),
            action: #selector(followFocusedSimulator(_:)),
            state: snapshot.preferences.simulatorTargetingMode == .followFocus
        ))
        submenu.addItem(actionItem(
            L10n.text("Pin Current Device"),
            action: #selector(pinCurrentSimulator(_:)),
            state: snapshot.preferences.simulatorTargetingMode == .pinned &&
                snapshot.preferences.pinnedSimulatorUDID == snapshot.target?.udid,
            isEnabled: snapshot.target != nil
        ))
        submenu.addItem(.separator())
        if availableSimulators.isEmpty {
            submenu.addItem(labelItem(L10n.text("No Booted Simulators")))
        } else {
            for simulator in availableSimulators {
                let item = actionItem(
                    "\(simulator.name) — \(simulator.runtime) — \(simulator.udid.suffix(4))",
                    action: #selector(selectSimulator(_:)),
                    state: snapshot.preferences.simulatorTargetingMode == .pinned &&
                        snapshot.preferences.pinnedSimulatorUDID?.caseInsensitiveCompare(simulator.udid) == .orderedSame
                )
                item.representedObject = simulator.udid
                submenu.addItem(item)
            }
        }
        parent.submenu = submenu
        return parent
    }

    private func inputMenu(_ snapshot: GlidexAppSnapshot) -> NSMenuItem {
        let parent = NSMenuItem(title: L10n.text("Input"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.addItem(actionItem(
            L10n.text("Constrain Input to Simulator"),
            action: #selector(toggleRequiresPointerOverSimulator(_:)),
            state: snapshot.preferences.requiresPointerOverSimulator
        ))
        if snapshot.preferences.inputMode == .point || snapshot.preferences.inputMode == .edge {
            submenu.addItem(actionItem(
                snapshot.anchorLockState == .locked ? L10n.text("Edit Anchor Position") : L10n.text("Lock Anchor"),
                action: #selector(toggleAnchorLock(_:))
            ))
        }
        parent.submenu = submenu
        return parent
    }

    private func automationMenu(_ snapshot: GlidexAppSnapshot) -> NSMenuItem {
        let parent = NSMenuItem(title: L10n.text("Automation"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let available = snapshot.preferences.isEnabled && snapshot.status == .active
        switch automationState {
        case let .idle(hasRecording):
            submenu.addItem(actionItem(
                L10n.text("Start Recording"),
                action: #selector(startRecording(_:)),
                isEnabled: available
            ))
            submenu.addItem(actionItem(
                L10n.text("Replay Last Recording"),
                action: #selector(replayLatestRecording(_:)),
                isEnabled: available && hasRecording
            ))
            submenu.addItem(actionItem(
                L10n.text("Replay Recording…"),
                action: #selector(chooseRecording(_:)),
                isEnabled: available
            ))
            submenu.addItem(actionItem(
                L10n.text("Manage Recordings…"),
                action: #selector(manageRecordings(_:))
            ))
        case .recording:
            submenu.addItem(labelItem(L10n.text("Recording…")))
            submenu.addItem(actionItem(L10n.text("Stop and Save Recording"), action: #selector(stopRecording(_:))))
        case let .replaying(name):
            submenu.addItem(labelItem(L10n.text("Replaying: %@", name)))
            submenu.addItem(actionItem(L10n.text("Stop Replay"), action: #selector(stopReplay(_:))))
        }
        parent.submenu = submenu
        return parent
    }

    private func statusText(_ status: GlidexRuntimeStatus) -> String {
        switch status {
        case let .waiting(reason): L10n.text("Waiting — %@", L10n.text(reason))
        case .connecting: L10n.text("Connecting")
        case .active: L10n.text("Active")
        case .paused: L10n.text("Paused")
        case let .error(error): L10n.text("Error — %@", errorText(error))
        }
    }

    private func errorText(_ error: GlidexRuntimeError) -> String {
        switch error {
        case .accessibilityPermission:
            L10n.text("Accessibility permission is required")
        case .simulatorNotRunning:
            L10n.text("Simulator is not running")
        case .ambiguousTarget:
            L10n.text("Multiple Simulator targets could not be matched")
        case let .multitouchUnavailable(detail):
            L10n.text("MultitouchSupport unavailable: %@", detail)
        case let .hidInitialization(detail):
            L10n.text("HID backend failed: %@", detail)
        case let .other(detail):
            detail
        }
    }

    private func modeTitle(_ mode: CaptureInputMode) -> String {
        switch mode {
        case .disabled: L10n.text("Disabled")
        case .navigate: L10n.text("Navigate")
        case .directTouch: L10n.text("Direct Touch")
        case .point: L10n.text("Point")
        case .edge: L10n.text("Edge")
        }
    }

    private func labelItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(
        _ title: String,
        action: Selector,
        state: Bool? = nil,
        isEnabled: Bool = true
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = isEnabled
        if let state {
            item.state = state ? .on : .off
        }
        return item
    }

    private func submenuItem<Value: RawRepresentable & Equatable>(
        title: String,
        values: [Value],
        selected: Value,
        selector: Selector,
        itemTitle: (Value) -> String = { $0.rawValue.capitalized }
    ) -> NSMenuItem where Value.RawValue == String {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for value in values {
            let item = NSMenuItem(
                title: itemTitle(value),
                action: selector,
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = value.rawValue
            item.state = value == selected ? .on : .off
            submenu.addItem(item)
        }
        parent.submenu = submenu
        return parent
    }

    @objc private func toggleEnabled(_ sender: NSMenuItem) {
        onSetEnabled?(sender.state != .on)
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = CaptureInputMode(rawValue: raw) else { return }
        onSetMode?(mode)
    }

    @objc private func selectBorderVisibility(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let visibility = BorderVisibility(rawValue: raw) else { return }
        onSetBorderVisibility?(visibility)
    }

    @objc private func toggleAnchorIndicator(_ sender: NSMenuItem) {
        onSetShowsAnchorIndicator?(sender.state != .on)
    }

    @objc private func toggleActiveTouches(_ sender: NSMenuItem) {
        onSetShowsActiveTouches?(sender.state != .on)
    }

    @objc private func toggleRequiresPointerOverSimulator(_ sender: NSMenuItem) {
        onSetRequiresPointerOverSimulator?(sender.state != .on)
    }

    @objc private func toggleAnchorLock(_ sender: NSMenuItem) {
        onSetAnchorLocked?(state.snapshot.anchorLockState != .locked)
    }

    @objc private func followFocusedSimulator(_ sender: NSMenuItem) { onFollowFocusedSimulator?() }
    @objc private func pinCurrentSimulator(_ sender: NSMenuItem) { onPinCurrentSimulator?() }
    @objc private func selectSimulator(_ sender: NSMenuItem) {
        guard let udid = sender.representedObject as? String else { return }
        onSelectSimulator?(udid)
    }

    @objc private func reattach(_ sender: NSMenuItem) { onReattach?() }
    @objc private func startRecording(_ sender: NSMenuItem) { onStartRecording?() }
    @objc private func stopRecording(_ sender: NSMenuItem) { onStopRecording?() }
    @objc private func replayLatestRecording(_ sender: NSMenuItem) { onReplayLatestRecording?() }
    @objc private func chooseRecording(_ sender: NSMenuItem) { onChooseRecording?() }
    @objc private func manageRecordings(_ sender: NSMenuItem) { onManageRecordings?() }
    @objc private func stopReplay(_ sender: NSMenuItem) { onStopReplay?() }
    @objc private func showDiagnostics(_ sender: NSMenuItem) { onDiagnostics?() }
    @objc private func showAbout(_ sender: NSMenuItem) { onAbout?() }
    @objc private func quit(_ sender: NSMenuItem) { onQuit?() }
}
