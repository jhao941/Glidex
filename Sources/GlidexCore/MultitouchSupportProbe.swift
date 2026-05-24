import CoreFoundation
import Foundation

public struct MultitouchProbeOptions: Sendable {
    public let duration: TimeInterval
    public let mode: Int32
    public let source: MultitouchProbeSource

    public init(duration: TimeInterval = 10, mode: Int32 = 0, source: MultitouchProbeSource = .default) {
        self.duration = duration
        self.mode = mode
        self.source = source
    }
}

public enum MultitouchProbeSource: String, Sendable {
    case list
    case `default`
    case both
}

public struct RawTouchContact: Sendable {
    public let identifier: Int32
    public let state: Int32
    public let normalizedPosition: CGPoint
    public let normalizedVelocity: CGPoint
    public let size: Float

    public var isActive: Bool {
        state != 7
    }
}

public struct RawTouchFrame: Sendable {
    public let timestamp: Double
    public let frame: Int32
    public let contacts: [RawTouchContact]
}

struct MTPoint {
    var x: Float
    var y: Float
}

struct MTVector {
    var position: MTPoint
    var velocity: MTPoint
}

struct MTContact {
    var frame: Int32
    var timestamp: Double
    var identifier: Int32
    var state: Int32
    var unknown1: Int32
    var unknown2: Int32
    var normalized: MTVector
    var size: Float
    var unknown3: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var unknown4: MTVector
    var unknown5_1: Int32
    var unknown5_2: Int32
    var unknown6: Float
}

public final class MultitouchSupportProbe: @unchecked Sendable {
    private typealias MTDeviceRef = UnsafeMutableRawPointer
    private typealias ContactFrameCallback = @convention(c) (
        MTDeviceRef?,
        UnsafeMutableRawPointer?,
        Int32,
        Double,
        Int32
    ) -> Int32
    private typealias MTDeviceCreateListFn = @convention(c) () -> Unmanaged<CFArray>?
    private typealias MTDeviceCreateDefaultFn = @convention(c) () -> MTDeviceRef?
    private typealias MTRegisterContactFrameCallbackFn = @convention(c) (MTDeviceRef?, ContactFrameCallback?) -> Void
    private typealias MTUnregisterContactFrameCallbackFn = @convention(c) (MTDeviceRef?, ContactFrameCallback?) -> Void
    private typealias MTDeviceStartFn = @convention(c) (MTDeviceRef?, Int32) -> Void
    private typealias MTDeviceStopFn = @convention(c) (MTDeviceRef?) -> Void
    private typealias MTDeviceReleaseFn = @convention(c) (MTDeviceRef?) -> Void

    private static let frameworkPath = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
    private static let activeLock = NSLock()
    private nonisolated(unsafe) static var activeProbe: MultitouchSupportProbe?

    private let logger: Logger
    private let loader: PrivateFrameworkLoader
    private var loaded: PrivateFrameworkHandle?
    private var createList: MTDeviceCreateListFn?
    private var createDefault: MTDeviceCreateDefaultFn?
    private var registerContactFrameCallback: MTRegisterContactFrameCallbackFn?
    private var unregisterContactFrameCallback: MTUnregisterContactFrameCallbackFn?
    private var startDevice: MTDeviceStartFn?
    private var stopDevice: MTDeviceStopFn?
    private var releaseDevice: MTDeviceReleaseFn?
    private var devices: [MTDeviceRef] = []
    private var deviceList: CFArray?
    private let printLock = NSLock()
    private var frameCount = 0

    init(logger: Logger, loader: PrivateFrameworkLoader) {
        self.logger = logger
        self.loader = loader
    }

    public func run(options: MultitouchProbeOptions = MultitouchProbeOptions()) throws {
        try load()
        try openDevices(source: options.source)

        guard !devices.isEmpty else {
            throw GlidexError.unsupported("MultitouchSupport returned no devices")
        }

        Self.activeLock.lock()
        Self.activeProbe = self
        Self.activeLock.unlock()
        defer {
            Self.activeLock.lock()
            Self.activeProbe = nil
            Self.activeLock.unlock()
        }

        logger.info(
            "starting MultitouchSupport probe for \(String(format: "%.1f", options.duration))s " +
            "source=\(options.source.rawValue) mode=\(options.mode); touch the trackpad now"
        )
        for device in devices {
            registerContactFrameCallback?(device, Self.contactFrameCallback)
            startDevice?(device, options.mode)
            logger.info("MTDeviceStart device=\(deviceLabel(device))")
        }

        let deadline = Date().addingTimeInterval(options.duration)
        while Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, min(0.05, deadline.timeIntervalSinceNow), false)
        }

        for device in devices {
            unregisterContactFrameCallback?(device, Self.contactFrameCallback)
        }
        Thread.sleep(forTimeInterval: 0.05)

        for device in devices {
            stopDevice?(device)
            logger.info("MTDeviceStop device=\(deviceLabel(device))")
        }
        logger.info("MultitouchSupport probe complete; frames=\(frameCount)")
    }

    private func load() throws {
        let framework = try loader.loadFramework(at: Self.frameworkPath)
        loaded = framework
        createList = try loader.symbol(named: "MTDeviceCreateList", in: framework, as: MTDeviceCreateListFn.self)
        if let raw = dlsym(framework.handle, "MTDeviceCreateDefault") {
            createDefault = unsafeBitCast(raw, to: MTDeviceCreateDefaultFn.self)
        } else {
            logger.warn("optional symbol missing: MTDeviceCreateDefault")
        }
        registerContactFrameCallback = try loader.symbol(
            named: "MTRegisterContactFrameCallback",
            in: framework,
            as: MTRegisterContactFrameCallbackFn.self
        )
        if let raw = dlsym(framework.handle, "MTUnregisterContactFrameCallback") {
            unregisterContactFrameCallback = unsafeBitCast(raw, to: MTUnregisterContactFrameCallbackFn.self)
        } else {
            logger.warn("optional symbol missing: MTUnregisterContactFrameCallback")
        }
        startDevice = try loader.symbol(named: "MTDeviceStart", in: framework, as: MTDeviceStartFn.self)
        stopDevice = try loader.symbol(named: "MTDeviceStop", in: framework, as: MTDeviceStopFn.self)
        releaseDevice = try loader.symbol(named: "MTDeviceRelease", in: framework, as: MTDeviceReleaseFn.self)
    }

    private func openDevices(source: MultitouchProbeSource) throws {
        devices.removeAll()

        if source == .default || source == .both {
            if let device = createDefault?() {
                appendDevice(device)
                logger.info("MultitouchSupport default device=\(deviceLabel(device))")
            } else {
                logger.warn("MTDeviceCreateDefault returned nil")
            }
        }

        if source == .list || source == .both {
            guard let createList else {
                throw GlidexError.symbolMissing("MTDeviceCreateList not loaded")
            }
            let list = createList()?.takeUnretainedValue()
            guard let list else {
                throw GlidexError.unsupported("MTDeviceCreateList returned nil")
            }
            deviceList = list

            for index in 0..<CFArrayGetCount(list) {
                guard let value = CFArrayGetValueAtIndex(list, index) else {
                    continue
                }
                appendDevice(MTDeviceRef(mutating: value))
            }
        }

        logger.info("MultitouchSupport devices=\(devices.count)")
        for device in devices {
            logger.info("device=\(deviceLabel(device))")
        }
    }

    private func appendDevice(_ device: MTDeviceRef) {
        guard !devices.contains(where: { $0 == device }) else {
            return
        }
        devices.append(device)
    }

    private func handleFrame(device: MTDeviceRef?, contacts: UnsafeMutableRawPointer?, count: Int32, timestamp: Double, frame: Int32) {
        printLock.lock()
        defer { printLock.unlock() }

        frameCount += 1
        let label = device.map(deviceLabel) ?? "nil"
        logger.info("raw_touch frame=\(frame) callbackTimestamp=\(timestamp) device=\(label) contacts=\(count)")

        guard let contacts, count > 0 else {
            return
        }

        let contactBuffer = contacts.bindMemory(to: MTContact.self, capacity: Int(count))
        for index in 0..<Int(count) {
            let contact = contactBuffer[index]
            logger.info(
                "  contact[\(index)] id=\(contact.identifier) state=\(contact.state) " +
                "normPos=(\(format(contact.normalized.position.x)),\(format(contact.normalized.position.y))) " +
                "normVel=(\(format(contact.normalized.velocity.x)),\(format(contact.normalized.velocity.y))) " +
                "size=\(format(contact.size)) major=\(format(contact.majorAxis)) minor=\(format(contact.minorAxis)) " +
                "angle=\(format(contact.angle)) contactFrame=\(contact.frame) contactTimestamp=\(contact.timestamp)"
            )
        }
    }

    private func deviceLabel(_ device: MTDeviceRef) -> String {
        return String(describing: device)
    }

    private func format(_ value: Float) -> String {
        String(format: "%.4f", value)
    }

    private static let contactFrameCallback: ContactFrameCallback = { device, contacts, count, timestamp, frame in
        activeLock.lock()
        let probe = activeProbe
        activeLock.unlock()
        probe?.handleFrame(device: device, contacts: contacts, count: count, timestamp: timestamp, frame: frame)
        return 0
    }
}

public final class MultitouchSupportRawTouchStream: @unchecked Sendable {
    private typealias MTDeviceRef = UnsafeMutableRawPointer
    private typealias ContactFrameCallback = @convention(c) (
        MTDeviceRef?,
        UnsafeMutableRawPointer?,
        Int32,
        Double,
        Int32
    ) -> Int32
    private typealias MTDeviceCreateListFn = @convention(c) () -> Unmanaged<CFArray>?
    private typealias MTDeviceCreateDefaultFn = @convention(c) () -> MTDeviceRef?
    private typealias MTRegisterContactFrameCallbackFn = @convention(c) (MTDeviceRef?, ContactFrameCallback?) -> Void
    private typealias MTUnregisterContactFrameCallbackFn = @convention(c) (MTDeviceRef?, ContactFrameCallback?) -> Void
    private typealias MTDeviceStartFn = @convention(c) (MTDeviceRef?, Int32) -> Void
    private typealias MTDeviceStopFn = @convention(c) (MTDeviceRef?) -> Void

    private static let frameworkPath = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
    private static let activeLock = NSLock()
    private nonisolated(unsafe) static var activeStream: MultitouchSupportRawTouchStream?

    private let logger: Logger
    private let loader: PrivateFrameworkLoader
    private let handler: @Sendable (RawTouchFrame) -> Void
    private var framework: PrivateFrameworkHandle?
    private var createList: MTDeviceCreateListFn?
    private var createDefault: MTDeviceCreateDefaultFn?
    private var registerContactFrameCallback: MTRegisterContactFrameCallbackFn?
    private var unregisterContactFrameCallback: MTUnregisterContactFrameCallbackFn?
    private var startDevice: MTDeviceStartFn?
    private var stopDevice: MTDeviceStopFn?
    private var devices: [MTDeviceRef] = []
    private var deviceList: CFArray?
    private let lock = NSLock()
    private var isStarted = false

    public init(logger: Logger, handler: @escaping @Sendable (RawTouchFrame) -> Void) {
        self.logger = logger
        self.loader = PrivateFrameworkLoader(logger: logger)
        self.handler = handler
    }

    deinit {
        stop()
    }

    public func start(source: MultitouchProbeSource = .default, mode: Int32 = 0) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isStarted else { return }

        try load()
        try openDevices(source: source)
        guard !devices.isEmpty else {
            throw GlidexError.unsupported("MultitouchSupport returned no devices")
        }

        Self.activeLock.lock()
        Self.activeStream = self
        Self.activeLock.unlock()

        for device in devices {
            registerContactFrameCallback?(device, Self.contactFrameCallback)
            startDevice?(device, mode)
            logger.info("raw touch stream started device=\(deviceLabel(device))")
        }
        isStarted = true
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard isStarted else { return }

        for device in devices {
            unregisterContactFrameCallback?(device, Self.contactFrameCallback)
        }
        Thread.sleep(forTimeInterval: 0.05)
        for device in devices {
            stopDevice?(device)
            logger.info("raw touch stream stopped device=\(deviceLabel(device))")
        }

        Self.activeLock.lock()
        if Self.activeStream === self {
            Self.activeStream = nil
        }
        Self.activeLock.unlock()

        devices.removeAll()
        deviceList = nil
        isStarted = false
    }

    private func load() throws {
        let framework = try loader.loadFramework(at: Self.frameworkPath)
        self.framework = framework
        createList = try loader.symbol(named: "MTDeviceCreateList", in: framework, as: MTDeviceCreateListFn.self)
        if let raw = dlsym(framework.handle, "MTDeviceCreateDefault") {
            createDefault = unsafeBitCast(raw, to: MTDeviceCreateDefaultFn.self)
        }
        registerContactFrameCallback = try loader.symbol(
            named: "MTRegisterContactFrameCallback",
            in: framework,
            as: MTRegisterContactFrameCallbackFn.self
        )
        if let raw = dlsym(framework.handle, "MTUnregisterContactFrameCallback") {
            unregisterContactFrameCallback = unsafeBitCast(raw, to: MTUnregisterContactFrameCallbackFn.self)
        }
        startDevice = try loader.symbol(named: "MTDeviceStart", in: framework, as: MTDeviceStartFn.self)
        stopDevice = try loader.symbol(named: "MTDeviceStop", in: framework, as: MTDeviceStopFn.self)
    }

    private func openDevices(source: MultitouchProbeSource) throws {
        devices.removeAll()

        if source == .default || source == .both, let device = createDefault?() {
            appendDevice(device)
        }

        if source == .list || source == .both {
            guard let createList else {
                throw GlidexError.symbolMissing("MTDeviceCreateList not loaded")
            }
            guard let list = createList()?.takeUnretainedValue() else {
                throw GlidexError.unsupported("MTDeviceCreateList returned nil")
            }
            deviceList = list

            for index in 0..<CFArrayGetCount(list) {
                guard let value = CFArrayGetValueAtIndex(list, index) else { continue }
                appendDevice(MTDeviceRef(mutating: value))
            }
        }

        logger.info("raw touch stream devices=\(devices.count)")
    }

    private func appendDevice(_ device: MTDeviceRef) {
        guard !devices.contains(where: { $0 == device }) else { return }
        devices.append(device)
    }

    private func handleFrame(contacts: UnsafeMutableRawPointer?, count: Int32, timestamp: Double, frame: Int32) {
        let rawContacts: [RawTouchContact]
        if let contacts, count > 0 {
            let contactBuffer = contacts.bindMemory(to: MTContact.self, capacity: Int(count))
            rawContacts = (0..<Int(count)).map { index in
                let contact = contactBuffer[index]
                return RawTouchContact(
                    identifier: contact.identifier,
                    state: contact.state,
                    normalizedPosition: CGPoint(
                        x: CGFloat(contact.normalized.position.x),
                        y: CGFloat(contact.normalized.position.y)
                    ),
                    normalizedVelocity: CGPoint(
                        x: CGFloat(contact.normalized.velocity.x),
                        y: CGFloat(contact.normalized.velocity.y)
                    ),
                    size: contact.size
                )
            }
        } else {
            rawContacts = []
        }
        handler(RawTouchFrame(timestamp: timestamp, frame: frame, contacts: rawContacts))
    }

    private func deviceLabel(_ device: MTDeviceRef) -> String {
        String(describing: device)
    }

    private static let contactFrameCallback: ContactFrameCallback = { _, contacts, count, timestamp, frame in
        activeLock.lock()
        let stream = activeStream
        activeLock.unlock()
        stream?.handleFrame(contacts: contacts, count: count, timestamp: timestamp, frame: frame)
        return 0
    }
}
