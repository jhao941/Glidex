import CoreFoundation
import Foundation

typealias MTDeviceRef = UnsafeMutableRawPointer
typealias MTContactFrameCallback = @convention(c) (
    MTDeviceRef?,
    UnsafeMutableRawPointer?,
    Int32,
    Double,
    Int32
) -> Int32

final class MultitouchSupportBindings {
    typealias DeviceCreateList = @convention(c) () -> Unmanaged<CFArray>?
    typealias DeviceCreateDefault = @convention(c) () -> MTDeviceRef?
    typealias RegisterCallback = @convention(c) (MTDeviceRef?, MTContactFrameCallback?) -> Void
    typealias UnregisterCallback = @convention(c) (MTDeviceRef?, MTContactFrameCallback?) -> Void
    typealias StartDevice = @convention(c) (MTDeviceRef?, Int32) -> Void
    typealias StopDevice = @convention(c) (MTDeviceRef?) -> Void
    typealias ReleaseDevice = @convention(c) (MTDeviceRef?) -> Void

    private static let frameworkPath = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"

    private let logger: Logger
    private let loader: PrivateFrameworkLoader
    private var framework: PrivateFrameworkHandle?

    private(set) var createList: DeviceCreateList?
    private(set) var createDefault: DeviceCreateDefault?
    private(set) var registerCallback: RegisterCallback?
    private(set) var unregisterCallback: UnregisterCallback?
    private(set) var startDevice: StartDevice?
    private(set) var stopDevice: StopDevice?
    private(set) var releaseDevice: ReleaseDevice?

    init(logger: Logger, loader: PrivateFrameworkLoader) {
        self.logger = logger
        self.loader = loader
    }

    func load() throws {
        guard framework == nil else { return }
        let framework = try loader.loadFramework(at: Self.frameworkPath)
        self.framework = framework
        createList = try loader.symbol(named: "MTDeviceCreateList", in: framework, as: DeviceCreateList.self)
        createDefault = optionalSymbol(named: "MTDeviceCreateDefault", in: framework, as: DeviceCreateDefault.self)
        registerCallback = try loader.symbol(named: "MTRegisterContactFrameCallback", in: framework, as: RegisterCallback.self)
        unregisterCallback = optionalSymbol(named: "MTUnregisterContactFrameCallback", in: framework, as: UnregisterCallback.self)
        startDevice = try loader.symbol(named: "MTDeviceStart", in: framework, as: StartDevice.self)
        stopDevice = try loader.symbol(named: "MTDeviceStop", in: framework, as: StopDevice.self)
        releaseDevice = optionalSymbol(named: "MTDeviceRelease", in: framework, as: ReleaseDevice.self)
    }

    private func optionalSymbol<T>(named name: String, in framework: PrivateFrameworkHandle, as type: T.Type) -> T? {
        guard let raw = dlsym(framework.handle, name) else {
            logger.warn("optional symbol missing: \(name)")
            return nil
        }
        return unsafeBitCast(raw, to: type)
    }
}
