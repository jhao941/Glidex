import AppKit
import CoreGraphics
import Foundation
import SimTouchCore

@main
struct SimTouchCaptureMain {
    @MainActor
    static func main() {
        let logger = Logger()
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)

        let contentView = CaptureView(logger: logger)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 402, height: 874),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        let windowDelegate = CaptureWindowDelegate()

        window.title = "SimTouch Capture"
        window.delegate = windowDelegate
        window.center()
        window.contentView = contentView
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
    func windowWillClose(_ notification: Notification) {
        NSApp.terminate(nil)
    }
}

private final class CaptureView: NSView {
    private let logger: Logger
    private let injector: SimulatorInjector
    private let injectionQueue = DispatchQueue(label: "simtouch.capture.injection", qos: .userInitiated)
    private let mapper = CaptureCoordinateMapper()
    private var panStart: CGPoint?
    private var magnificationStartTime: Date?
    private var accumulatedMagnification: CGFloat = 0

    init(logger: Logger) {
        self.logger = logger
        do {
            self.injector = try SimulatorInjector(logger: logger)
        } catch {
            logger.error("failed to initialize injector: \(error)")
            fatalError("failed to initialize injector: \(error)")
        }

        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        setupGestures()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        bounds.fill()

        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1))
        border.lineWidth = 2
        border.stroke()

        drawCenteredLabel("SimTouch Capture", yOffset: 18, fontSize: 20, weight: .semibold)
        drawCenteredLabel("Click, drag, or pinch in this window", yOffset: -14, fontSize: 13, weight: .regular)
    }

    private func setupGestures() {
        let click = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        click.numberOfClicksRequired = 1
        addGestureRecognizer(click)

        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)

        let magnify = NSMagnificationGestureRecognizer(target: self, action: #selector(handleMagnification(_:)))
        addGestureRecognizer(magnify)
    }

    @objc private func handleClick(_ gesture: NSClickGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let localPoint = gesture.location(in: self)
        let simulatorPoint = mapper.simulatorPoint(from: localPoint, in: bounds)
        logger.info("capture click local=\(format(localPoint)) simulator=\(format(simulatorPoint))")
        let injector = self.injector

        runInjection {
            try injector.tap(at: simulatorPoint)
        }
    }

    @objc private func handlePan(_ gesture: NSPanGestureRecognizer) {
        let localPoint = gesture.location(in: self)

        switch gesture.state {
        case .began:
            panStart = localPoint
            logger.info("capture drag began local=\(format(localPoint))")
        case .ended, .cancelled:
            guard let panStart else { return }
            self.panStart = nil

            let start = mapper.simulatorPoint(from: panStart, in: bounds)
            let end = mapper.simulatorPoint(from: localPoint, in: bounds)
            logger.info("capture drag ended simulator=\(format(start))->\(format(end))")
            let injector = self.injector

            runInjection {
                try injector.drag(from: start, to: end, duration: 0.35)
            }
        default:
            break
        }
    }

    @objc private func handleMagnification(_ gesture: NSMagnificationGestureRecognizer) {
        let localPoint = gesture.location(in: self)

        switch gesture.state {
        case .began:
            magnificationStartTime = Date()
            accumulatedMagnification = 0
            logger.info("capture pinch began local=\(format(localPoint))")
        case .changed:
            accumulatedMagnification += gesture.magnification
        case .ended, .cancelled:
            let center = mapper.simulatorPoint(from: localPoint, in: bounds)
            let scale = max(0.2, Double(1 + accumulatedMagnification))
            let duration = Date().timeIntervalSince(magnificationStartTime ?? Date())
            magnificationStartTime = nil
            accumulatedMagnification = 0
            logger.info("capture pinch ended center=\(format(center)) scale=\(String(format: "%.3f", scale)) duration=\(String(format: "%.3f", duration))")
            let injector = self.injector

            runInjection {
                try injector.pinch(center: center, scale: scale, duration: max(0.2, duration))
            }
        default:
            break
        }
    }

    private func runInjection(_ action: @escaping @Sendable () throws -> Void) {
        injectionQueue.async { [logger] in
            do {
                try action()
            } catch {
                logger.error("capture injection failed: \(error)")
            }
        }
    }

    private func drawCenteredLabel(_ text: String, yOffset: CGFloat, fontSize: CGFloat, weight: NSFont.Weight) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: weight),
            .foregroundColor: NSColor.labelColor,
        ]
        let size = text.size(withAttributes: attributes)
        let point = CGPoint(
            x: bounds.midX - size.width / 2,
            y: bounds.midY + yOffset - size.height / 2
        )
        text.draw(at: point, withAttributes: attributes)
    }

    private func format(_ point: CGPoint) -> String {
        "(\(Int(point.x)), \(Int(point.y)))"
    }
}

private struct CaptureCoordinateMapper {
    private let simulatorSize = CGSize(width: 402, height: 874)

    func simulatorPoint(from localPoint: CGPoint, in bounds: CGRect) -> CGPoint {
        guard bounds.width > 0, bounds.height > 0 else {
            return .zero
        }

        let clampedX = min(max(localPoint.x, bounds.minX), bounds.maxX)
        let clampedY = min(max(localPoint.y, bounds.minY), bounds.maxY)
        let normalizedX = (clampedX - bounds.minX) / bounds.width
        let normalizedYFromTop = (bounds.maxY - clampedY) / bounds.height

        return CGPoint(
            x: normalizedX * simulatorSize.width,
            y: normalizedYFromTop * simulatorSize.height
        )
    }
}
