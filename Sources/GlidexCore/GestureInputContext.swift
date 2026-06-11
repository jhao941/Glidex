import Foundation

public struct GestureInputSample: Equatable, Sendable {
    public var optionPressed: Bool
    public var globalMouseLocation: DesktopPoint?
    public var captureMouseLocation: CapturePoint?

    public init(
        optionPressed: Bool = false,
        globalMouseLocation: DesktopPoint? = nil,
        captureMouseLocation: CapturePoint? = nil
    ) {
        self.optionPressed = optionPressed
        self.globalMouseLocation = globalMouseLocation
        self.captureMouseLocation = captureMouseLocation
    }

    public static let none = GestureInputSample()
}

public struct GestureInputContext: Equatable, Sendable {
    public let persistentMode: CaptureInputMode
    public let optionPressed: Bool
    public let globalMouseLocation: DesktopPoint?
    public let simulatorMouseLocation: SimulatorPoint?
    public let anchorPolicy: AnchorPolicy

    public init(
        persistentMode: CaptureInputMode,
        optionPressed: Bool,
        globalMouseLocation: DesktopPoint?,
        simulatorMouseLocation: SimulatorPoint?,
        anchorPolicy: AnchorPolicy
    ) {
        self.persistentMode = persistentMode
        self.optionPressed = optionPressed
        self.globalMouseLocation = globalMouseLocation
        self.simulatorMouseLocation = simulatorMouseLocation
        self.anchorPolicy = anchorPolicy
    }

    public static func resolve(
        persistentMode: CaptureInputMode,
        optionPressed: Bool,
        globalMouseLocation: DesktopPoint?,
        simulatorMouseLocation: SimulatorPoint?,
        fixedPoint: SimulatorPoint?,
        fallback: SimulatorPoint,
        simulatorSize: SimulatorPointSize
    ) -> GestureInputContext {
        let policy: AnchorPolicy
        switch persistentMode {
        case .navigate:
            policy = optionPressed && simulatorMouseLocation != nil
                ? .point(simulatorMouseLocation)
                : .navigate
        case .point:
            policy = .point(fixedPoint)
        case .edge:
            let edgePoint = fixedPoint ?? fallback
            policy = .edge(
                AnchorPolicy.nearestEdge(to: edgePoint, simulatorSize: simulatorSize),
                fixedPoint: edgePoint
            )
        case .disabled:
            policy = .navigate
        }
        return GestureInputContext(
            persistentMode: persistentMode,
            optionPressed: optionPressed,
            globalMouseLocation: globalMouseLocation,
            simulatorMouseLocation: simulatorMouseLocation,
            anchorPolicy: policy
        )
    }
}
