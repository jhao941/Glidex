import CoreGraphics
import Foundation

public struct InputTuning: Equatable, Sendable {
    public var mouseDragThreshold: CGFloat
    public var navigationGain: CGFloat
    public var pinchIntentThreshold: CGFloat
    public var pinchFallbackThreshold: CGFloat
    public var navigationIntentThreshold: CGFloat
    public var navigationFallbackThreshold: CGFloat
    public var navigationFallbackDelay: TimeInterval

    public init(
        mouseDragThreshold: CGFloat = 3,
        navigationGain: CGFloat = 1.35,
        pinchIntentThreshold: CGFloat = 0.010,
        pinchFallbackThreshold: CGFloat = 0.018,
        navigationIntentThreshold: CGFloat = 0.010,
        navigationFallbackThreshold: CGFloat = 0.006,
        navigationFallbackDelay: TimeInterval = 0.070
    ) {
        self.mouseDragThreshold = mouseDragThreshold
        self.navigationGain = navigationGain
        self.pinchIntentThreshold = pinchIntentThreshold
        self.pinchFallbackThreshold = pinchFallbackThreshold
        self.navigationIntentThreshold = navigationIntentThreshold
        self.navigationFallbackThreshold = navigationFallbackThreshold
        self.navigationFallbackDelay = navigationFallbackDelay
    }

    public static let stable = InputTuning()
}
