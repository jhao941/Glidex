import CoreFoundation
import Foundation

public protocol RawTouchStream: AnyObject {
    func start(source: MultitouchProbeSource, mode: Int32) throws
    func stop()
}

public final class MultitouchSupportRawTouchStream: RawTouchStream, @unchecked Sendable {
    private static let activeLock = NSLock()
    private nonisolated(unsafe) static var activeStream: MultitouchSupportRawTouchStream?

    private let logger: Logger
    private let bindings: MultitouchSupportBindings
    private let handler: @Sendable (RawTouchFrame) -> Void
    private var devices: [MTDeviceRef] = []
    private var deviceList: CFArray?
    private let lock = NSLock()
    private var isStarted = false

    public init(logger: Logger, handler: @escaping @Sendable (RawTouchFrame) -> Void) {
        self.logger = logger
        self.bindings = MultitouchSupportBindings(
            logger: logger,
            loader: PrivateFrameworkLoader(logger: logger)
        )
        self.handler = handler
    }

    deinit {
        stop()
    }

    public func start(source: MultitouchProbeSource = .default, mode: Int32 = 0) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isStarted else { return }

        try bindings.load()
        try openDevices(source: source)
        guard !devices.isEmpty else {
            throw GlidexError.unsupported("MultitouchSupport returned no devices")
        }

        Self.activeLock.lock()
        Self.activeStream = self
        Self.activeLock.unlock()

        for device in devices {
            bindings.registerCallback?(device, Self.contactFrameCallback)
            bindings.startDevice?(device, mode)
            logger.info("raw touch stream started device=\(deviceLabel(device))")
        }
        isStarted = true
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard isStarted else { return }

        for device in devices {
            bindings.unregisterCallback?(device, Self.contactFrameCallback)
        }
        Thread.sleep(forTimeInterval: 0.05)
        for device in devices {
            bindings.stopDevice?(device)
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

    private func openDevices(source: MultitouchProbeSource) throws {
        devices.removeAll()
        if source == .default || source == .both, let device = bindings.createDefault?() {
            appendDevice(device)
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
        logger.info("raw touch stream devices=\(devices.count)")
    }

    private func appendDevice(_ device: MTDeviceRef) {
        guard !devices.contains(where: { $0 == device }) else { return }
        devices.append(device)
    }

    private func handleFrame(contacts: UnsafeMutableRawPointer?, count: Int32, timestamp: Double, frame: Int32) {
        let rawContacts: [RawTouchContact]
        if let contacts, count > 0 {
            let buffer = contacts.bindMemory(to: MTContact.self, capacity: Int(count))
            rawContacts = (0..<Int(count)).map { index in
                let contact = buffer[index]
                return RawTouchContact(
                    identifier: contact.identifier,
                    state: contact.state,
                    normalizedPosition: NormalizedTouchPoint(
                        x: CGFloat(contact.normalized.position.x),
                        y: CGFloat(contact.normalized.position.y)
                    ),
                    normalizedVelocity: NormalizedTouchVector(
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

    private static let contactFrameCallback: MTContactFrameCallback = { _, contacts, count, timestamp, frame in
        activeLock.lock()
        let stream = activeStream
        activeLock.unlock()
        stream?.handleFrame(contacts: contacts, count: count, timestamp: timestamp, frame: frame)
        return 0
    }
}
