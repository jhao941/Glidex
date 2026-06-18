import Foundation

final class BootedSimulatorResolver {
    private let logger: Logger
    private let loader: PrivateFrameworkLoader
    private let coreSimulatorFramework = "/Library/Developer/PrivateFrameworks/CoreSimulator.framework/CoreSimulator"
    private var developerDirectory: String

    init(logger: Logger, loader: PrivateFrameworkLoader) {
        self.logger = logger
        self.loader = loader
        self.developerDirectory = DeveloperDirectoryResolver().resolve(hostBundleURL: nil)?.developerDirectory
            ?? "/Applications/Xcode.app/Contents/Developer"
    }

    func useDeveloperDirectory(_ path: String) {
        developerDirectory = path
    }

    func listBootedSimulators() throws -> [BootedSimulatorRecord] {
        _ = try? loader.loadFramework(at: coreSimulatorFramework)
        try probeCoreSimulatorClasses()
        return try listViaSimctl()
    }

    func resolveSimDevice(udid: String) throws -> AnyObject {
        _ = try loader.loadFramework(at: coreSimulatorFramework)

        guard let simServiceContextClass = loader.classNamed("SimServiceContext") else {
            throw GlidexError.classMissing("CoreSimulator class missing: SimServiceContext")
        }

        let sharedSelector = loader.selector(named: "sharedServiceContextForDeveloperDir:error:")
        logTypeEncoding(simServiceContextClass, selector: "sharedServiceContextForDeveloperDir:error:", isClassMethod: true)
        let developerDir = developerDirectory as NSString
        let contextResult = ObjCInvoker.withOutObject { errorPointer in
            ObjCInvoker.classObjectPointer(
                simServiceContextClass,
                sharedSelector,
                object: developerDir,
                pointer: errorPointer
            )
        }
        guard let context = contextResult.result else {
            let contextErrorObject = contextResult.object
            let contextError = contextErrorObject as? NSError
            throw GlidexError.commandFailed("failed to acquire SimServiceContext: \(contextError?.localizedDescription ?? "nil")")
        }
        logger.info("resolved SimServiceContext: \(type(of: context))")

        let defaultSetSelector = loader.selector(named: "defaultDeviceSetWithError:")
        logTypeEncoding(simServiceContextClass, selector: "defaultDeviceSetWithError:")
        let deviceSetResult = ObjCInvoker.withOutObject { errorPointer in
            ObjCInvoker.object(context, defaultSetSelector, pointer: errorPointer)
        }
        guard let deviceSet = deviceSetResult.result else {
            let deviceSetErrorObject = deviceSetResult.object
            let deviceSetError = deviceSetErrorObject as? NSError
            throw GlidexError.commandFailed("failed to acquire default SimDeviceSet: \(deviceSetError?.localizedDescription ?? "nil")")
        }
        logger.info("resolved SimDeviceSet: \(type(of: deviceSet))")

        let devicesSelector = loader.selector(named: "devicesByUDID")
        logTypeEncoding(type(of: deviceSet), selector: "devicesByUDID")
        guard let devicesByUDID = ObjCInvoker.object(deviceSet, devicesSelector) as? NSDictionary else {
            throw GlidexError.commandFailed("failed to fetch devicesByUDID")
        }

        if let uuid = UUID(uuidString: udid), let direct = devicesByUDID[uuid] as AnyObject? {
            logger.info("resolved SimDevice via UUID key")
            return direct
        }
        if let stringKey = devicesByUDID[udid] as AnyObject? {
            logger.info("resolved SimDevice via string UDID key")
            return stringKey
        }

        let keys = devicesByUDID.allKeys.map { "\($0)" }.sorted().joined(separator: ", ")
        throw GlidexError.simulatorNotFound("failed to resolve SimDevice for \(udid); dictionary keys: \(keys)")
    }

    func probeCoreSimulatorClasses() throws {
        logClass("SimServiceContext", interestingSelectors: [
            ("sharedServiceContextForDeveloperDir:error:", true),
            ("defaultDeviceSetWithError:", false),
        ])
        logClass("SimDeviceSet", interestingSelectors: [
            ("devicesByUDID", false),
            ("availableDevices", false),
        ])
        logClass("SimDevice", interestingSelectors: [
            ("UDID", false),
            ("name", false),
            ("deviceType", false),
            ("runtime", false),
            ("state", false),
            ("io", false),
            ("mainScreen", false),
        ])
        logClass("SimDeviceIO", interestingSelectors: [
            ("mainScreen", false),
            ("displayRenderable", false),
            ("framebufferService", false),
        ])
    }

    private func listViaSimctl() throws -> [BootedSimulatorRecord] {
        let data = try ProcessRunner.run("/usr/bin/xcrun", arguments: ["simctl", "list", "devices", "booted", "--json"])
        let decoded = try JSONDecoder().decode(SimctlListResponse.self, from: data)

        var records: [BootedSimulatorRecord] = []
        for (runtime, devices) in decoded.devices {
            for device in devices where device.state == "Booted" {
                records.append(
                    BootedSimulatorRecord(
                        name: device.name,
                        udid: device.udid,
                        runtime: runtime,
                        deviceType: device.deviceTypeSummary,
                        screenSize: nil,
                        nativeResolution: nil,
                        scale: nil,
                        dataPath: device.dataPath,
                        source: "simctl-json"
                    )
                )
            }
        }

        records.sort { $0.name < $1.name }
        return records
    }

    private func logClass(_ name: String, interestingSelectors: [(String, Bool)]) {
        guard let cls = loader.classNamed(name) else {
            logger.warn("CoreSimulator class missing: \(name)")
            return
        }
        let methods = ObjCRuntime.selectorNames(for: cls)
        logger.info("CoreSimulator class found: \(name)")
        logger.debug("\(name) selectors: \(methods.prefix(20).joined(separator: ", "))")
        for (selector, isClassMethod) in interestingSelectors {
            logTypeEncoding(cls, selector: selector, isClassMethod: isClassMethod)
        }
    }

    private func logTypeEncoding(_ cls: AnyClass, selector: String, isClassMethod: Bool = false) {
        if let encoding = ObjCRuntime.typeEncoding(for: cls, selector: selector, isClassMethod: isClassMethod) {
            logger.info("type_encoding \(NSStringFromClass(cls)) \(selector) = \(encoding)")
        } else {
            logger.warn("type_encoding missing \(NSStringFromClass(cls)) \(selector)")
        }
    }
}
