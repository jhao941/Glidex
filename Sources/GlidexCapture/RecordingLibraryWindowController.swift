import AppKit
import GlidexCore
import UniformTypeIdentifiers

@MainActor
final class RecordingLibraryWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    var onLoad: (() throws -> [StoredGestureRecording])?
    var onReplay: ((StoredGestureRecording, Double, Bool) throws -> Void)?
    var onRename: ((StoredGestureRecording, String) throws -> StoredGestureRecording)?
    var onDelete: ((StoredGestureRecording) throws -> Void)?
    var onImport: ((URL) throws -> StoredGestureRecording)?
    var onExport: ((StoredGestureRecording, URL) throws -> Void)?

    private let tableView = NSTableView()
    private let emptyLabel = NSTextField(labelWithString: L10n.text("No saved recordings."))
    private let replayButton = NSButton(title: L10n.text("Replay"), target: nil, action: nil)
    private let renameButton = NSButton(title: L10n.text("Rename…"), target: nil, action: nil)
    private let deleteButton = NSButton(title: L10n.text("Delete"), target: nil, action: nil)
    private let exportButton = NSButton(title: L10n.text("Export…"), target: nil, action: nil)
    private let ratePopup = NSPopUpButton()
    private let loopButton = NSButton(checkboxWithTitle: L10n.text("Loop"), target: nil, action: nil)
    private var recordings: [StoredGestureRecording] = []

    init() {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 760, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = L10n.text("Recording Library")
        window.minSize = CGSize(width: 620, height: 360)
        window.isReleasedWhenClosed = false
        super.init(window: window)
        configureContent()
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        reload()
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { recordings.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard recordings.indices.contains(row), let identifier = tableColumn?.identifier else { return nil }
        let stored = recordings[row]
        let value: String
        switch identifier.rawValue {
        case "name": value = stored.recording.name
        case "date": value = Self.dateFormatter.string(from: stored.recording.recordedAt)
        case "duration": value = Self.durationFormatter.string(from: stored.recording.duration) ?? "0:00"
        case "events": value = String(stored.recording.events.count)
        case "contacts": value = String(stored.recording.maximumContactCount)
        default: value = ""
        }
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            ?? makeCell(identifier: identifier)
        cell.textField?.stringValue = value
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateControls()
    }

    private func configureContent() {
        let columns: [(String, String, CGFloat)] = [
            ("name", L10n.text("Name"), 250),
            ("date", L10n.text("Recorded"), 170),
            ("duration", L10n.text("Duration"), 80),
            ("events", L10n.text("Events"), 70),
            ("contacts", L10n.text("Touches"), 70),
        ]
        for (identifier, title, width) in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            column.minWidth = min(60, width)
            tableView.addTableColumn(column)
        }
        tableView.delegate = self
        tableView.dataSource = self
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = false
        tableView.doubleAction = #selector(replay(_:))
        tableView.target = self

        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder

        emptyLabel.alignment = .center
        emptyLabel.textColor = .secondaryLabelColor

        replayButton.target = self
        replayButton.action = #selector(replay(_:))
        renameButton.target = self
        renameButton.action = #selector(rename(_:))
        deleteButton.target = self
        deleteButton.action = #selector(delete(_:))
        exportButton.target = self
        exportButton.action = #selector(export(_:))
        let importButton = NSButton(title: L10n.text("Import…"), target: self, action: #selector(importRecording(_:)))
        let refreshButton = NSButton(title: L10n.text("Refresh"), target: self, action: #selector(refresh(_:)))
        let closeButton = NSButton(title: L10n.text("Close"), target: self, action: #selector(closeWindow(_:)))

        ratePopup.addItems(withTitles: ["0.5×", "1×", "1.5×", "2×"])
        ratePopup.selectItem(withTitle: "1×")
        let speedLabel = NSTextField(labelWithString: L10n.text("Speed:"))

        let actions = NSStackView(views: [replayButton, renameButton, deleteButton, importButton, exportButton])
        actions.orientation = .horizontal
        actions.spacing = 8
        let options = NSStackView(views: [speedLabel, ratePopup, loopButton, refreshButton, closeButton])
        options.orientation = .horizontal
        options.spacing = 8
        let spacer = NSView()
        let controls = NSStackView(views: [actions, spacer, options])
        controls.orientation = .horizontal
        controls.alignment = .centerY
        controls.spacing = 8
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let tableContainer = NSView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        tableContainer.addSubview(scrollView)
        tableContainer.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: tableContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: tableContainer.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: tableContainer.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: tableContainer.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: tableContainer.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: tableContainer.centerYAnchor),
        ])

        let stack = NSStackView(views: [tableContainer, controls])
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
            tableContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
        ])
        updateControls()
    }

    private func makeCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let label = NSTextField(labelWithString: "")
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.textField = label
        cell.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    private var selectedRecording: StoredGestureRecording? {
        let row = tableView.selectedRow
        return recordings.indices.contains(row) ? recordings[row] : nil
    }

    private var playbackRate: Double {
        switch ratePopup.indexOfSelectedItem {
        case 0: 0.5
        case 2: 1.5
        case 3: 2
        default: 1
        }
    }

    private func reload(selecting url: URL? = nil) {
        do {
            recordings = try onLoad?() ?? []
            tableView.reloadData()
            if let url, let row = recordings.firstIndex(where: { $0.url == url }) {
                tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                tableView.scrollRowToVisible(row)
            } else if !recordings.isEmpty, tableView.selectedRow < 0 {
                tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            }
            emptyLabel.isHidden = !recordings.isEmpty
            updateControls()
        } catch {
            present(error)
        }
    }

    private func updateControls() {
        let hasSelection = selectedRecording != nil
        replayButton.isEnabled = hasSelection
        renameButton.isEnabled = hasSelection
        deleteButton.isEnabled = hasSelection
        exportButton.isEnabled = hasSelection
    }

    @objc private func replay(_ sender: Any?) {
        guard let selectedRecording else { return }
        perform { try onReplay?(selectedRecording, playbackRate, loopButton.state == .on) }
    }

    @objc private func rename(_ sender: Any?) {
        guard let selectedRecording else { return }
        let alert = NSAlert()
        alert.messageText = L10n.text("Rename Recording")
        alert.informativeText = L10n.text("Enter a new name for this recording.")
        alert.addButton(withTitle: L10n.text("Rename"))
        alert.addButton(withTitle: L10n.text("Cancel"))
        let field = NSTextField(string: selectedRecording.recording.name)
        field.frame.size = CGSize(width: 320, height: 24)
        alert.accessoryView = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform {
            let renamed = try onRename?(selectedRecording, field.stringValue)
            reload(selecting: renamed?.url)
        }
    }

    @objc private func delete(_ sender: Any?) {
        guard let selectedRecording else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.text("Delete “%@”?", selectedRecording.recording.name)
        alert.informativeText = L10n.text("This action cannot be undone.")
        alert.addButton(withTitle: L10n.text("Delete"))
        alert.addButton(withTitle: L10n.text("Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform {
            try onDelete?(selectedRecording)
            reload()
        }
    }

    @objc private func importRecording(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.title = L10n.text("Import Gesture Recording")
        panel.prompt = L10n.text("Import")
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform {
            let imported = try onImport?(url)
            reload(selecting: imported?.url)
        }
    }

    @objc private func export(_ sender: Any?) {
        guard let selectedRecording else { return }
        let panel = NSSavePanel()
        panel.title = L10n.text("Export Gesture Recording")
        panel.prompt = L10n.text("Export")
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = selectedRecording.url.lastPathComponent
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform { try onExport?(selectedRecording, url) }
    }

    @objc private func refresh(_ sender: Any?) { reload() }
    @objc private func closeWindow(_ sender: Any?) { close() }

    private func perform(_ action: () throws -> Void) {
        do { try action() } catch { present(error) }
    }

    private func present(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad
        return formatter
    }()
}
