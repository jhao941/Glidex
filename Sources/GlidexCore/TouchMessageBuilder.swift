import CGlidexShim
import CoreGraphics
import Foundation

enum TouchDirection: Int32 {
    case down = 1
    case up = 2
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

    static func describe(_ message: UnsafeMutableRawPointer) -> String {
        guard let cString = st_copy_indigo_message_description(message) else {
            return "message_description_unavailable"
        }
        defer { free(UnsafeMutableRawPointer(mutating: cString)) }
        return String(cString: cString)
    }
}
