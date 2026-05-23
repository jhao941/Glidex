import Foundation

public final class SimulatorInjector: @unchecked Sendable {
    private let logger: Logger
    private let loader: PrivateFrameworkLoader
    private let resolver: BootedSimulatorResolver
    private let simulatorKit: SimulatorKitLoader
    private let backend: IndigoHIDBackend

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

    public func listBootedSimulators() throws -> [BootedSimulatorRecord] {
        try resolver.listBootedSimulators()
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
        let devices = try listBootedSimulators()
        guard let first = devices.first else {
            throw GlidexError.simulatorNotFound("no booted simulator available")
        }
        logger.info("selected simulator name=\(first.name) udid=\(first.udid)")
        return first
    }
}
