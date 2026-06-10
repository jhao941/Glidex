import AppKit
import GlidexCore

@MainActor
final class StatusItemController: NSObject {
    var onSetEnabled: ((Bool) -> Void)?
    var onSetMode: ((CaptureInputMode) -> Void)?
    var onSetBorderVisibility: ((BorderVisibility) -> Void)?
    var onSetShowsTouchIndicator: ((Bool) -> Void)?
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
        statusItem.button?.image = NSImage(
            systemSymbolName: presentation.symbolName,
            accessibilityDescription: "Glidex \(snapshot.status.title)"
        )
        statusItem.button?.contentTintColor = statusColor(for: snapshot.status)
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
        menu.addItem(submenuItem(
            title: "Border Visibility",
            values: BorderVisibility.allCases,
            selected: snapshot.preferences.borderVisibility,
            selector: #selector(selectBorderVisibility(_:))
        ))
        menu.addItem(actionItem(
            "Show Touch Indicator",
            action: #selector(toggleTouchIndicator(_:)),
            state: snapshot.preferences.showsTouchIndicator
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

    private func statusColor(for status: GlidexRuntimeStatus) -> NSColor {
        switch status {
        case .active: .systemGreen
        case .waiting, .connecting: .systemYellow
        case .error: .systemRed
        case .paused: .secondaryLabelColor
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

    @objc private func toggleTouchIndicator(_ sender: NSMenuItem) {
        onSetShowsTouchIndicator?(sender.state != .on)
    }

    @objc private func toggleCalibration(_ sender: NSMenuItem) {
        onSetCalibrationMode?(sender.state != .on)
    }

    @objc private func reattach(_ sender: NSMenuItem) { onReattach?() }
    @objc private func showDiagnostics(_ sender: NSMenuItem) { onDiagnostics?() }
    @objc private func showSettings(_ sender: NSMenuItem) { onSettings?() }
    @objc private func quit(_ sender: NSMenuItem) { onQuit?() }
}
