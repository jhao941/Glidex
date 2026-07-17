import CoreGraphics
import Foundation

public struct GestureRecording: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1

    public let formatVersion: Int
    public let name: String
    public let recordedAt: Date
    public let sourceScreen: RecordingScreen
    public let events: [RecordedTouchEvent]

    public init(
        name: String,
        recordedAt: Date,
        sourceScreen: RecordingScreen,
        events: [RecordedTouchEvent]
    ) {
        self.formatVersion = Self.currentFormatVersion
        self.name = name
        self.recordedAt = recordedAt
        self.sourceScreen = sourceScreen
        self.events = events
    }

    public var duration: TimeInterval { events.last?.time ?? 0 }

    public var maximumContactCount: Int {
        events.map(\.contacts.count).max() ?? 0
    }

    public func renamed(_ name: String) -> GestureRecording {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return GestureRecording(
            name: trimmed.isEmpty ? self.name : trimmed,
            recordedAt: recordedAt,
            sourceScreen: sourceScreen,
            events: events
        )
    }
}

public struct RecordingScreen: Codable, Equatable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public init(_ size: SimulatorPointSize) {
        self.init(width: Double(size.width), height: Double(size.height))
    }

    public var isValid: Bool { width > 0 && height > 0 }
}

public enum RecordedTouchPhase: String, Codable, Equatable, Sendable {
    case begin
    case update
    case end
    case cancel
}

public struct RecordedTouchContact: Codable, Equatable, Sendable {
    public let id: Int
    public let x: Double
    public let y: Double

    public init(id: Int, x: Double, y: Double) {
        self.id = id
        self.x = x
        self.y = y
    }
}

public struct RecordedTouchEvent: Codable, Equatable, Sendable {
    public let time: TimeInterval
    public let gestureID: UUID
    public let phase: RecordedTouchPhase
    public let source: TouchSource
    public let intent: GestureIntent
    public let anchorX: Double
    public let anchorY: Double
    public let contacts: [RecordedTouchContact]

    public init(
        time: TimeInterval,
        gestureID: UUID,
        phase: RecordedTouchPhase,
        source: TouchSource,
        intent: GestureIntent,
        anchorX: Double,
        anchorY: Double,
        contacts: [RecordedTouchContact]
    ) {
        self.time = time
        self.gestureID = gestureID
        self.phase = phase
        self.source = source
        self.intent = intent
        self.anchorX = anchorX
        self.anchorY = anchorY
        self.contacts = contacts
    }
}

public enum GestureRecordingCodec {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func encode(_ recording: GestureRecording) throws -> Data {
        try encoder().encode(recording)
    }

    public static func decode(_ data: Data) throws -> GestureRecording {
        let recording = try decoder().decode(GestureRecording.self, from: data)
        guard recording.formatVersion == GestureRecording.currentFormatVersion else {
            throw GestureRecordingError.unsupportedFormatVersion(recording.formatVersion)
        }
        guard recording.sourceScreen.isValid else {
            throw GestureRecordingError.invalidSourceScreen
        }
        var previousTime: TimeInterval = 0
        for (index, event) in recording.events.enumerated() {
            guard event.time >= previousTime,
                  event.anchorX.isNormalized,
                  event.anchorY.isNormalized,
                  event.contacts.allSatisfy({ $0.x.isNormalized && $0.y.isNormalized }) else {
                throw GestureRecordingError.invalidEvent(index)
            }
            previousTime = event.time
        }
        return recording
    }
}

public enum GestureRecordingError: Error, Equatable, Sendable {
    case invalidSourceScreen
    case invalidEvent(Int)
    case alreadyRecording
    case unsupportedFormatVersion(Int)
}

private extension Double {
    var isNormalized: Bool { isFinite && self >= 0 && self <= 1 }
}
