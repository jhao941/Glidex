import Foundation

public struct OverlayPresentation: Equatable, Sendable {
    public static let windowAlpha: CGFloat = 1

    public var status: GlidexRuntimeStatus
    public var acceptsInput: Bool
    public var borderAlpha: CGFloat
    public var inputMode: CaptureInputMode
    public var showsTouchIndicator: Bool
    public var isCalibrationMode: Bool

    public init(snapshot: GlidexAppSnapshot) {
        self.status = snapshot.status
        self.acceptsInput = snapshot.acceptsInput
        self.borderAlpha = snapshot.preferences.borderVisibility.alpha
        self.inputMode = snapshot.preferences.inputMode
        self.showsTouchIndicator = snapshot.preferences.showsTouchIndicator
        self.isCalibrationMode = snapshot.isCalibrationMode
    }
}
