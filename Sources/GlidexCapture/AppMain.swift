import AppKit
import GlidexCore

@main
struct GlidexCaptureMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let controller = AppController(logger: Logger())
        app.delegate = controller

        app.finishLaunching()
        controller.start()

        withExtendedLifetime(controller) {
            app.run()
        }
    }
}
