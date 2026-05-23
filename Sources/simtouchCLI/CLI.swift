import Foundation
import SimTouchCore

struct CLI {
    private let arguments: [String]
    private let logger: Logger

    init(arguments: [String], logger: Logger) throws {
        self.arguments = arguments
        self.logger = logger
    }

    func run() async throws {
        guard arguments.count >= 2 else {
            throw SimTouchError.usage(Self.usage)
        }

        let command = arguments[1]
        let injector = try SimulatorInjector(logger: logger)

        switch command {
        case "list":
            let devices = try injector.listBootedSimulators()
            DevicePrinter.printDevices(devices, logger: logger)
        case "tap":
            let point = try parsePointFlags(arguments.dropFirst(2), xFlag: "--x", yFlag: "--y")
            try injector.tap(at: point)
        case "digitizer-tap":
            let point = try parsePointFlags(arguments.dropFirst(2), xFlag: "--x", yFlag: "--y")
            try injector.digitizerTap(at: point)
        case "drag":
            let parser = ArgumentCursor(Array(arguments.dropFirst(2)))
            let from = try parser.point(for: "--from")
            let to = try parser.point(for: "--to")
            let duration = try parser.double(for: "--duration", defaultValue: 0.5)
            try injector.drag(from: from, to: to, duration: duration)
        case "pinch":
            let parser = ArgumentCursor(Array(arguments.dropFirst(2)))
            let center = try parser.point(for: "--center")
            let scale = try parser.double(for: "--scale", defaultValue: 1.2)
            let duration = try parser.double(for: "--duration", defaultValue: 0.5)
            try injector.pinch(center: center, scale: scale, duration: duration)
        case "probe":
            try injector.probe()
        case "swift-probe":
            try injector.swiftProbe()
        default:
            throw SimTouchError.usage("unknown command '\(command)'\n\n\(Self.usage)")
        }
    }

    private func parsePointFlags(_ args: ArraySlice<String>, xFlag: String, yFlag: String) throws -> CGPoint {
        let parser = ArgumentCursor(Array(args))
        let x = try parser.double(for: xFlag)
        let y = try parser.double(for: yFlag)
        return CGPoint(x: x, y: y)
    }

    static let usage = """
    Usage:
      simtouch list
      simtouch probe
      simtouch swift-probe
      simtouch tap --x 120 --y 300
      simtouch digitizer-tap --x 120 --y 300
      simtouch drag --from 120,300 --to 120,700 --duration 0.5
      simtouch pinch --center 200,400 --scale 1.2 --duration 0.5
    """
}

struct ArgumentCursor {
    private let args: [String]

    init(_ args: [String]) {
        self.args = args
    }

    func value(for flag: String) throws -> String {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else {
            throw SimTouchError.usage("missing value for \(flag)")
        }
        return args[index + 1]
    }

    func double(for flag: String, defaultValue: Double? = nil) throws -> Double {
        if let index = args.firstIndex(of: flag), index + 1 < args.count, let value = Double(args[index + 1]) {
            return value
        }
        if let defaultValue {
            return defaultValue
        }
        throw SimTouchError.usage("missing numeric value for \(flag)")
    }

    func point(for flag: String) throws -> CGPoint {
        let raw = try value(for: flag)
        let parts = raw.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else {
            throw SimTouchError.usage("expected \(flag) in x,y form")
        }
        return CGPoint(x: x, y: y)
    }
}
