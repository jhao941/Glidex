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
    var onSetCalibrationMode: ((Bool) -> Void)?
    var onReattach: (() -> Void)?
    var onDiagnostics: (() -> Void)?
    var onSettings: (() -> Void)?
    var onQuit: (() -> Void)?

    private let state: GlidexAppState
    private let statusItem: NSStatusItem
    private var stateObserver: UUID?

    init(state: GlidexAppState) {
        self.state = state
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        stateObserver = state.observe { [weak self] snapshot in
            self?.render(snapshot)
        }
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
        menu.addItem(labelItem("Status: \(statusText(snapshot.status))"))
        menu.addItem(labelItem("Simulator: \(snapshot.target?.name ?? "None")"))
        menu.addItem(labelItem("Option Anchor: \(presentation.optionAnchorText)"))
        menu.addItem(.separator())

        menu.addItem(actionItem(
            "Enabled",
            action: #selector(toggleEnabled(_:)),
            state: snapshot.preferences.isEnabled
        ))
        menu.addItem(submenuItem(
            title: "Mode",
            values: [CaptureInputMode.navigate, .point, .edge],
            selected: snapshot.preferences.inputMode,
            selector: #selector(selectMode(_:))
        ))
        if snapshot.preferences.inputMode == .point || snapshot.preferences.inputMode == .edge {
            menu.addItem(actionItem(
                snapshot.anchorLockState == .locked ? "Edit Anchor Position" : "Lock Anchor",
                action: #selector(toggleAnchorLock(_:))
            ))
        }
        menu.addItem(submenuItem(
            title: "Border Visibility",
            values: BorderVisibility.allCases,
            selected: snapshot.preferences.borderVisibility,
            selector: #selector(selectBorderVisibility(_:))
        ))
        menu.addItem(actionItem(
            "Show Anchor Indicator",
            action: #selector(toggleAnchorIndicator(_:)),
            state: snapshot.preferences.showsAnchorIndicator
        ))
        menu.addItem(actionItem(
            "Show Active Touches",
            action: #selector(toggleActiveTouches(_:)),
            state: snapshot.preferences.showsActiveTouches
        ))
        menu.addItem(actionItem(
            "Require Pointer Over Simulator",
            action: #selector(toggleRequiresPointerOverSimulator(_:)),
            state: snapshot.preferences.requiresPointerOverSimulator
        ))
        menu.addItem(.separator())
        menu.addItem(actionItem("Reattach to Simulator", action: #selector(reattach(_:))))
        menu.addItem(actionItem(
            "Calibration Mode",
            action: #selector(toggleCalibration(_:)),
            state: snapshot.isCalibrationMode
        ))
        menu.addItem(actionItem("Diagnostics…", action: #selector(showDiagnostics(_:))))
        menu.addItem(actionItem("Settings…", action: #selector(showSettings(_:))))
        menu.addItem(.separator())
        menu.addItem(actionItem("Quit Glidex", action: #selector(quit(_:))))
        statusItem.menu = menu
    }

    private func statusText(_ status: GlidexRuntimeStatus) -> String {
        switch status {
        case let .waiting(reason): "Waiting — \(reason)"
        case .connecting: "Connecting"
        case .active: "Active"
        case .paused: "Paused"
        case let .error(error): "Error — \(error.message)"
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
        state: Bool? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let state {
            item.state = state ? .on : .off
        }
        return item
    }

    private func submenuItem<Value: RawRepresentable & Equatable>(
        title: String,
        values: [Value],
        selected: Value,
        selector: Selector
    ) -> NSMenuItem where Value.RawValue == String {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for value in values {
            let item = NSMenuItem(
                title: value.rawValue.capitalized,
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

    @objc private func toggleCalibration(_ sender: NSMenuItem) {
        onSetCalibrationMode?(sender.state != .on)
    }

    @objc private func reattach(_ sender: NSMenuItem) { onReattach?() }
    @objc private func showDiagnostics(_ sender: NSMenuItem) { onDiagnostics?() }
    @objc private func showSettings(_ sender: NSMenuItem) { onSettings?() }
    @objc private func quit(_ sender: NSMenuItem) { onQuit?() }
}
