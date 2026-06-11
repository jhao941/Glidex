import Foundation

public final class SimulatorInjector: @unchecked Sendable {
    private let logger: Logger
    private let loader: PrivateFrameworkLoader
    private let resolver: BootedSimulatorResolver
    private let simulatorKit: SimulatorKitLoader
    private let backend: IndigoHIDBackend
    private var selectedSimulator: BootedSimulatorRecord?

    public init(logger: Logger) throws {
        self.logger = logger
        self.loader = PrivateFrameworkLoader(logger: logger)
        self.resolver = BootedSimulatorResolver(logger: logger, loader: loader)
        self.simulatorKit = SimulatorKitLoader(logger: logger, loader: loader)
        self.backend = IndigoHIDBackend(logger: logger, simulatorKit: simulatorKit)
    }

    public func probe() throws {
        logger.info("probing private frameworks")
        _ = try listBootedSimulators()
        try simulatorKit.probe()
        try backend.probeFactories()
    }

    public func swiftProbe() throws {
        try simulatorKit.load()
        guard let framework = simulatorKit.framework else {
            throw GlidexError.frameworkLoadFailed("SimulatorKit framework not loaded")
        }
        try SwiftMetadataProbe.run(framework: framework, logger: logger)
    }

    public func multitouchProbe(duration: TimeInterval, mode: Int32, source: MultitouchProbeSource) throws {
        let probe = MultitouchSupportProbe(logger: logger, loader: loader)
        try probe.run(options: MultitouchProbeOptions(duration: duration, mode: mode, source: source))
    }

    public func listBootedSimulators() throws -> [BootedSimulatorRecord] {
        try resolver.listBootedSimulators()
    }

    public func useDeveloperDirectory(_ resolution: DeveloperDirectoryResolution) {
        resolver.useDeveloperDirectory(resolution.developerDirectory)
        simulatorKit.useFramework(at: resolution.simulatorKitPath)
        selectedSimulator = nil
        logger.info("selected developer directory: \(resolution.developerDirectory)")
    }

    @discardableResult
    public func selectTarget(udid: String) throws -> SimulatorTarget {
        let devices = try listBootedSimulators()
        guard let simulator = devices.first(where: { $0.udid.caseInsensitiveCompare(udid) == .orderedSame }) else {
            throw GlidexError.simulatorNotFound("booted simulator not found for UDID \(udid)")
        }
        selectedSimulator = simulator
        return try resolvedTarget(for: simulator)
    }

    public func selectedTarget() throws -> SimulatorTarget {
        let simulator = try selectTargetRecord()
        return try resolvedTarget(for: simulator)
    }

    public func tap(at point: CGPoint) throws {
        let simulator = try selectTarget()
        let simDevice = try resolver.resolveSimDevice(udid: simulator.udid)
        try backend.attemptTap(on: simulator, simDevice: simDevice, point: point)
    }

    public func digitizerTap(at point: CGPoint) throws {
        let simulator = try selectTarget()
        let simDevice = try resolver.resolveSimDevice(udid: simulator.udid)
        try backend.attemptDigitizerTap(on: simulator, simDevice: simDevice, point: point)
    }

    public func drag(from: CGPoint, to: CGPoint, duration: TimeInterval) throws {
        let simulator = try selectTarget()
        let simDevice = try resolver.resolveSimDevice(udid: simulator.udid)
        try backend.attemptDrag(on: simulator, simDevice: simDevice, from: from, to: to, duration: duration)
    }

    public func pinch(center: CGPoint, scale: Double, duration: TimeInterval) throws {
        let simulator = try selectTarget()
        let simDevice = try resolver.resolveSimDevice(udid: simulator.udid)
        try backend.attemptPinch(on: simulator, simDevice: simDevice, center: center, scale: scale, duration: duration)
    }

    public func makeLiveTouchSession() throws -> LiveTouchSession {
        let simulator = try selectTarget()
        let simDevice = try resolver.resolveSimDevice(udid: simulator.udid)
        return try backend.makeLiveTouchSession(on: simulator, simDevice: simDevice)
    }

    public func makeLiveTwoFingerTouchSession() throws -> LiveTwoFingerTouchSession {
        let simulator = try selectTarget()
        let simDevice = try resolver.resolveSimDevice(udid: simulator.udid)
        return try backend.makeLiveTwoFingerTouchSession(on: simulator, simDevice: simDevice)
    }

    private func selectTarget() throws -> BootedSimulatorRecord {
        try selectTargetRecord()
    }

    private func selectTargetRecord() throws -> BootedSimulatorRecord {
        if let selectedSimulator {
            return selectedSimulator
        }
        let devices = try listBootedSimulators()
        guard !devices.isEmpty else {
            throw GlidexError.simulatorNotFound("no booted simulator available")
        }
        guard devices.count == 1, let only = devices.first else {
            let summary = devices.map { "\($0.name) [\($0.udid)]" }.joined(separator: ", ")
            throw GlidexError.simulatorNotFound("multiple booted simulators require explicit selection: \(summary)")
        }
        selectedSimulator = only
        logger.info("selected sole booted simulator name=\(only.name) udid=\(only.udid)")
        return only
    }

    private func resolvedTarget(for simulator: BootedSimulatorRecord) throws -> SimulatorTarget {
        let simDevice = try resolver.resolveSimDevice(udid: simulator.udid)
        let metrics = backend.resolveScreenMetrics(for: simDevice, fallback: simulator)
        return SimulatorTarget(
            name: simulator.name,
            udid: simulator.udid,
            runtime: simulator.runtime,
            deviceType: simulator.deviceType,
            pointSize: SimulatorPointSize(metrics.pointSize)
        )
    }
}
