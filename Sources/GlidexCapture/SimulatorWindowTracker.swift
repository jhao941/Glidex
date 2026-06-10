import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import GlidexCore

@MainActor
final class SimulatorWindowTracker {
    struct Target: Equatable {
        enum Kind: Equatable {
            case screen
            case window
        }

        var frame: CGRect
        var kind: Kind
    }

    private struct AXFrameCandidate {
        var frame: CGRect
        var score: CGFloat
    }

    private let logger: Logger
    private var timer: Timer?
    private var simulatorSize = CGSize.zero
    private var onChange: ((Target) -> Void)?
    private var lastTarget: Target?

    private(set) var isFollowing = false

    init(logger: Logger) {
        self.logger = logger
    }

    func currentTarget(simulatorSize: CGSize) -> Target? {
        if let frame = Self.findSimulatorScreenFrame(simulatorSize: simulatorSize) {
            return Target(frame: frame, kind: .screen)
        }
        return Self.findSimulatorWindowFrame().map { Target(frame: $0, kind: .window) }
    }

    func start(simulatorSize: CGSize, onChange: @escaping (Target) -> Void) {
        guard !isFollowing else { return }
        self.simulatorSize = simulatorSize
        self.onChange = onChange
        isFollowing = true

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.poll()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        logger.info("capture simulator follow enabled")
    }

    func stop() {
        guard isFollowing else { return }
        timer?.invalidate()
        timer = nil
        onChange = nil
        lastTarget = nil
        isFollowing = false
        logger.info("capture simulator follow disabled")
    }

    private func poll() {
        guard let target = currentTarget(simulatorSize: simulatorSize), target != lastTarget else { return }
        lastTarget = target
        onChange?(target)
    }

    private static func findSimulatorScreenFrame(simulatorSize: CGSize) -> CGRect? {
        guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary) else {
            return nil
        }
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.iphonesimulator"
        }), let windowFrame = findSimulatorWindowFrame() else {
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

    private static func findSimulatorWindowFrame() -> CGRect? {
        let options = CGWindowListOption(arrayLiteral: .optionOnScreenOnly, .excludeDesktopElements)
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windows where window[kCGWindowOwnerName as String] as? String == "Simulator" {
            guard let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let x = bounds["X"], let y = bounds["Y"],
                  let width = bounds["Width"], let height = bounds["Height"] else { continue }
            return appKitFrame(from: CGRect(x: x, y: y, width: width, height: height))
        }
        return nil
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

        let aspectError = abs(frame.width / frame.height - targetAspect) / targetAspect
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
        let screenFrame = NSScreen.screens.first?.frame ?? .zero
        return CGRect(
            x: bounds.minX,
            y: screenFrame.maxY - bounds.minY - bounds.height,
            width: bounds.width,
            height: bounds.height
        )
    }

    private static func copyAXAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        return value as? T
    }
}
