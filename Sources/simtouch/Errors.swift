import Foundation

enum SimTouchError: Error, CustomStringConvertible {
    case usage(String)
    case frameworkLoadFailed(String)
    case symbolMissing(String)
    case classMissing(String)
    case selectorMissing(String)
    case commandFailed(String)
    case simulatorNotFound(String)
    case unsupported(String)

    var description: String {
        switch self {
        case let .usage(message),
             let .frameworkLoadFailed(message),
             let .symbolMissing(message),
             let .classMissing(message),
             let .selectorMissing(message),
             let .commandFailed(message),
             let .simulatorNotFound(message),
             let .unsupported(message):
            return message
        }
    }
}
