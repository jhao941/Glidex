import CoreGraphics
import Foundation

public struct RawTouchContact: Codable, Sendable {
    public let identifier: Int32
    public let state: Int32
    public let normalizedPosition: NormalizedTouchPoint
    public let normalizedVelocity: NormalizedTouchVector
    public let size: Float

    public init(
        identifier: Int32,
        state: Int32,
        normalizedPosition: NormalizedTouchPoint,
        normalizedVelocity: NormalizedTouchVector,
        size: Float
    ) {
        self.identifier = identifier
        self.state = state
        self.normalizedPosition = normalizedPosition
        self.normalizedVelocity = normalizedVelocity
        self.size = size
    }

    public var isActive: Bool {
        state != 7
    }
}

public struct RawTouchFrame: Codable, Sendable {
    public let timestamp: Double
    public let frame: Int32
    public let contacts: [RawTouchContact]

    public init(timestamp: Double, frame: Int32, contacts: [RawTouchContact]) {
        self.timestamp = timestamp
        self.frame = frame
        self.contacts = contacts
    }
}
