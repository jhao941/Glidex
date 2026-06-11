import CGlidexShim
import Dispatch
import Foundation

private final class HIDSendCompletionBox: @unchecked Sendable {
    let handler: @Sendable (String?) -> Void

    init(handler: @escaping @Sendable (String?) -> Void) {
        self.handler = handler
    }
}

private let hidSendCompletion: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> Void = { context, errorCString in
    guard let context else { return }
    let box = Unmanaged<HIDSendCompletionBox>.fromOpaque(context).takeRetainedValue()
    box.handler(errorCString.map(String.init(cString:)))
}

final class SimulatorHIDClient {
    let rawClient: AnyObject

    private let logger: Logger

    init(rawClient: AnyObject, logger: Logger) {
        self.rawClient = rawClient
        self.logger = logger
    }

    static func make(simDevice: AnyObject, simulatorKit: SimulatorKitLoader, logger: Logger) throws -> SimulatorHIDClient {
        try simulatorKit.load()
        guard let hidClientClass = simulatorKit.loader.classNamed("SimulatorKit.SimDeviceLegacyHIDClient") else {
            throw GlidexError.classMissing("SimulatorKit.SimDeviceLegacyHIDClient missing")
        }

        let alloc = NSSelectorFromString("alloc")
        guard let allocated = ObjCInvoker.object(hidClientClass as AnyObject, alloc) else {
            throw GlidexError.commandFailed("failed to alloc SimDeviceLegacyHIDClient")
        }

        let rawClient = try makeRawClient(allocated: allocated, simDevice: simDevice, logger: logger)
        let hidClient = SimulatorHIDClient(rawClient: rawClient, logger: logger)
        hidClient.prepareSessionIfAvailable(simDevice: simDevice)
        return hidClient
    }

    func send(
        message: UnsafeMutableRawPointer,
        waitForCompletion: Bool = true,
        onCompletion: (@Sendable (String?) -> Void)? = nil
    ) {
        let rawPointer = Unmanaged.passUnretained(rawClient).toOpaque()
        let errorCString: UnsafePointer<CChar>?
        var completionContext: UnsafeMutableRawPointer?
        if waitForCompletion {
            errorCString = st_send_hid_message_sync(rawPointer, message, true, 1.0)
            completionContext = nil
        } else {
            completionContext = onCompletion.map {
                Unmanaged.passRetained(HIDSendCompletionBox(handler: $0)).toOpaque()
            }
            errorCString = st_send_hid_message_async(
                rawPointer,
                message,
                true,
                completionContext,
                completionContext == nil ? nil : hidSendCompletion
            )
        }
        if let errorCString {
            defer { free(UnsafeMutableRawPointer(mutating: errorCString)) }
            let message = String(cString: errorCString)
            logger.error("sendWithMessage completion error: \(message)")
            if let completionContext {
                let box = Unmanaged<HIDSendCompletionBox>.fromOpaque(completionContext).takeRetainedValue()
                box.handler(message)
            } else {
                onCompletion?(message)
            }
        } else if waitForCompletion {
            onCompletion?(nil)
        }
    }

    private static func makeRawClient(allocated: AnyObject, simDevice: AnyObject, logger: Logger) throws -> AnyObject {
        let screenSelector = NSSelectorFromString("initWithDevice:screenID:")
        if allocated.responds(to: screenSelector) {
            if let encoding = ObjCRuntime.typeEncoding(for: type(of: allocated), selector: "initWithDevice:screenID:") {
                logger.info("type_encoding \(NSStringFromClass(type(of: allocated))) initWithDevice:screenID: = \(encoding)")
            }
            switch ObjCInvoker.objectObjectUnsignedLongLongCatching(allocated, screenSelector, object: simDevice, value: 1) {
            case let .success(client?):
                logger.info("created HID client via initWithDevice:screenID: screenID=1")
                return client
            case let .failure(message):
                logger.warn("initWithDevice:screenID: threw: \(message); falling back")
            case .success(nil):
                logger.warn("initWithDevice:screenID: returned nil; falling back")
            }
        }

        let sessionSelector = NSSelectorFromString("initWithDevice:sessionResetQueue:error:sessionResetHandler:")
        if allocated.responds(to: sessionSelector) {
            if let encoding = ObjCRuntime.typeEncoding(for: type(of: allocated), selector: "initWithDevice:sessionResetQueue:error:sessionResetHandler:") {
                logger.info("type_encoding \(NSStringFromClass(type(of: allocated))) initWithDevice:sessionResetQueue:error:sessionResetHandler: = \(encoding)")
            }
            let queue = DispatchQueue(label: "glidex.hid.session-reset")
            var errorObject: AnyObject?
            if let client = ObjCInvoker.object(
                allocated,
                sessionSelector,
                object: simDevice,
                object: queue as AnyObject,
                pointer: &errorObject,
                object: nil
            ) {
                logger.info("created HID client via initWithDevice:sessionResetQueue:error:sessionResetHandler:")
                return client
            }
            let error = errorObject as? NSError
            logger.warn("initWithDevice:sessionResetQueue:error:sessionResetHandler: failed: \(error?.localizedDescription ?? "nil"); falling back")
        }

        let initSelector = NSSelectorFromString("initWithDevice:error:")
        var errorObject: AnyObject?
        guard let client = ObjCInvoker.object(allocated, initSelector, object: simDevice, pointer: &errorObject) else {
            let error = errorObject as? NSError
            throw GlidexError.commandFailed("initWithDevice:error: failed: \(error?.localizedDescription ?? "nil")")
        }
        logger.info("created HID client via initWithDevice:error:")
        return client
    }

    private func prepareSessionIfAvailable(simDevice: AnyObject) {
        let connectedSelector = NSSelectorFromString("connected")
        if rawClient.responds(to: connectedSelector) {
            logger.info("HID connected(before)=\(ObjCInvoker.bool(rawClient, connectedSelector))")
        }

        let connectSelector = NSSelectorFromString("connectToDeviceIO:")
        let ioSelector = NSSelectorFromString("io")
        if rawClient.responds(to: connectSelector), let deviceIO = ObjCInvoker.object(simDevice, ioSelector) {
            if let encoding = ObjCRuntime.typeEncoding(for: type(of: rawClient), selector: "connectToDeviceIO:") {
                logger.info("type_encoding \(NSStringFromClass(type(of: rawClient))) connectToDeviceIO: = \(encoding)")
            }
            logger.info("connecting HID client to SimDeviceIO")
            ObjCInvoker.void(rawClient, connectSelector, object: deviceIO)
        } else {
            logger.debug("Skipping connectToDeviceIO: hidClient responds=\(rawClient.responds(to: connectSelector))")
        }

        let resetSelector = NSSelectorFromString("resetHIDSession")
        guard rawClient.responds(to: resetSelector) else {
            logger.debug("SimDeviceLegacyHIDClient has no resetHIDSession selector")
            return
        }
        if rawClient.responds(to: connectedSelector) {
            let connected = ObjCInvoker.bool(rawClient, connectedSelector)
            logger.info("HID connected(after connect)=\(connected)")
            if connected {
                logger.info("resetting HID session before send")
                _ = ObjCInvoker.object(rawClient, resetSelector)
                logger.info("HID connected(after reset)=\(ObjCInvoker.bool(rawClient, connectedSelector))")
            } else {
                logger.warn("skipping resetHIDSession because HID client is not connected")
            }
            return
        }

        logger.debug("connected selector unavailable; skipping resetHIDSession")
    }
}
