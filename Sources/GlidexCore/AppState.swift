import Foundation

public enum GlidexRuntimeStatus: Equatable, Sendable {
    case waiting(String)
    case connecting
    case active
    case paused
    case error(GlidexRuntimeError)

    public var title: String {
        switch self {
        case .waiting: "Waiting"
        case .connecting: "Connecting"
        case .active: "Active"
        case .paused: "Paused"
        case .error: "Error"
        }
    }
}

public enum GlidexRuntimeError: Equatable, Sendable {
    case accessibilityPermission
    case simulatorNotRunning
    case ambiguousTarget
    case multitouchUnavailable(String)
    case hidInitialization(String)
    case other(String)

    public var message: String {
        switch self {
        case .accessibilityPermission:
            "Accessibility permission is required"
        case .simulatorNotRunning:
            "Simulator is not running"
        case .ambiguousTarget:
            "Multiple Simulator targets could not be matched"
        case let .multitouchUnavailable(detail):
            "MultitouchSupport unavailable: \(detail)"
        case let .hidInitialization(detail):
            "HID backend failed: \(detail)"
        case let .other(detail):
            detail
        }
    }
}

public enum BorderVisibility: String, Codable, CaseIterable, Equatable, Sendable {
    case hidden
    case subtle
    case normal
    case strong

    public var alpha: CGFloat {
        switch self {
        case .hidden: 0
        case .subtle: 0.35
        case .normal: 0.65
        case .strong: 1
        }
    }
}

public enum OptionAnchorAvailability: Equatable, Sendable {
    case inactive
    case outsideSimulator
    case available(SimulatorPoint)

    public var title: String {
        switch self {
        case .inactive: "Ready"
        case .outsideSimulator: "Pointer outside Simulator"
        case .available: "Active"
        }
    }
}

public struct GlidexPreferenceValues: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var inputMode: CaptureInputMode
    public var borderVisibility: BorderVisibility
    public var showsTouchIndicator: Bool

    public init(
        isEnabled: Bool = true,
        inputMode: CaptureInputMode = .navigate,
        borderVisibility: BorderVisibility = .subtle,
        showsTouchIndicator: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.inputMode = inputMode == .disabled ? .navigate : inputMode
        self.borderVisibility = borderVisibility
        self.showsTouchIndicator = showsTouchIndicator
    }

    public static let defaults = GlidexPreferenceValues()
}

public struct GlidexAppSnapshot: Equatable, Sendable {
    public var preferences: GlidexPreferenceValues
    public var status: GlidexRuntimeStatus
    public var target: SimulatorTarget?
    public var isCalibrationMode: Bool
    public var optionAnchorAvailability: OptionAnchorAvailability

    public init(
        preferences: GlidexPreferenceValues = .defaults,
        status: GlidexRuntimeStatus = .waiting("Looking for Simulator"),
        target: SimulatorTarget? = nil,
        isCalibrationMode: Bool = false,
        optionAnchorAvailability: OptionAnchorAvailability = .inactive
    ) {
        self.preferences = preferences
        self.status = preferences.isEnabled ? status : .paused
        self.target = target
        self.isCalibrationMode = isCalibrationMode
        self.optionAnchorAvailability = optionAnchorAvailability
    }

    public var acceptsInput: Bool {
        preferences.isEnabled && (status == .active || isCalibrationMode)
    }
}

@MainActor
public final class GlidexAppState {
    public typealias Observer = (GlidexAppSnapshot) -> Void

    public private(set) var snapshot: GlidexAppSnapshot {
        didSet {
            for observer in observers.values {
                observer(snapshot)
            }
        }
    }

    private var observers: [UUID: Observer] = [:]

    public init(snapshot: GlidexAppSnapshot = GlidexAppSnapshot()) {
        self.snapshot = snapshot
    }

    @discardableResult
    public func observe(_ observer: @escaping Observer) -> UUID {
        let id = UUID()
        observers[id] = observer
        observer(snapshot)
        return id
    }

    public func removeObserver(_ id: UUID) {
        observers[id] = nil
    }

    public func setEnabled(_ enabled: Bool) {
        var next = snapshot
        next.preferences.isEnabled = enabled
        if enabled {
            if case .paused = next.status {
                next.status = .waiting("Looking for Simulator")
            }
        } else {
            next.status = .paused
            next.isCalibrationMode = false
        }
        commit(next)
    }

    public func setInputMode(_ mode: CaptureInputMode) {
        var next = snapshot
        next.preferences.inputMode = mode == .disabled ? .navigate : mode
        commit(next)
    }

    public func setBorderVisibility(_ visibility: BorderVisibility) {
        var next = snapshot
        next.preferences.borderVisibility = visibility
        commit(next)
    }

    public func setShowsTouchIndicator(_ shows: Bool) {
        var next = snapshot
        next.preferences.showsTouchIndicator = shows
        commit(next)
    }

    public func setCalibrationMode(_ enabled: Bool) {
        var next = snapshot
        next.isCalibrationMode = enabled
        commit(next)
    }

    public func setOptionAnchorAvailability(_ availability: OptionAnchorAvailability) {
        var next = snapshot
        next.optionAnchorAvailability = availability
        commit(next)
    }

    public func transition(to status: GlidexRuntimeStatus, target: SimulatorTarget? = nil) {
        var next = snapshot
        next.target = target
        next.status = next.preferences.isEnabled ? status : .paused
        commit(next)
    }

    private func commit(_ next: GlidexAppSnapshot) {
        guard next != snapshot else { return }
        snapshot = next
    }
}
