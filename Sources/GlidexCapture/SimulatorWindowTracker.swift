import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import GlidexCore

@MainActor
final class SimulatorWindowTracker {
    enum Lookup: Equatable {
        case none
        case target(Target)
        case ambiguous
    }

    struct Target: Equatable {
        enum Kind: Equatable {
            case screen
            case window
        }

        var frame: CGRect
        var kind: Kind
        var windowTitle: String?
        var ownerPID: pid_t
    }

    private struct AXFrameCandidate {
        var frame: CGRect
        var score: CGFloat
    }

    private let logger: Logger
    private var timer: Timer?
    private var simulatorSize = CGSize.zero
    private var onChange: ((Lookup) -> Void)?
    private var lastLookup: Lookup?
    private var observer: AXObserver?
    private var observedWindow: AXUIElement?

    private(set) var isFollowing = false

    init(logger: Logger) {
        self.logger = logger
    }

    func currentTarget(simulatorSize: CGSize) -> Target? {
        guard case let .target(target) = lookupTarget(simulatorSize: simulatorSize) else {
            return nil
        }
        return target
    }

    func lookupTarget(simulatorSize: CGSize) -> Lookup {
        let windows = Self.findSimulatorWindows()
        guard !windows.isEmpty else { return .none }
        guard windows.count == 1, let window = windows.first else { return .ambiguous }
        if let frame = Self.findSimulatorScreenFrame(
            simulatorSize: simulatorSize,
            windowFrame: window.frame
        ) {
            return .target(Target(
                frame: frame,
                kind: .screen,
                windowTitle: window.title,
                ownerPID: window.pid
            ))
        }
        return .target(Target(
            frame: window.frame,
            kind: .window,
            windowTitle: window.title,
            ownerPID: window.pid
        ))
    }

    func start(simulatorSize: CGSize, onChange: @escaping (Lookup) -> Void) {
        guard !isFollowing else { return }
        self.simulatorSize = simulatorSize
        self.onChange = onChange
        isFollowing = true
        poll()
        guard isFollowing else { return }
        let hasAXObserver = startAXObserver()
        startPollingFallback()
        logger.info("capture simulator follow enabled strategy=\(hasAXObserver ? "ax-observer+health-poll" : "polling-fallback")")
    }

    func stop() {
        guard isFollowing else { return }
        timer?.invalidate()
        timer = nil
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        observedWindow = nil
        onChange = nil
        lastLookup = nil
        isFollowing = false
        logger.info("capture simulator follow disabled")
    }

    private func poll() {
        let lookup = lookupTarget(simulatorSize: simulatorSize)
        guard lookup != lastLookup else { return }
        lastLookup = lookup
        onChange?(lookup)
    }

    private func startAXObserver() -> Bool {
        guard let target = currentTarget(simulatorSize: simulatorSize), target.ownerPID != 0 else { return false }
        let appElement = AXUIElementCreateApplication(target.ownerPID)
        guard let windows: [AXUIElement] = Self.copyAXAttribute(appElement, kAXWindowsAttribute),
              let window = windows.min(by: {
                  Self.frameDistance(Self.axFrame($0), target.frame) < Self.frameDistance(Self.axFrame($1), target.frame)
              }) else { return false }

        var createdObserver: AXObserver?
        let result = AXObserverCreate(target.ownerPID, Self.observerCallback, &createdObserver)
        guard result == .success, let createdObserver else { return false }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverAddNotification(createdObserver, window, kAXMovedNotification as CFString, refcon) == .success,
              AXObserverAddNotification(createdObserver, window, kAXResizedNotification as CFString, refcon) == .success else {
            return false
        }
        _ = AXObserverAddNotification(createdObserver, window, kAXUIElementDestroyedNotification as CFString, refcon)

        observer = createdObserver
        observedWindow = window
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(createdObserver), .commonModes)
        return true
    }

    private func startPollingFallback() {
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private static let observerCallback: AXObserverCallback = { _, _, _, refcon in
        guard let refcon else { return }
        let tracker = Unmanaged<SimulatorWindowTracker>.fromOpaque(refcon).takeUnretainedValue()
        DispatchQueue.main.async {
            tracker.poll()
        }
    }

    private static func findSimulatorScreenFrame(
        simulatorSize: CGSize,
        windowFrame: CGRect
    ) -> CGRect? {
        guard AXIsProcessTrusted() else {
            return nil
        }
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.iphonesimulator"
        }) else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        guard let windows: [AXUIElement] = copyAXAttribute(appElement, kAXWindowsAttribute) else { return nil }

        let targetAspect = simulatorSize.width / simulatorSize.height
        var candidates: [AXFrameCandidate] = []
        var visited = 0
        for window in windows {
            collectScreenCandidates(
                from: window,
                windowFrame: windowFrame,
                targetAspect: targetAspect,
                depth: 0,
                visited: &visited,
                candidates: &candidates
            )
        }
        return candidates.max(by: { $0.score < $1.score })?.frame
    }

    private static func findSimulatorWindows() -> [(frame: CGRect, title: String?, pid: pid_t)] {
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windows.compactMap { window in
            guard window[kCGWindowOwnerName as String] as? String == "Simulator" else { return nil }
            guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"],
                  width >= 180, height >= 320 else { return nil }
            let title = window[kCGWindowName as String] as? String
            let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            return (appKitFrame(from: CGRect(x: x, y: y, width: width, height: height)), title, pid)
        }
    }

    private static func collectScreenCandidates(
        from element: AXUIElement,
        windowFrame: CGRect,
        targetAspect: CGFloat,
        depth: Int,
        visited: inout Int,
        candidates: inout [AXFrameCandidate]
    ) {
        guard depth <= 8, visited < 1_000 else { return }
        visited += 1

        if let frame = elementFrame(element, containing: windowFrame),
           let score = candidateScore(frame: frame, windowFrame: windowFrame, targetAspect: targetAspect) {
            candidates.append(AXFrameCandidate(frame: frame, score: score))
        }

        guard let children: [AXUIElement] = copyAXAttribute(element, kAXChildrenAttribute) else { return }
        for child in children {
            collectScreenCandidates(
                from: child,
                windowFrame: windowFrame,
                targetAspect: targetAspect,
                depth: depth + 1,
                visited: &visited,
                candidates: &candidates
            )
        }
    }

    private static func candidateScore(frame: CGRect, windowFrame: CGRect, targetAspect: CGFloat) -> CGFloat? {
        guard frame.width >= 160, frame.height >= 320 else { return nil }
        guard frame.width < windowFrame.width * 0.98 || frame.height < windowFrame.height * 0.98 else { return nil }
        guard windowFrame.insetBy(dx: -2, dy: -2).contains(frame) else { return nil }

        let frameAspect = frame.width / frame.height
        let portraitError = abs(frameAspect - targetAspect) / targetAspect
        let rotatedAspect = 1 / targetAspect
        let landscapeError = abs(frameAspect - rotatedAspect) / rotatedAspect
        let aspectError = min(portraitError, landscapeError)
        guard aspectError <= 0.18 else { return nil }
        let areaRatio = frame.width * frame.height / max(windowFrame.width * windowFrame.height, 1)
        guard areaRatio >= 0.25 else { return nil }

        let centerError = abs(frame.midX - windowFrame.midX) / max(windowFrame.width, 1)
        let toolbarBonus: CGFloat = windowFrame.maxY - frame.maxY > 20 ? 0.15 : 0
        return areaRatio * 1.4 - aspectError * 2.2 - centerError + toolbarBonus
    }

    private static func elementFrame(_ element: AXUIElement, containing windowFrame: CGRect) -> CGRect? {
        guard let positionValue: AXValue = copyAXAttribute(element, kAXPositionAttribute),
              let sizeValue: AXValue = copyAXAttribute(element, kAXSizeAttribute) else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size), size.width > 0, size.height > 0 else { return nil }

        let rawFrame = CGRect(origin: position, size: size)
        let converted = appKitFrame(from: rawFrame)
        if windowFrame.insetBy(dx: -2, dy: -2).contains(converted) { return converted }
        if windowFrame.insetBy(dx: -2, dy: -2).contains(rawFrame) { return rawFrame }
        return converted
    }

    private static func appKitFrame(from bounds: CGRect) -> CGRect {
        DesktopCoordinateSpace(
            mainDisplayHeight: CGDisplayBounds(CGMainDisplayID()).height
        ).appKitFrame(fromQuartzTopLeft: bounds)
    }

    private static func axFrame(_ element: AXUIElement) -> CGRect? {
        guard let positionValue: AXValue = copyAXAttribute(element, kAXPositionAttribute),
              let sizeValue: AXValue = copyAXAttribute(element, kAXSizeAttribute) else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size) else { return nil }
        return appKitFrame(from: CGRect(origin: position, size: size))
    }

    private static func frameDistance(_ lhs: CGRect?, _ rhs: CGRect) -> CGFloat {
        guard let lhs else { return .greatestFiniteMagnitude }
        return abs(lhs.minX - rhs.minX) + abs(lhs.minY - rhs.minY) +
            abs(lhs.width - rhs.width) + abs(lhs.height - rhs.height)
    }

    private static func copyAXAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        return value as? T
    }
}
