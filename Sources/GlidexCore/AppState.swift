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

public enum AnchorLockState: String, Equatable, Sendable {
    case unavailable
    case unlocked
    case locked
}

public enum AnchorIndicatorState: Equatable, Sendable {
    case none
    case fixed(SimulatorPoint)
    case temporary(SimulatorPoint)
}

public struct GlidexPreferenceValues: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var inputMode: CaptureInputMode
    public var borderVisibility: BorderVisibility
    public var showsAnchorIndicator: Bool
    public var showsActiveTouches: Bool
    public var prefersAnchorLocked: Bool
    public var requiresPointerOverSimulator: Bool

    public init(
        isEnabled: Bool = true,
        inputMode: CaptureInputMode = .navigate,
        borderVisibility: BorderVisibility = .subtle,
        showsAnchorIndicator: Bool = true,
        showsActiveTouches: Bool = true,
        prefersAnchorLocked: Bool = false,
        requiresPointerOverSimulator: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.inputMode = inputMode == .disabled ? .navigate : inputMode
        self.borderVisibility = borderVisibility
        self.showsAnchorIndicator = showsAnchorIndicator
        self.showsActiveTouches = showsActiveTouches
        self.prefersAnchorLocked = prefersAnchorLocked
        self.requiresPointerOverSimulator = requiresPointerOverSimulator
    }

    public init(
        isEnabled: Bool = true,
        inputMode: CaptureInputMode = .navigate,
        borderVisibility: BorderVisibility = .subtle,
        showsTouchIndicator: Bool,
        prefersAnchorLocked: Bool = false
    ) {
        self.init(
            isEnabled: isEnabled,
            inputMode: inputMode,
            borderVisibility: borderVisibility,
            showsAnchorIndicator: showsTouchIndicator,
            showsActiveTouches: showsTouchIndicator,
            prefersAnchorLocked: prefersAnchorLocked
        )
    }

    public static let defaults = GlidexPreferenceValues()

    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case inputMode
        case borderVisibility
        case showsTouchIndicator
        case showsAnchorIndicator
        case showsActiveTouches
        case prefersAnchorLocked
        case requiresPointerOverSimulator
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let legacyIndicator = try values.decodeIfPresent(Bool.self, forKey: .showsTouchIndicator)
        self.init(
            isEnabled: try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true,
            inputMode: try values.decodeIfPresent(CaptureInputMode.self, forKey: .inputMode) ?? .navigate,
            borderVisibility: try values.decodeIfPresent(BorderVisibility.self, forKey: .borderVisibility) ?? .subtle,
            showsAnchorIndicator: try values.decodeIfPresent(Bool.self, forKey: .showsAnchorIndicator) ?? legacyIndicator ?? true,
            showsActiveTouches: try values.decodeIfPresent(Bool.self, forKey: .showsActiveTouches) ?? legacyIndicator ?? true,
            prefersAnchorLocked: try values.decodeIfPresent(Bool.self, forKey: .prefersAnchorLocked) ?? false,
            requiresPointerOverSimulator: try values.decodeIfPresent(Bool.self, forKey: .requiresPointerOverSimulator) ?? true
        )
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(isEnabled, forKey: .isEnabled)
        try values.encode(inputMode, forKey: .inputMode)
        try values.encode(borderVisibility, forKey: .borderVisibility)
        try values.encode(showsAnchorIndicator, forKey: .showsAnchorIndicator)
        try values.encode(showsActiveTouches, forKey: .showsActiveTouches)
        try values.encode(prefersAnchorLocked, forKey: .prefersAnchorLocked)
        try values.encode(requiresPointerOverSimulator, forKey: .requiresPointerOverSimulator)
    }

    public var showsTouchIndicator: Bool {
        get { showsAnchorIndicator && showsActiveTouches }
        set {
            showsAnchorIndicator = newValue
            showsActiveTouches = newValue
        }
    }
}

public struct GlidexAppSnapshot: Equatable, Sendable {
    public var preferences: GlidexPreferenceValues
    public var status: GlidexRuntimeStatus
    public var target: SimulatorTarget?
    public var isCalibrationMode: Bool
    public var optionAnchorAvailability: OptionAnchorAvailability
    public var anchorLockState: AnchorLockState
    public var anchorIndicator: AnchorIndicatorState
    public var activeTouches: [TouchContactPoint]

    public init(
        preferences: GlidexPreferenceValues = .defaults,
        status: GlidexRuntimeStatus = .waiting("Looking for Simulator"),
        target: SimulatorTarget? = nil,
        isCalibrationMode: Bool = false,
        optionAnchorAvailability: OptionAnchorAvailability = .inactive,
        anchorLockState: AnchorLockState? = nil,
        anchorIndicator: AnchorIndicatorState = .none,
        activeTouches: [TouchContactPoint] = []
    ) {
        self.preferences = preferences
        self.status = preferences.isEnabled ? status : .paused
        self.target = target
        self.isCalibrationMode = isCalibrationMode
        self.optionAnchorAvailability = optionAnchorAvailability
        self.anchorLockState = anchorLockState ?? (
            !preferences.inputMode.supportsAnchor
                ? .unavailable
                : (preferences.prefersAnchorLocked ? .locked : .unlocked)
        )
        self.anchorIndicator = anchorIndicator
        self.activeTouches = activeTouches
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
    private var previousNonDirectInputMode: CaptureInputMode

    public init(snapshot: GlidexAppSnapshot = GlidexAppSnapshot()) {
        self.snapshot = snapshot
        self.previousNonDirectInputMode = snapshot.preferences.inputMode == .directTouch
            ? .navigate
            : snapshot.preferences.inputMode
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
        if next.preferences.inputMode != .directTouch {
            previousNonDirectInputMode = next.preferences.inputMode
        }
        next.anchorLockState = !next.preferences.inputMode.supportsAnchor
            ? .unavailable
            : (next.preferences.prefersAnchorLocked ? .locked : .unlocked)
        commit(next)
    }

    public func toggleDirectTouchMode() {
        setInputMode(snapshot.preferences.inputMode == .directTouch
            ? previousNonDirectInputMode
            : .directTouch)
    }

    public func setAnchorLocked(_ locked: Bool) {
        guard snapshot.preferences.inputMode.supportsAnchor else { return }
        var next = snapshot
        next.preferences.prefersAnchorLocked = locked
        next.anchorLockState = locked ? .locked : .unlocked
        commit(next)
    }

    public func resetAnchorLockForAttachment() {
        guard snapshot.preferences.inputMode.supportsAnchor else { return }
        var next = snapshot
        next.anchorLockState = .unlocked
        commit(next)
    }

    public func setBorderVisibility(_ visibility: BorderVisibility) {
        var next = snapshot
        next.preferences.borderVisibility = visibility
        commit(next)
    }

    public func setShowsAnchorIndicator(_ shows: Bool) {
        var next = snapshot
        next.preferences.showsAnchorIndicator = shows
        commit(next)
    }

    public func setShowsActiveTouches(_ shows: Bool) {
        var next = snapshot
        next.preferences.showsActiveTouches = shows
        if !shows { next.activeTouches = [] }
        commit(next)
    }

    public func setRequiresPointerOverSimulator(_ requires: Bool) {
        var next = snapshot
        next.preferences.requiresPointerOverSimulator = requires
        commit(next)
    }

    public func setAnchorIndicator(_ indicator: AnchorIndicatorState) {
        var next = snapshot
        next.anchorIndicator = indicator
        commit(next)
    }

    public func setActiveTouches(_ contacts: [TouchContactPoint]) {
        var next = snapshot
        next.activeTouches = contacts
        commit(next)
    }

    public func clearIndicators() {
        var next = snapshot
        next.anchorIndicator = .none
        next.activeTouches = []
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
