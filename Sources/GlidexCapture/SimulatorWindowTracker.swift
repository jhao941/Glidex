import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import GlidexCore

private protocol SimulatorDisplayHost: AnyObject {
    var kind: SimulatorDisplayHostKind { get }
    func discover(simulatorSize: CGSize) -> [SimulatorWindowTracker.Target]
    func refresh(_ target: SimulatorWindowTracker.Target, simulatorSize: CGSize) -> SimulatorWindowTracker.Target?
    func invalidateCache(ownerPID: pid_t)
}

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

        var descriptor: SimulatorDisplayDescriptor
        var kind: Kind
        var hostBundleURL: URL?
        var observedElement: AXUIElement?

        var frame: CGRect { descriptor.contentFrame }
        var windowFrame: CGRect { descriptor.windowFrame }
        var windowTitle: String? { descriptor.windowTitle }
        var ownerPID: pid_t { descriptor.ownerPID }

        static func == (lhs: Target, rhs: Target) -> Bool {
            lhs.descriptor == rhs.descriptor && lhs.kind == rhs.kind && lhs.hostBundleURL == rhs.hostBundleURL
        }
    }

    private let logger: Logger
    private let hosts: [SimulatorDisplayHost]
    private var timer: Timer?
    private var simulatorSize = CGSize.zero
    private var onChange: ((Lookup) -> Void)?
    private var lastLookup: Lookup?
    private var selectedTarget: Target?
    private var observer: AXObserver?
    private var workspaceObserver: NSObjectProtocol?

    private(set) var isFollowing = false
    var onHostApplicationActivated: ((pid_t) -> Void)?

    init(logger: Logger) {
        self.logger = logger
        self.hosts = [DeviceHubHost(), LegacySimulatorHost()]
        observeHostActivation()
    }

    var frontmostHostPID: pid_t? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              SimulatorDisplayHostKind(bundleIdentifier: application.bundleIdentifier) != nil else { return nil }
        return application.processIdentifier
    }

    func discoverTargets(simulatorSize: CGSize) -> [Target] {
        hosts.flatMap { $0.discover(simulatorSize: simulatorSize) }
    }

    func discoverTargets(ownerPID: pid_t, simulatorSize: CGSize) -> [Target] {
        let targets = discoverTargets(simulatorSize: simulatorSize).filter { $0.ownerPID == ownerPID }
        guard targets.count > 1,
              let focusedWindowFrame = AXSupport.focusedWindowFrame(ownerPID: ownerPID) else { return targets }
        let focusedTargets = targets.filter {
            AXSupport.frameDistance($0.windowFrame, focusedWindowFrame) <= 8
        }
        return focusedTargets.isEmpty ? targets : focusedTargets
    }

    func lookupTarget(simulatorSize: CGSize) -> Lookup {
        let targets = discoverTargets(simulatorSize: simulatorSize)
        guard !targets.isEmpty else { return .none }
        guard targets.count == 1, let target = targets.first else { return .ambiguous }
        return .target(target)
    }

    func currentTarget(simulatorSize: CGSize) -> Target? {
        guard case let .target(target) = lookupTarget(simulatorSize: simulatorSize) else { return nil }
        return target
    }

    func start(target: Target, simulatorSize: CGSize, onChange: @escaping (Lookup) -> Void) {
        stop()
        self.simulatorSize = simulatorSize
        self.onChange = onChange
        self.selectedTarget = target
        self.lastLookup = .target(target)
        isFollowing = true
        let hasAXObserver = startAXObserver(target: target)
        startPollingFallback()
        logger.info(
            "capture display follow enabled host=\(target.descriptor.hostKind.rawValue) strategy=\(hasAXObserver ? "ax-observer+health-poll" : "polling-fallback")"
        )
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        observer = nil
        selectedTarget = nil
        onChange = nil
        lastLookup = nil
        let wasFollowing = isFollowing
        isFollowing = false
        if wasFollowing { logger.info("capture display follow disabled") }
    }

    func shutdown() {
        stop()
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
            self.workspaceObserver = nil
        }
        onHostApplicationActivated = nil
    }

    private func observeHostActivation() {
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication,
                  SimulatorDisplayHostKind(bundleIdentifier: application.bundleIdentifier) != nil else { return }
            let ownerPID = application.processIdentifier
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.logger.info(
                    "display host activated bundle=\(application.bundleIdentifier ?? "unknown") pid=\(ownerPID)"
                )
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                    self?.onHostApplicationActivated?(ownerPID)
                }
            }
        }
    }

    private func poll() {
        guard let selectedTarget,
              let host = hosts.first(where: { $0.kind == selectedTarget.descriptor.hostKind }) else { return }
        let lookup: Lookup
        if let refreshed = host.refresh(selectedTarget, simulatorSize: simulatorSize) {
            self.selectedTarget = refreshed
            lookup = .target(refreshed)
        } else {
            lookup = .none
        }
        guard lookup != lastLookup else { return }
        lastLookup = lookup
        onChange?(lookup)
    }

    private func startAXObserver(target: Target) -> Bool {
        guard target.ownerPID != 0, let element = target.observedElement else { return false }
        var createdObserver: AXObserver?
        guard AXObserverCreate(target.ownerPID, Self.observerCallback, &createdObserver) == .success,
              let createdObserver else { return false }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let notifications = [
            kAXMovedNotification as String,
            kAXResizedNotification as String,
            kAXUIElementDestroyedNotification as String,
            kAXLayoutChangedNotification as String,
        ]
        var installed = false
        for notification in notifications {
            if AXObserverAddNotification(createdObserver, element, notification as CFString, refcon) == .success {
                installed = true
            }
        }
        guard installed else { return false }
        observer = createdObserver
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(createdObserver), .commonModes)
        return true
    }

    private func startPollingFallback() {
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private static let observerCallback: AXObserverCallback = { _, element, notification, refcon in
        guard let refcon else { return }
        let tracker = Unmanaged<SimulatorWindowTracker>.fromOpaque(refcon).takeUnretainedValue()
        let wasDestroyed = notification as String == kAXUIElementDestroyedNotification as String
        DispatchQueue.main.async {
            if wasDestroyed,
               let target = tracker.selectedTarget,
               let host = tracker.hosts.first(where: { $0.kind == target.descriptor.hostKind }) {
                host.invalidateCache(ownerPID: target.ownerPID)
                if let observer = tracker.observer {
                    CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
                }
                tracker.observer = nil
            }
            tracker.poll()
            if tracker.isFollowing, tracker.observer == nil, let target = tracker.selectedTarget {
                _ = tracker.startAXObserver(target: target)
            }
        }
        _ = element
    }
}

private final class DeviceHubHost: SimulatorDisplayHost {
    let kind = SimulatorDisplayHostKind.deviceHub
    private let bundleIdentifier = "com.apple.dt.Devices"
    private var cachedGroups: [pid_t: [AXUIElement]] = [:]

    func discover(simulatorSize: CGSize) -> [SimulatorWindowTracker.Target] {
        NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == bundleIdentifier }
            .flatMap { targets(for: $0, rebuildCache: false) }
    }

    func refresh(
        _ target: SimulatorWindowTracker.Target,
        simulatorSize: CGSize
    ) -> SimulatorWindowTracker.Target? {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.processIdentifier == target.ownerPID && $0.bundleIdentifier == bundleIdentifier
        }) else {
            invalidateCache(ownerPID: target.ownerPID)
            return nil
        }
        let refreshedTargets = targets(for: app, rebuildCache: false)
        if let exact = refreshedTargets.first(where: {
            $0.descriptor.representsSameDisplay(as: target.descriptor)
        }) { return exact }
        if refreshedTargets.count == 1 { return refreshedTargets[0] }
        invalidateCache(ownerPID: target.ownerPID)
        let rebuilt = targets(for: app, rebuildCache: true)
        return rebuilt.count == 1 ? rebuilt[0] : nil
    }

    func invalidateCache(ownerPID: pid_t) {
        cachedGroups[ownerPID] = nil
    }

    private func targets(for app: NSRunningApplication, rebuildCache: Bool) -> [SimulatorWindowTracker.Target] {
        let pid = app.processIdentifier
        if rebuildCache { cachedGroups[pid] = nil }
        let appElement = AXUIElementCreateApplication(pid)
        guard let windows: [AXUIElement] = AXSupport.copyAttribute(appElement, kAXWindowsAttribute) else { return [] }
        let groups: [AXUIElement]
        if let cached = cachedGroups[pid], !cached.isEmpty, cached.allSatisfy({ AXSupport.frame($0) != nil }) {
            groups = cached
        } else {
            groups = windows.flatMap { AXSupport.findElements(in: $0, subrole: "iOSContentGroup") }
            cachedGroups[pid] = groups
        }
        let metadata = windows.reduce(into: [ObjectIdentifier: DeviceHubMetadata]()) { result, window in
            result[ObjectIdentifier(window)] = AXSupport.deviceHubMetadata(in: window)
        }
        let resolution = DeveloperDirectoryResolver().resolve(hostBundleURL: app.bundleURL)

        return groups.compactMap { group in
            guard let contentFrame = AXSupport.frame(group),
                  let window: AXUIElement = AXSupport.copyAttribute(group, kAXWindowAttribute),
                  let windowFrame = AXSupport.frame(window) else { return nil }
            let info = metadata[ObjectIdentifier(window)] ?? AXSupport.deviceHubMetadata(in: window)
            let title: String? = AXSupport.copyAttribute(window, kAXTitleAttribute)
            return SimulatorWindowTracker.Target(
                descriptor: SimulatorDisplayDescriptor(
                    hostKind: .deviceHub,
                    ownerPID: pid,
                    windowFrame: windowFrame,
                    contentFrame: contentFrame,
                    windowTitle: title,
                    deviceName: info.deviceName,
                    runtime: info.runtime,
                    deviceUDID: info.udid,
                    developerDirectory: resolution?.developerDirectory
                ),
                kind: .screen,
                hostBundleURL: app.bundleURL,
                observedElement: group
            )
        }
    }
}

private final class LegacySimulatorHost: SimulatorDisplayHost {
    let kind = SimulatorDisplayHostKind.legacySimulator
    private let bundleIdentifier = "com.apple.iphonesimulator"

    func discover(simulatorSize: CGSize) -> [SimulatorWindowTracker.Target] {
        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) else { return [] }
        let resolution = DeveloperDirectoryResolver().resolve(hostBundleURL: app.bundleURL)
        return AXSupport.legacyWindows(ownerPID: app.processIdentifier).map { window in
            let screen = AXSupport.findLegacyScreenFrame(
                in: window.element,
                simulatorSize: simulatorSize,
                windowFrame: window.frame
            )
            return SimulatorWindowTracker.Target(
                descriptor: SimulatorDisplayDescriptor(
                    hostKind: .legacySimulator,
                    ownerPID: app.processIdentifier,
                    windowFrame: window.frame,
                    contentFrame: screen ?? window.frame,
                    windowTitle: window.title,
                    developerDirectory: resolution?.developerDirectory
                ),
                kind: screen == nil ? .window : .screen,
                hostBundleURL: app.bundleURL,
                observedElement: window.element
            )
        }
    }

    func refresh(
        _ target: SimulatorWindowTracker.Target,
        simulatorSize: CGSize
    ) -> SimulatorWindowTracker.Target? {
        discover(simulatorSize: simulatorSize).min(by: {
            AXSupport.frameDistance($0.descriptor.windowFrame, target.descriptor.windowFrame) <
                AXSupport.frameDistance($1.descriptor.windowFrame, target.descriptor.windowFrame)
        })
    }

    func invalidateCache(ownerPID: pid_t) {}
}

private struct DeviceHubMetadata {
    var udid: String?
    var deviceName: String?
    var runtime: String?
}

private enum AXSupport {
    private static let uuidPattern = try! NSRegularExpression(
        pattern: #"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"#
    )

    static func findElements(in root: AXUIElement, subrole: String) -> [AXUIElement] {
        var results: [AXUIElement] = []
        var visited = 0
        walk(root, depth: 0, visited: &visited) { element in
            let value: String? = copyAttribute(element, kAXSubroleAttribute)
            if value == subrole { results.append(element) }
        }
        return results
    }

    static func deviceHubMetadata(in window: AXUIElement) -> DeviceHubMetadata {
        var strings: [String] = []
        var visited = 0
        walk(window, depth: 0, visited: &visited) { element in
            for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXIdentifierAttribute] {
                if let value: String = copyAttribute(element, attribute), !value.isEmpty {
                    strings.append(value)
                }
            }
        }
        let joined = strings.joined(separator: "\n")
        let range = NSRange(joined.startIndex..., in: joined)
        let udid = uuidPattern.firstMatch(in: joined, range: range).flatMap {
            Range($0.range, in: joined).map { String(joined[$0]) }
        }
        let runtime = strings.first(where: { $0.range(of: #"iOS\s*\d+(?:\.\d+)*"#, options: .regularExpression) != nil })
        let deviceName = strings.first(where: {
            $0.localizedCaseInsensitiveContains("iPhone") || $0.localizedCaseInsensitiveContains("iPad")
        })
        return DeviceHubMetadata(udid: udid, deviceName: deviceName, runtime: runtime)
    }

    static func legacyWindows(ownerPID: pid_t) -> [(element: AXUIElement, frame: CGRect, title: String?)] {
        let app = AXUIElementCreateApplication(ownerPID)
        guard let windows: [AXUIElement] = copyAttribute(app, kAXWindowsAttribute) else { return [] }
        return windows.compactMap { window in
            guard let frame = frame(window), frame.width >= 180, frame.height >= 320 else { return nil }
            let title: String? = copyAttribute(window, kAXTitleAttribute)
            return (window, frame, title)
        }
    }

    static func focusedWindowFrame(ownerPID: pid_t) -> CGRect? {
        let app = AXUIElementCreateApplication(ownerPID)
        guard let window: AXUIElement = copyAttribute(app, kAXFocusedWindowAttribute) else { return nil }
        return frame(window)
    }

    static func findLegacyScreenFrame(
        in window: AXUIElement,
        simulatorSize: CGSize,
        windowFrame: CGRect
    ) -> CGRect? {
        let targetAspect = simulatorSize.width / simulatorSize.height
        var candidates: [(CGRect, CGFloat)] = []
        var visited = 0
        walk(window, depth: 0, visited: &visited) { element in
            guard let candidate = frame(element),
                  let score = candidateScore(candidate, windowFrame: windowFrame, targetAspect: targetAspect) else { return }
            candidates.append((candidate, score))
        }
        return candidates.max(by: { $0.1 < $1.1 })?.0
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let positionValue: AXValue = copyAttribute(element, kAXPositionAttribute),
              let sizeValue: AXValue = copyAttribute(element, kAXSizeAttribute) else { return nil }
        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue, .cgPoint, &position),
              AXValueGetValue(sizeValue, .cgSize, &size), size.width > 0, size.height > 0 else { return nil }
        return appKitFrame(from: CGRect(origin: position, size: size))
    }

    static func frameDistance(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        abs(lhs.minX - rhs.minX) + abs(lhs.minY - rhs.minY) + abs(lhs.width - rhs.width) + abs(lhs.height - rhs.height)
    }

    static func copyAttribute<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        return value as? T
    }

    private static func walk(
        _ element: AXUIElement,
        depth: Int,
        visited: inout Int,
        visit: (AXUIElement) -> Void
    ) {
        guard depth <= 10, visited < 1_200 else { return }
        visited += 1
        visit(element)
        guard let children: [AXUIElement] = copyAttribute(element, kAXChildrenAttribute) else { return }
        for child in children { walk(child, depth: depth + 1, visited: &visited, visit: visit) }
    }

    private static func candidateScore(
        _ frame: CGRect,
        windowFrame: CGRect,
        targetAspect: CGFloat
    ) -> CGFloat? {
        guard frame.width >= 160, frame.height >= 320,
              frame.width < windowFrame.width * 0.98 || frame.height < windowFrame.height * 0.98,
              windowFrame.insetBy(dx: -2, dy: -2).contains(frame) else { return nil }
        let aspect = frame.width / frame.height
        let error = min(abs(aspect - targetAspect) / targetAspect, abs(aspect - 1 / targetAspect) / (1 / targetAspect))
        guard error <= 0.18 else { return nil }
        let areaRatio = frame.width * frame.height / max(windowFrame.width * windowFrame.height, 1)
        guard areaRatio >= 0.25 else { return nil }
        return areaRatio * 1.4 - error * 2.2
    }

    private static func appKitFrame(from frame: CGRect) -> CGRect {
        DesktopCoordinateSpace(mainDisplayHeight: CGDisplayBounds(CGMainDisplayID()).height)
            .appKitFrame(fromQuartzTopLeft: frame)
    }
}
