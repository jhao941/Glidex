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

public final class MultitouchSupportProbe: @unchecked Sendable {
    private static let activeLock = NSLock()
    private nonisolated(unsafe) static var activeProbe: MultitouchSupportProbe?

    private let logger: Logger
    private let bindings: MultitouchSupportBindings
    private var devices: [MTDeviceRef] = []
    private var deviceList: CFArray?
    private let printLock = NSLock()
    private var frameCount = 0

    init(logger: Logger, loader: PrivateFrameworkLoader) {
        self.logger = logger
        self.bindings = MultitouchSupportBindings(logger: logger, loader: loader)
    }

    public func run(options: MultitouchProbeOptions = MultitouchProbeOptions()) throws {
        try bindings.load()
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
            bindings.registerCallback?(device, Self.contactFrameCallback)
            bindings.startDevice?(device, options.mode)
            logger.info("MTDeviceStart device=\(deviceLabel(device))")
        }

        let deadline = Date().addingTimeInterval(options.duration)
        while Date() < deadline {
            CFRunLoopRunInMode(.defaultMode, min(0.05, deadline.timeIntervalSinceNow), false)
        }

        for device in devices {
            bindings.unregisterCallback?(device, Self.contactFrameCallback)
        }
        Thread.sleep(forTimeInterval: 0.05)
        for device in devices {
            bindings.stopDevice?(device)
            logger.info("MTDeviceStop device=\(deviceLabel(device))")
        }
        logger.info("MultitouchSupport probe complete; frames=\(frameCount)")
    }

    private func openDevices(source: MultitouchProbeSource) throws {
        devices.removeAll()
        if source == .default || source == .both {
            if let device = bindings.createDefault?() {
                appendDevice(device)
                logger.info("MultitouchSupport default device=\(deviceLabel(device))")
            } else {
                logger.warn("MTDeviceCreateDefault returned nil")
            }
        }
        if source == .list || source == .both {
            guard let createList = bindings.createList else {
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

        logger.info("MultitouchSupport devices=\(devices.count)")
        for device in devices {
            logger.info("device=\(deviceLabel(device))")
        }
    }

    private func appendDevice(_ device: MTDeviceRef) {
        guard !devices.contains(where: { $0 == device }) else { return }
        devices.append(device)
    }

    private func handleFrame(
        device: MTDeviceRef?,
        contacts: UnsafeMutableRawPointer?,
        count: Int32,
        timestamp: Double,
        frame: Int32
    ) {
        printLock.lock()
        defer { printLock.unlock() }
        frameCount += 1
        logger.info("raw_touch frame=\(frame) callbackTimestamp=\(timestamp) device=\(device.map(deviceLabel) ?? "nil") contacts=\(count)")
        guard let contacts, count > 0 else { return }

        let buffer = contacts.bindMemory(to: MTContact.self, capacity: Int(count))
        for index in 0..<Int(count) {
            let contact = buffer[index]
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
        String(describing: device)
    }

    private func format(_ value: Float) -> String {
        String(format: "%.4f", value)
    }

    private static let contactFrameCallback: MTContactFrameCallback = { device, contacts, count, timestamp, frame in
        activeLock.lock()
        let probe = activeProbe
        activeLock.unlock()
        probe?.handleFrame(device: device, contacts: contacts, count: count, timestamp: timestamp, frame: frame)
        return 0
    }
}
