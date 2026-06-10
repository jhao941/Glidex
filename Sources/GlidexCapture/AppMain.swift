import AppKit
import GlidexCore

@main
struct GlidexCaptureMain {
    @MainActor
    static func main() {
        let logger = Logger()
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let contentView = CaptureView(logger: logger)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let windowDelegate = CaptureWindowDelegate(captureView: contentView)

        window.title = "Glidex Capture"
        window.delegate = windowDelegate
        window.center()
        window.contentView = contentView
        contentView.hostWindow = window
        window.makeKeyAndOrderFront(nil)

        app.finishLaunching()
        app.activate(ignoringOtherApps: true)
        logger.info("capture app ready")

        withExtendedLifetime((window, windowDelegate, logger)) {
            app.run()
        }
    }
}

@MainActor
private final class CaptureWindowDelegate: NSObject, NSWindowDelegate {
    private weak var captureView: CaptureView?

    init(captureView: CaptureView) {
        self.captureView = captureView
    }

    func windowDidResignKey(_ notification: Notification) {
        captureView?.cancelInput(reason: "window resigned key")
    }

    func windowWillClose(_ notification: Notification) {
        captureView?.shutdown()
        NSApp.terminate(nil)
    }
}
