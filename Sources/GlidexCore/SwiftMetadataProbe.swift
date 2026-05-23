import Darwin
import Foundation

private struct RawValueWitnessTable {
    let initializeBufferWithCopyOfBuffer: UnsafeRawPointer
    let destroy: UnsafeRawPointer
    let initializeWithCopy: UnsafeRawPointer
    let assignWithCopy: UnsafeRawPointer
    let initializeWithTake: UnsafeRawPointer
    let assignWithTake: UnsafeRawPointer
    let getEnumTagSinglePayload: UnsafeRawPointer
    let storeEnumTagSinglePayload: UnsafeRawPointer
    let size: UInt
    let stride: UInt
    let flags: UInt32
    let extraInhabitantCount: UInt32
}

enum SwiftMetadataProbe {
    typealias MetadataAccessorFn = @convention(thin) () -> UnsafeRawPointer

    private struct TypeProbe {
        let name: String
        let symbol: String
    }

    private struct SymbolProbe {
        let name: String
        let symbol: String
    }

    static func run(framework: PrivateFrameworkHandle, logger: Logger) throws {
        logger.info("probing Swift metadata for SimulatorKit digitizer and display-input types")

        let typeProbes = [
            TypeProbe(
                name: "SimDigitizerInputView.DeviceUnitPoint",
                symbol: "$s12SimulatorKit21SimDigitizerInputViewC15DeviceUnitPointVMa"
            ),
            TypeProbe(
                name: "SimDigitizerInputView.TouchPhase",
                symbol: "$s12SimulatorKit21SimDigitizerInputViewC10TouchPhaseOMa"
            ),
            TypeProbe(
                name: "SimDigitizerInputView.TouchEvent",
                symbol: "$s12SimulatorKit21SimDigitizerInputViewC10TouchEventVMa"
            ),
            TypeProbe(
                name: "SimDigitizerInputView.PressureEvent",
                symbol: "$s12SimulatorKit21SimDigitizerInputViewC13PressureEventVMa"
            ),
            TypeProbe(
                name: "SimDigitizerInputView.ScrollEvent",
                symbol: "$s12SimulatorKit21SimDigitizerInputViewC11ScrollEventVMa"
            ),
            TypeProbe(
                name: "SimDigitizerInputView.TouchMode",
                symbol: "$s12SimulatorKit21SimDigitizerInputViewC9TouchModeOMa"
            ),
            TypeProbe(
                name: "SimDigitizerInputView.DrawOption",
                symbol: "$s12SimulatorKit21SimDigitizerInputViewC10DrawOptionVMa"
            ),
            TypeProbe(
                name: "SimDigitizerInputView.Context",
                symbol: "$s12SimulatorKit21SimDigitizerInputViewC7ContextVMa"
            ),
            TypeProbe(
                name: "SimDisplayView.ScreenInputDevice",
                symbol: "$s12SimulatorKit14SimDisplayViewC17ScreenInputDeviceVMa"
            ),
        ]

        for probe in typeProbes {
            try describeType(probe, framework: framework, logger: logger)
        }

        logger.info("probing Swift entrypoint symbols for digitizer state machine")
        for probe in symbolProbes {
            describeSymbol(probe, framework: framework, logger: logger)
        }
    }

    private static let symbolProbes = [
        SymbolProbe(
            name: "ScreenInputDevice.none",
            symbol: "$s12SimulatorKit14SimDisplayViewC17ScreenInputDeviceV4noneAEvgZ"
        ),
        SymbolProbe(
            name: "ScreenInputDevice.digitizer",
            symbol: "$s12SimulatorKit14SimDisplayViewC17ScreenInputDeviceV9digitizerAEvgZ"
        ),
        SymbolProbe(
            name: "ScreenInputDevice.hardwareButtons",
            symbol: "$s12SimulatorKit14SimDisplayViewC17ScreenInputDeviceV15hardwareButtonsAEvgZ"
        ),
        SymbolProbe(
            name: "ScreenInputDevice.keyboard",
            symbol: "$s12SimulatorKit14SimDisplayViewC17ScreenInputDeviceV8keyboardAEvgZ"
        ),
        SymbolProbe(
            name: "ScreenInputDevice.all",
            symbol: "$s12SimulatorKit14SimDisplayViewC17ScreenInputDeviceV3allAEvgZ"
        ),
        SymbolProbe(
            name: "SimDisplayView.connect(screen:inputs:)",
            symbol: "$s12SimulatorKit14SimDisplayViewC7connect6screen6inputsyAA0C12DeviceScreenC_AC0j5InputI0VtKFTj"
        ),
        SymbolProbe(
            name: "SimDisplayView.digitizerView.getter",
            symbol: "$s12SimulatorKit14SimDisplayViewC09digitizerE0AA0c14DigitizerInputE0CvgTj"
        ),
        SymbolProbe(
            name: "SimDigitizerInputView.processMouseEvents(with:)",
            symbol: "$s12SimulatorKit21SimDigitizerInputViewC18processMouseEvents4withyAC7ContextV_tFTj"
        ),
        SymbolProbe(
            name: "SimDigitizerInputView.processMouseEventsForTouch2(with:)",
            symbol: "$s12SimulatorKit21SimDigitizerInputViewC27processMouseEventsForTouch24withyAC7ContextV_tFTj"
        ),
        SymbolProbe(
            name: "SimDigitizerInputView.processPinchEvents(with:)",
            symbol: "$s12SimulatorKit21SimDigitizerInputViewC18processPinchEvents4withyAC7ContextV_tFTj"
        ),
        SymbolProbe(
            name: "SimDigitizerInputView.processPressureEvents(with:)",
            symbol: "$s12SimulatorKit21SimDigitizerInputViewC21processPressureEvents4withyAC7ContextV_tFTj"
        ),
        SymbolProbe(
            name: "SimDigitizerInputView.transitionToMouseDown(with:)",
            symbol: "$s12SimulatorKit21SimDigitizerInputViewC21transitionToMouseDown4withyAC7ContextV_tFTj"
        ),
        SymbolProbe(
            name: "SimDigitizerInputView.transitionToMaybeFingerDown(with:)",
            symbol: "$s12SimulatorKit21SimDigitizerInputViewC27transitionToMaybeFingerDown4withyAC7ContextV_tFTj"
        ),
        SymbolProbe(
            name: "SimDigitizerInputView.transitionToSecondFingerDown(with:)",
            symbol: "$s12SimulatorKit21SimDigitizerInputViewC28transitionToSecondFingerDown4withyAC7ContextV_tFTj"
        ),
        SymbolProbe(
            name: "SimDigitizerInputView.transitionToPinch(with:)",
            symbol: "$s12SimulatorKit21SimDigitizerInputViewC17transitionToPinch4withyAC7ContextV_tFTj"
        ),
        SymbolProbe(
            name: "SimDigitizerInputView.transitionToIdle(with:forwardEvent:)",
            symbol: "$s12SimulatorKit21SimDigitizerInputViewC16transitionToIdle4with12forwardEventyAC7ContextV_So7NSEventCSgtFTj"
        ),
        SymbolProbe(
            name: "SimDeviceLegacyHIDClient.simDigitizerInputView(_:touchEvent:)",
            symbol: "$s12SimulatorKit24SimDeviceLegacyHIDClientC21simDigitizerInputView_10touchEventyAA0chiJ0C_AG05TouchL0VtF"
        ),
        SymbolProbe(
            name: "SimDeviceLegacyHIDClient.simDigitizerInputView(_:scrollEvent:)",
            symbol: "$s12SimulatorKit24SimDeviceLegacyHIDClientC21simDigitizerInputView_11scrollEventyAA0chiJ0C_AG06ScrollL0VtF"
        ),
        SymbolProbe(
            name: "SimDeviceLegacyHIDClient.simDigitizerInputView(_:pressureEvent:)",
            symbol: "$s12SimulatorKit24SimDeviceLegacyHIDClientC21simDigitizerInputView_13pressureEventyAA0chiJ0C_AG08PressureL0VtF"
        ),
    ]

    private static func describeType(_ probe: TypeProbe, framework: PrivateFrameworkHandle, logger: Logger) throws {
        let metadata = try metadataAccessor(probe.symbol, framework: framework)()
        describeType(named: probe.name, metadata: metadata, logger: logger)
    }

    private static func describeType(named: String, metadata: UnsafeRawPointer, logger: Logger) {
        let vwtPointerAddress = metadata.advanced(by: -MemoryLayout<UnsafeRawPointer>.size)
        let vwtPointer = vwtPointerAddress.load(as: UnsafeRawPointer.self)
        let vwt = vwtPointer.load(as: RawValueWitnessTable.self)
        logger.info("\(named) metadata=\(metadata) vwt=\(vwtPointer) size=\(vwt.size) stride=\(vwt.stride) flags=0x\(String(vwt.flags, radix: 16)) extraInhabitants=\(vwt.extraInhabitantCount)")
    }

    private static func describeSymbol(_ probe: SymbolProbe, framework: PrivateFrameworkHandle, logger: Logger) {
        if let raw = dlsym(framework.handle, probe.symbol) {
            logger.info("swift symbol found: \(probe.name) address=\(raw)")
        } else {
            logger.warn("swift symbol missing: \(probe.name) symbol=\(probe.symbol)")
        }
    }

    private static func metadataAccessor(_ symbol: String, framework: PrivateFrameworkHandle) throws -> MetadataAccessorFn {
        guard let raw = dlsym(framework.handle, symbol) else {
            throw GlidexError.symbolMissing("swift metadata accessor missing: \(symbol)")
        }
        return unsafeBitCast(raw, to: MetadataAccessorFn.self)
    }
}
