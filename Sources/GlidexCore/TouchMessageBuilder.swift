import CGlidexShim
import CoreGraphics
import Foundation

enum TouchDirection: Int32 {
    case down = 1
    case up = 2
}

enum DirectTouchContactPhase: UInt8, Sendable {
    case down = 0
    case move = 1
    case up = 2
}

struct DirectTouchContact: Equatable, Sendable {
    let identifier: UInt32
    let point: CGPoint
    let phase: DirectTouchContactPhase
}

enum TouchMessageBuilder {
    static func singleTouch(point: CGPoint, screenPointSize: CGSize, direction: TouchDirection) throws -> UnsafeMutableRawPointer {
        var messageSize: Int = 0
        var errorCString: UnsafePointer<CChar>?
        guard let message = st_create_indigo_touch_message(point, screenPointSize, direction.rawValue, &messageSize, &errorCString) else {
            let message = errorCString.map { String(cString: $0) } ?? "unknown touch builder failure"
            if let errorCString {
                free(UnsafeMutableRawPointer(mutating: errorCString))
            }
            throw GlidexError.commandFailed("failed to create single-touch Indigo message: \(message)")
        }
        if let errorCString {
            free(UnsafeMutableRawPointer(mutating: errorCString))
        }
        return message
    }

    static func twoFingerTouch(finger1: CGPoint, finger2: CGPoint, screenPointSize: CGSize, direction: TouchDirection) throws -> UnsafeMutableRawPointer {
        var messageSize: Int = 0
        var errorCString: UnsafePointer<CChar>?
        guard let message = st_create_indigo_two_finger_touch_message(finger1, finger2, screenPointSize, direction.rawValue, &messageSize, &errorCString) else {
            let message = errorCString.map { String(cString: $0) } ?? "unknown two-finger builder failure"
            if let errorCString {
                free(UnsafeMutableRawPointer(mutating: errorCString))
            }
            throw GlidexError.commandFailed("failed to create two-finger Indigo message: \(message)")
        }
        if let errorCString {
            free(UnsafeMutableRawPointer(mutating: errorCString))
        }
        return message
    }

    static func directTouch(contacts: [DirectTouchContact], screenPointSize: CGSize) throws -> UnsafeMutableRawPointer {
        let points = contacts.map(\.point)
        let identifiers = contacts.map(\.identifier)
        let phases = contacts.map { $0.phase.rawValue }
        var messageSize: Int = 0
        var errorCString: UnsafePointer<CChar>?
        let message = points.withUnsafeBufferPointer { pointsBuffer in
            identifiers.withUnsafeBufferPointer { identifiersBuffer in
                phases.withUnsafeBufferPointer { phasesBuffer in
                    st_create_indigo_direct_touch_message(
                        pointsBuffer.baseAddress,
                        identifiersBuffer.baseAddress,
                        phasesBuffer.baseAddress,
                        contacts.count,
                        screenPointSize,
                        &messageSize,
                        &errorCString
                    )
                }
            }
        }
        guard let message else {
            let description = errorCString.map { String(cString: $0) } ?? "unknown Direct Touch builder failure"
            if let errorCString {
                free(UnsafeMutableRawPointer(mutating: errorCString))
            }
            throw GlidexError.commandFailed("failed to create Direct Touch Indigo message: \(description)")
        }
        if let errorCString {
            free(UnsafeMutableRawPointer(mutating: errorCString))
        }
        return message
    }

    static func describe(_ message: UnsafeMutableRawPointer) -> String {
        guard let cString = st_copy_indigo_message_description(message) else {
            return "message_description_unavailable"
        }
        defer { free(UnsafeMutableRawPointer(mutating: cString)) }
        return String(cString: cString)
    }
}
