import CoreGraphics
import Foundation

public struct NormalizedTouchPoint: Codable, Equatable, Sendable {
    public var x: CGFloat
    public var y: CGFloat

    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }
}

public struct NormalizedTouchVector: Codable, Equatable, Sendable {
    public var x: CGFloat
    public var y: CGFloat

    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    public static let zero = NormalizedTouchVector(x: 0, y: 0)
}

public struct CapturePoint: Codable, Equatable, Sendable {
    public var x: CGFloat
    public var y: CGFloat

    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    public init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
    }

    public var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

public struct DesktopPoint: Codable, Equatable, Sendable {
    public var x: CGFloat
    public var y: CGFloat

    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    public init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
    }

    public var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

public struct SimulatorPoint: Equatable, Sendable {
    public var x: CGFloat
    public var y: CGFloat

    public init(x: CGFloat, y: CGFloat) {
        self.x = x
        self.y = y
    }

    public init(_ point: CGPoint) {
        self.init(x: point.x, y: point.y)
    }

    public var cgPoint: CGPoint {
        CGPoint(x: x, y: y)
    }
}

public struct SimulatorPointSize: Equatable, Sendable {
    public var width: CGFloat
    public var height: CGFloat

    public init(width: CGFloat, height: CGFloat) {
        self.width = width
        self.height = height
    }

    public init(_ size: CGSize) {
        self.init(width: size.width, height: size.height)
    }

    public var cgSize: CGSize {
        CGSize(width: width, height: height)
    }
}

public enum TouchSource: String, Equatable, Sendable {
    case mouse
    case rawTrackpad
}

public enum GestureIntent: String, Equatable, Sendable {
    case point
    case navigate
    case edge
    case pinch
    case directTouch
}

public enum CaptureInputMode: String, Codable, CaseIterable, Equatable, Sendable {
    case navigate
    case directTouch
    case point
    case edge
    case disabled

    public var supportsAnchor: Bool {
        self == .point || self == .edge
    }
}

public struct TouchContactPoint: Equatable, Sendable {
    public var identifier: Int
    public var point: SimulatorPoint

    public init(identifier: Int, point: SimulatorPoint) {
        self.identifier = identifier
        self.point = point
    }
}
