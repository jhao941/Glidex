import AppKit

@MainActor
final class DiagnosticsWindowController: NSWindowController {
    var onRefresh: (() -> String)?
    var onReconnect: (() -> Void)?
    var onSetCalibrationMode: ((Bool) -> Void)?
    var onExport: (() -> Void)?

    private let scrollView: NSScrollView
    private let textView: NSTextView
    private let calibrationButton = NSButton(
        checkboxWithTitle: L10n.text("Calibration Mode"),
        target: nil,
        action: nil
    )

    init() {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            preconditionFailure("AppKit did not create a text view for Diagnostics")
        }
        self.scrollView = scrollView
        self.textView = textView

        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 620, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("Glidex Diagnostics")
        window.minSize = CGSize(width: 500, height: 380)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        configureContent()
    }

    required init?(coder: NSCoder) { nil }

    func show(report: String, calibrationEnabled: Bool) {
        textView.string = report
        calibrationButton.state = calibrationEnabled ? .on : .off
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func configureContent() {
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = CGSize(width: 12, height: 12)

        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        let copyButton = NSButton(title: L10n.text("Copy Diagnostics"), target: self, action: #selector(copyDiagnostics(_:)))
        let refreshButton = NSButton(title: L10n.text("Refresh"), target: self, action: #selector(refresh(_:)))
        let reconnectButton = NSButton(title: L10n.text("Reconnect"), target: self, action: #selector(reconnect(_:)))
        let exportButton = NSButton(title: L10n.text("Export…"), target: self, action: #selector(exportDiagnostics(_:)))
        calibrationButton.target = self
        calibrationButton.action = #selector(toggleCalibration(_:))
        let closeButton = NSButton(title: L10n.text("Close"), target: self, action: #selector(closeWindow(_:)))
        closeButton.keyEquivalent = "\r"

        let buttons = NSStackView(views: [copyButton, refreshButton, reconnectButton, exportButton, calibrationButton, closeButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        buttons.spacing = 8

        let stack = NSStackView(views: [scrollView, buttons])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        window?.contentView = NSView()
        window?.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window!.contentView!.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: window!.contentView!.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: window!.contentView!.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: window!.contentView!.bottomAnchor, constant: -16),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 300),
        ])
    }

    @objc private func copyDiagnostics(_ sender: Any?) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textView.string, forType: .string)
    }

    @objc private func refresh(_ sender: Any?) {
        if let report = onRefresh?() { textView.string = report }
    }

    @objc private func reconnect(_ sender: Any?) { onReconnect?() }
    @objc private func exportDiagnostics(_ sender: Any?) { onExport?() }

    @objc private func toggleCalibration(_ sender: NSButton) {
        onSetCalibrationMode?(sender.state == .on)
    }

    @objc private func closeWindow(_ sender: Any?) { close() }
}
