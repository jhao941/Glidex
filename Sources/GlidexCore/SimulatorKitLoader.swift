import CGlidexShim
import Foundation

final class SimulatorKitLoader {
    typealias IndigoHIDMessageForMouseNSEventFn = @convention(c) (
        UnsafePointer<CGPoint>?,
        UnsafePointer<CGPoint>?,
        UInt64,
        UInt64,
        CGSize,
        UInt64
    ) -> UnsafeMutableRawPointer?

    typealias IndigoHIDMessageForScrollEventFn = @convention(c) (
        UInt32,
        Double,
        Double,
        Double,
        UInt64
    ) -> UnsafeMutableRawPointer?

    typealias IndigoHIDTargetForScreenFn = @convention(c) (AnyObject) -> UInt64

    let logger: Logger
    let loader: PrivateFrameworkLoader
    private var frameworkPath: String

    private(set) var framework: PrivateFrameworkHandle?

    init(logger: Logger, loader: PrivateFrameworkLoader) {
        self.logger = logger
        self.loader = loader
        self.frameworkPath = DeveloperDirectoryResolver().resolve(hostBundleURL: nil)?.simulatorKitPath
            ?? "/Applications/Xcode.app/Contents/Developer/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit"
    }

    func useFramework(at path: String) throws {
        switch SimulatorKitFrameworkSwitch.decide(loadedPath: framework?.path, requestedPath: path) {
        case .useRequested:
            break
        case .alreadySelected:
            return
        case let .incompatibleLoadedFramework(loadedPath):
            throw GlidexError.frameworkLoadFailed(
                "SimulatorKit is already loaded from \(loadedPath); switching to \(path) requires restarting Glidex"
            )
        }
        guard frameworkPath != path else { return }
        frameworkPath = path
        framework = nil
    }

    func load() throws {
        let loadedFramework = try loader.loadFramework(at: frameworkPath)
        let mouseFactory = try loader.symbol(
            named: "IndigoHIDMessageForMouseNSEvent",
            in: loadedFramework,
            as: IndigoHIDMessageForMouseNSEventFn.self
        )
        st_set_indigo_mouse_factory(unsafeBitCast(mouseFactory, to: UnsafeMutableRawPointer.self))
        framework = loadedFramework
    }

    func probe() throws {
        try load()

        logClass("SimulatorKit.SimDeviceLegacyHIDClient", selectors: [
            ("initWithDevice:error:", false),
            ("sendWithMessage:freeWhenDone:completionQueue:completion:", false),
        ])
        logClass("SimulatorKit.SimDeviceScreen", selectors: [
            ("initWithDevice:screenID:", false),
            ("screen", false),
            ("screenID", false),
            ("isDefault", false),
        ])
        logClass("SimulatorKit.SimDisplayView", selectors: [
            ("setDevice:", false),
            ("device", false),
        ])
        logClass("SimulatorKit.SimDigitizerInputView", selectors: [
            ("initWithFrame:", false),
            ("delegate", false),
            ("setDelegate:", false),
            ("isEnabled", false),
            ("setEnabled:", false),
        ])

        let exportedSymbols = [
            "_IndigoHIDMessageForMouseNSEvent",
            "_IndigoHIDMessageForScrollEvent",
            "_IndigoHIDTargetForScreen",
        ]

        guard let framework else {
            return
        }
        for symbol in exportedSymbols {
            if dlsym(framework.handle, symbol) != nil {
                logger.info("exported symbol found: \(symbol)")
            } else {
                logger.warn("exported symbol missing: \(symbol)")
            }
        }
    }

    func indigoMouseFactory() throws -> IndigoHIDMessageForMouseNSEventFn {
        try load()
        guard let framework else {
            throw GlidexError.frameworkLoadFailed("SimulatorKit framework not loaded")
        }
        return try loader.symbol(
            named: "IndigoHIDMessageForMouseNSEvent",
            in: framework,
            as: IndigoHIDMessageForMouseNSEventFn.self
        )
    }

    func indigoScrollFactory() throws -> IndigoHIDMessageForScrollEventFn {
        try load()
        guard let framework else {
            throw GlidexError.frameworkLoadFailed("SimulatorKit framework not loaded")
        }
        return try loader.symbol(
            named: "IndigoHIDMessageForScrollEvent",
            in: framework,
            as: IndigoHIDMessageForScrollEventFn.self
        )
    }

    func indigoTargetForScreen() throws -> IndigoHIDTargetForScreenFn {
        try load()
        guard let framework else {
            throw GlidexError.frameworkLoadFailed("SimulatorKit framework not loaded")
        }
        return try loader.symbol(named: "IndigoHIDTargetForScreen", in: framework, as: IndigoHIDTargetForScreenFn.self)
    }

    private func logClass(_ className: String, selectors: [(String, Bool)]) {
        guard let cls = loader.classNamed(className) else {
            logger.warn("SimulatorKit class missing: \(className)")
            return
        }
        logger.info("SimulatorKit class found: \(className)")
        let selectorNames = ObjCRuntime.selectorNames(for: cls)
        logger.debug("\(className) selectors: \(selectorNames.prefix(40).joined(separator: ", "))")
        for (selector, isClassMethod) in selectors {
            if let encoding = ObjCRuntime.typeEncoding(for: cls, selector: selector, isClassMethod: isClassMethod) {
                logger.info("type_encoding \(className) \(selector) = \(encoding)")
            } else {
                logger.warn("type_encoding missing \(className) \(selector)")
            }
        }
    }
}
