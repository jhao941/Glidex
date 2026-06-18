import AppKit
import CGlidexShim
import Dispatch
import Foundation

final class IndigoHIDBackend: @unchecked Sendable {
    private struct DeviceUnitPoint {
        var x: CGFloat
        var y: CGFloat
    }

    private struct RawTouchEvent {
        var touch1: DeviceUnitPoint
        var touch2: DeviceUnitPoint
        var touch2Tag: UInt8
        var phase: UInt8
        var padding0: UInt16
        var padding1: UInt32
        var type: UInt64
        var edge: UInt64
    }

    private struct MainActorObject: @unchecked Sendable {
        var value: AnyObject
    }

    private enum TouchPhase: UInt8 {
        case started = 0
        case touching = 1
        case ended = 2
    }

    private enum MouseEventType: UInt64 {
        case leftMouseDown = 1
        case leftMouseUp = 2
        case leftMouseDragged = 6
    }

    private let logger: Logger
    private let simulatorKit: SimulatorKitLoader
    private let dumpsHIDMessages: Bool

    init(logger: Logger, simulatorKit: SimulatorKitLoader) {
        self.logger = logger
        self.simulatorKit = simulatorKit
        self.dumpsHIDMessages = ProcessInfo.processInfo.environment["GLIDEX_DUMP_HID_MESSAGES"] == "1"
    }

    func probeFactories() throws {
        _ = try simulatorKit.indigoMouseFactory()
        logger.info("resolved IndigoHIDMessageForMouseNSEvent")
        _ = try simulatorKit.indigoScrollFactory()
        logger.info("resolved IndigoHIDMessageForScrollEvent")
        _ = try simulatorKit.indigoTargetForScreen()
        logger.info("resolved IndigoHIDTargetForScreen")
    }

    func attemptTap(on simulator: BootedSimulatorRecord, simDevice: AnyObject, point: CGPoint) throws {
        let hidClient = try SimulatorHIDClient.make(simDevice: simDevice, simulatorKit: simulatorKit, logger: logger)
        let metrics = resolveScreenMetrics(for: simDevice, fallback: simulator)
        logger.info("attempting tap backend=indigo-digitizer-touch simulator=\(simulator.udid)")
        logger.info("coordinate_assumption=device-points point=(\(point.x), \(point.y))")
        logger.info("screen_metrics points=\(Int(metrics.pointSize.width))x\(Int(metrics.pointSize.height)) scale=\(metrics.scale)")
        logger.info("touch_lifecycle=down,optional-delay,up")
        try execute(GestureSynthesizer.tap(point: point), metrics: metrics, hidClient: hidClient)
        logger.info("tap touch sequence completed")
    }

    func attemptDigitizerTap(on simulator: BootedSimulatorRecord, simDevice: AnyObject, point: CGPoint) throws {
        precondition(MemoryLayout<RawTouchEvent>.size == 56)
        precondition(MemoryLayout<RawTouchEvent>.stride == 56)

        let hidClient = try SimulatorHIDClient.make(simDevice: simDevice, simulatorKit: simulatorKit, logger: logger)
        let metrics = resolveScreenMetrics(for: simDevice, fallback: simulator)
        let digitizerView = try makeDigitizerView(simDevice: simDevice, metrics: metrics)
        let touch = DeviceUnitPoint(x: point.x / metrics.pointSize.width, y: point.y / metrics.pointSize.height)

        logger.info("attempting tap backend=swift-simDigitizerInputView simulator=\(simulator.udid)")
        logger.info("coordinate_assumption=device-points point=(\(point.x), \(point.y)) unit=(\(touch.x), \(touch.y))")
        logger.info("touch_event_layout size=\(MemoryLayout<RawTouchEvent>.size) touch1@0 touch2@16 touch2Tag@32 phase@33 type@40 edge@48")

        try sendDigitizerTouchEvent(
            digitizerView: digitizerView,
            hidClient: hidClient.rawClient,
            event: makeTouchEvent(touch1: touch, phase: .started, type: .leftMouseDown)
        )
        Thread.sleep(forTimeInterval: 0.03)
        try sendDigitizerTouchEvent(
            digitizerView: digitizerView,
            hidClient: hidClient.rawClient,
            event: makeTouchEvent(touch1: touch, phase: .touching, type: .leftMouseDragged)
        )
        Thread.sleep(forTimeInterval: 0.03)
        try sendDigitizerTouchEvent(
            digitizerView: digitizerView,
            hidClient: hidClient.rawClient,
            event: makeTouchEvent(touch1: touch, phase: .ended, type: .leftMouseUp)
        )
        logger.info("swift digitizer tap sequence completed")
    }

    func attemptDrag(on simulator: BootedSimulatorRecord, simDevice: AnyObject, from: CGPoint, to: CGPoint, duration: TimeInterval) throws {
        let hidClient = try SimulatorHIDClient.make(simDevice: simDevice, simulatorKit: simulatorKit, logger: logger)
        let metrics = resolveScreenMetrics(for: simDevice, fallback: simulator)
        logger.info("attempting drag backend=indigo-digitizer-touch simulator=\(simulator.udid)")
        logger.info("touch_lifecycle=down,interpolated-down+delay,final-repeat-down,up from=(\(from.x), \(from.y)) to=(\(to.x), \(to.y)) duration=\(duration)")
        try execute(GestureSynthesizer.drag(from: from, to: to, duration: duration), metrics: metrics, hidClient: hidClient)
    }

    func attemptPinch(on simulator: BootedSimulatorRecord, simDevice: AnyObject, center: CGPoint, scale: Double, duration: TimeInterval) throws {
        let hidClient = try SimulatorHIDClient.make(simDevice: simDevice, simulatorKit: simulatorKit, logger: logger)
        let metrics = resolveScreenMetrics(for: simDevice, fallback: simulator)
        logger.info("attempting pinch backend=indigo-two-finger-touch simulator=\(simulator.udid)")
        logger.info("touch_lifecycle=two-finger-down,interpolated-down+delay,final-repeat-down,up center=(\(center.x), \(center.y)) scale=\(scale) duration=\(duration)")
        try execute(GestureSynthesizer.pinch(center: center, scale: scale, duration: duration), metrics: metrics, hidClient: hidClient)
    }

    func makeLiveTouchSession(on simulator: BootedSimulatorRecord, simDevice: AnyObject) throws -> LiveTouchSession {
        let hidClient = try SimulatorHIDClient.make(simDevice: simDevice, simulatorKit: simulatorKit, logger: logger)
        let metrics = resolveScreenMetrics(for: simDevice, fallback: simulator)
        logger.info("created live touch session simulator=\(simulator.udid) screen_metrics points=\(Int(metrics.pointSize.width))x\(Int(metrics.pointSize.height)) scale=\(metrics.scale)")
        return LiveTouchSession(
            hidClient: hidClient,
            metrics: metrics,
            logger: logger,
            dumpsHIDMessages: dumpsHIDMessages
        )
    }

    func makeLiveTwoFingerTouchSession(on simulator: BootedSimulatorRecord, simDevice: AnyObject) throws -> LiveTwoFingerTouchSession {
        let hidClient = try SimulatorHIDClient.make(simDevice: simDevice, simulatorKit: simulatorKit, logger: logger)
        let metrics = resolveScreenMetrics(for: simDevice, fallback: simulator)
        logger.info("created live two-finger touch session simulator=\(simulator.udid) screen_metrics points=\(Int(metrics.pointSize.width))x\(Int(metrics.pointSize.height)) scale=\(metrics.scale)")
        return LiveTwoFingerTouchSession(
            hidClient: hidClient,
            metrics: metrics,
            logger: logger,
            dumpsHIDMessages: dumpsHIDMessages
        )
    }

    func makeLiveDirectTouchSession(on simulator: BootedSimulatorRecord, simDevice: AnyObject) throws -> LiveDirectTouchSession {
        let hidClient = try SimulatorHIDClient.make(simDevice: simDevice, simulatorKit: simulatorKit, logger: logger)
        let metrics = resolveScreenMetrics(for: simDevice, fallback: simulator)
        logger.info("created live Direct Touch session simulator=\(simulator.udid) screen_metrics points=\(Int(metrics.pointSize.width))x\(Int(metrics.pointSize.height)) scale=\(metrics.scale)")
        return LiveDirectTouchSession(
            hidClient: hidClient,
            metrics: metrics,
            logger: logger,
            dumpsHIDMessages: dumpsHIDMessages
        )
    }

    private func makeDigitizerView(simDevice: AnyObject, metrics: ScreenMetrics) throws -> AnyObject {
        let simDevice = MainActorObject(value: simDevice)
        return try syncOnMainActor {
            MainActorObject(value: try makeDigitizerViewOnMainActor(simDevice: simDevice.value, metrics: metrics))
        }.value
    }

    private func syncOnMainActor<T: Sendable>(_ body: @MainActor () throws -> T) throws -> T {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated(body)
        }

        return try DispatchQueue.main.sync {
            try MainActor.assumeIsolated(body)
        }
    }

    @MainActor
    private func makeDigitizerViewOnMainActor(simDevice: AnyObject, metrics: ScreenMetrics) throws -> AnyObject {
        try simulatorKit.load()
        let frame = CGRect(origin: .zero, size: metrics.pointSize)

        if let displayViewClass = simulatorKit.loader.classNamed("SimulatorKit.SimDisplayView"),
           let displayView = allocateAndInitFrame(classObject: displayViewClass, frame: frame) as? NSView {
            ObjCInvoker.void(displayView, NSSelectorFromString("setDevice:"), object: simDevice)
            try connectDisplayViewIfPossible(displayView, simDevice: simDevice)
            if let digitizerView = firstSubview(in: displayView, matchingClassName: "SimDigitizerInputView") {
                logger.info("using SimDigitizerInputView from SimDisplayView hierarchy")
                logViewHierarchy(displayView)
                return digitizerView
            }
            logger.warn("SimDisplayView hierarchy did not contain SimDigitizerInputView; falling back to bare input view")
            logViewHierarchy(displayView)
        } else {
            logger.warn("failed to create SimDisplayView; falling back to bare SimDigitizerInputView")
        }

        guard let digitizerClass = simulatorKit.loader.classNamed("SimulatorKit.SimDigitizerInputView"),
              let digitizerView = allocateAndInitFrame(classObject: digitizerClass, frame: frame) else {
            throw GlidexError.classMissing("SimulatorKit.SimDigitizerInputView missing or initWithFrame: failed")
        }
        return digitizerView
    }

    @MainActor
    private func connectDisplayViewIfPossible(_ displayView: NSView, simDevice: AnyObject) throws {
        guard ProcessInfo.processInfo.environment["GLIDEX_ENABLE_DISPLAY_CONNECT"] == "1" else {
            logger.info("skipping SimDisplayView.connect probe; set GLIDEX_ENABLE_DISPLAY_CONNECT=1 to try the experimental SwiftCC connect trampoline")
            return
        }
        guard let screen = makeSimDeviceScreen(simDevice: simDevice, screenID: 1) else {
            logger.warn("failed to create SimDeviceScreen(screenID: 1); using display view without connect")
            return
        }
        guard let framework = simulatorKit.framework else {
            throw GlidexError.frameworkLoadFailed("SimulatorKit framework not loaded")
        }
        let symbol = "$s12SimulatorKit14SimDisplayViewC7connect6screen6inputsyAA0C12DeviceScreenC_AC0j5InputI0VtKFTj"
        guard let function = dlsym(framework.handle, symbol) else {
            logger.warn("Swift SimDisplayView.connect symbol missing; using display view without connect")
            return
        }
        logger.info("calling Swift SimDisplayView.connect(screen:inputs:) screenID=1 inputs=all")
        st_call_swift_display_connect(
            function,
            Unmanaged.passUnretained(displayView).toOpaque(),
            Unmanaged.passUnretained(screen).toOpaque(),
            UInt.max
        )
    }

    @MainActor
    private func makeSimDeviceScreen(simDevice: AnyObject, screenID: UInt64) -> AnyObject? {
        guard let screenClass = simulatorKit.loader.classNamed("SimulatorKit.SimDeviceScreen"),
              let allocated = ObjCInvoker.object(screenClass as AnyObject, NSSelectorFromString("alloc")) else {
            return nil
        }
        return ObjCInvoker.objectObjectUnsignedLongLong(
            allocated,
            NSSelectorFromString("initWithDevice:screenID:"),
            object: simDevice,
            value: screenID
        )
    }

    @MainActor
    private func allocateAndInitFrame(classObject: AnyClass, frame: CGRect) -> AnyObject? {
        guard let allocated = ObjCInvoker.object(classObject as AnyObject, NSSelectorFromString("alloc")) else {
            return nil
        }
        return ObjCInvoker.objectCGRect(allocated, NSSelectorFromString("initWithFrame:"), rect: frame)
    }

    @MainActor
    private func firstSubview(in root: NSView, matchingClassName needle: String) -> AnyObject? {
        if NSStringFromClass(type(of: root)).contains(needle) {
            return root
        }
        for subview in root.subviews {
            if let match = firstSubview(in: subview, matchingClassName: needle) {
                return match
            }
        }
        return nil
    }

    @MainActor
    private func logViewHierarchy(_ root: NSView, depth: Int = 0) {
        let indent = String(repeating: "  ", count: depth)
        logger.info("view_hierarchy \(indent)\(NSStringFromClass(type(of: root))) frame=\(root.frame)")
        for subview in root.subviews {
            logViewHierarchy(subview, depth: depth + 1)
        }
    }

    private func makeTouchEvent(touch1: DeviceUnitPoint, phase: TouchPhase, type: MouseEventType) -> RawTouchEvent {
        RawTouchEvent(
            touch1: touch1,
            touch2: DeviceUnitPoint(x: 0, y: 0),
            touch2Tag: 1,
            phase: phase.rawValue,
            padding0: 0,
            padding1: 0,
            type: type.rawValue,
            edge: 0
        )
    }

    private func sendDigitizerTouchEvent(digitizerView: AnyObject, hidClient: AnyObject, event: RawTouchEvent) throws {
        try simulatorKit.load()
        guard let framework = simulatorKit.framework else {
            throw GlidexError.frameworkLoadFailed("SimulatorKit framework not loaded")
        }
        let symbol = "$s12SimulatorKit24SimDeviceLegacyHIDClientC21simDigitizerInputView_10touchEventyAA0chiJ0C_AG05TouchL0VtF"
        guard let function = dlsym(framework.handle, symbol) else {
            throw GlidexError.symbolMissing("swift symbol missing: \(symbol)")
        }

        var mutableEvent = event
        withUnsafePointer(to: &mutableEvent) { pointer in
            logger.info("calling Swift simDigitizerInputView(_:touchEvent:) phase=\(event.phase) type=\(event.type)")
            st_call_swift_digitizer_touch(
                function,
                Unmanaged.passUnretained(digitizerView).toOpaque(),
                UnsafeRawPointer(pointer),
                Unmanaged.passUnretained(hidClient).toOpaque()
            )
        }
    }

    private func execute(_ steps: [GestureSynthesizer.Step], metrics: ScreenMetrics, hidClient: SimulatorHIDClient) throws {
        for step in steps {
            switch step {
            case let .singleTouch(point, direction, description):
                let message = try TouchMessageBuilder.singleTouch(point: point, screenPointSize: metrics.pointSize, direction: direction)
                logger.info(description)
                logMessageIfEnabled(message)
                hidClient.send(message: message)
            case let .twoFingerTouch(finger1, finger2, direction, description):
                let message = try TouchMessageBuilder.twoFingerTouch(
                    finger1: finger1,
                    finger2: finger2,
                    screenPointSize: metrics.pointSize,
                    direction: direction
                )
                logger.info(description)
                logMessageIfEnabled(message)
                hidClient.send(message: message)
            case let .delay(duration, description):
                logger.info(description)
                Thread.sleep(forTimeInterval: duration)
            }
        }
    }

    private func logMessageIfEnabled(_ message: UnsafeMutableRawPointer) {
        guard dumpsHIDMessages else { return }
        logger.info("message \(TouchMessageBuilder.describe(message))")
    }

    func resolveScreenMetrics(for simDevice: AnyObject, fallback simulator: BootedSimulatorRecord) -> ScreenMetrics {
        let deviceTypeSelector = NSSelectorFromString("deviceType")
        let sizeSelector = NSSelectorFromString("mainScreenSize")
        let scaleSelector = NSSelectorFromString("mainScreenScale")

        if let deviceType = ObjCInvoker.object(simDevice, deviceTypeSelector) {
            let deviceTypeClass: AnyClass = type(of: deviceType)
            if let sizeEncoding = ObjCRuntime.typeEncoding(for: deviceTypeClass, selector: "mainScreenSize") {
                logger.info("type_encoding \(NSStringFromClass(deviceTypeClass)) mainScreenSize = \(sizeEncoding)")
            }
            if let scaleEncoding = ObjCRuntime.typeEncoding(for: deviceTypeClass, selector: "mainScreenScale") {
                logger.info("type_encoding \(NSStringFromClass(deviceTypeClass)) mainScreenScale = \(scaleEncoding)")
            }

            let size = ObjCInvoker.size(deviceType, sizeSelector)
            let scaleEncoding = ObjCRuntime.typeEncoding(for: deviceTypeClass, selector: "mainScreenScale") ?? ""
            let scale: Double
            if scaleEncoding.hasPrefix("f") {
                scale = Double(ObjCInvoker.float(deviceType, scaleSelector))
            } else {
                scale = ObjCInvoker.double(deviceType, scaleSelector)
            }

            if size.width > 0, size.height > 0, scale > 0 {
                logger.info("resolved screen metrics from SimDeviceType size=\(Int(size.width))x\(Int(size.height)) scale=\(scale)")
                return ScreenMetrics(pointSize: CGSize(width: size.width / scale, height: size.height / scale), scale: scale)
            }
            logger.warn("SimDeviceType returned non-positive screen metrics size=\(size) scale=\(scale); falling back")
        }

        let fallbackSize: CGSize
        if let screenSize = simulator.screenSize {
            fallbackSize = screenSize
        } else {
            switch simulator.deviceType {
        case let type where type.contains("iPhone-17-Pro"),
             let type where type.contains("iPhone-16-Pro"):
                fallbackSize = CGSize(width: 402, height: 874)
        case let type where type.contains("iPhone-17-Pro-Max"),
             let type where type.contains("iPhone-16-Pro-Max"):
                fallbackSize = CGSize(width: 440, height: 956)
        case let type where type.contains("iPhone-17"),
             let type where type.contains("iPhone-16"):
                fallbackSize = CGSize(width: 393, height: 852)
        case let type where type.contains("iPhone-12-mini"):
                fallbackSize = CGSize(width: 375, height: 812)
        default:
                fallbackSize = CGSize(width: 393, height: 852)
            }
        }
        logger.warn("using fallback screen metrics size=\(Int(fallbackSize.width))x\(Int(fallbackSize.height)) scale=1.0")
        return ScreenMetrics(pointSize: fallbackSize, scale: 1.0)
    }
}
