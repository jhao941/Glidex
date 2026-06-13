import Foundation
import GlidexCore

struct CLI {
    private let arguments: [String]
    private let logger: Logger

    init(arguments: [String], logger: Logger) throws {
        self.arguments = arguments
        self.logger = logger
    }

    func run() async throws {
        guard arguments.count >= 2 else {
            throw GlidexError.usage(Self.usage)
        }

        let command = arguments[1]
        let injector = try SimulatorInjector(logger: logger)

        switch command {
        case "help", "--help", "-h":
            print(Self.usage)
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
        case "live-drag":
            let parser = ArgumentCursor(Array(arguments.dropFirst(2)))
            let from = try parser.point(for: "--from")
            let to = try parser.point(for: "--to")
            let duration = try parser.double(for: "--duration", defaultValue: 0.5)
            try await runLiveDrag(injector: injector, from: from, to: to, duration: duration)
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
        case "multitouch-probe":
            let parser = ArgumentCursor(Array(arguments.dropFirst(2)))
            let duration = try parser.double(for: "--duration", defaultValue: 10)
            let mode = try Int32(parser.int(for: "--mode", defaultValue: 0))
            let sourceValue = try parser.string(for: "--source", defaultValue: "default")
            guard let source = MultitouchProbeSource(rawValue: sourceValue) else {
                throw GlidexError.usage("expected --source to be list, default, or both")
            }
            try injector.multitouchProbe(duration: duration, mode: mode, source: source)
        case "recordings":
            try await runRecordingsCommand(injector: injector)
        default:
            throw GlidexError.usage("unknown command '\(command)'\n\n\(Self.usage)")
        }
    }

    private func runRecordingsCommand(injector: SimulatorInjector) async throws {
        guard arguments.count >= 3 else {
            throw GlidexError.usage("missing recordings subcommand\n\n\(Self.usage)")
        }
        let parser = ArgumentCursor(Array(arguments.dropFirst(3)))
        let directory = try parser.optionalString(for: "--directory")
            .map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath, isDirectory: true) }
            ?? GestureRecordingStore.defaultDirectoryURL()
        let store = GestureRecordingStore(directoryURL: directory)

        switch arguments[2] {
        case "list":
            let recordings = try store.recordings()
            if recordings.isEmpty {
                print("No recordings in \(directory.path)")
                return
            }
            for stored in recordings {
                let duration = stored.recording.events.last?.time ?? 0
                print("\(stored.url.path)\t\(stored.recording.events.count) events\t\(String(format: "%.3fs", duration))")
            }
        case "replay":
            let file = try parser.string(for: "--file")
            let url = URL(fileURLWithPath: NSString(string: file).expandingTildeInPath)
            let playbackRate = try parser.double(for: "--rate", defaultValue: 1)
            if let udid = try parser.optionalString(for: "--udid") {
                _ = try injector.selectTarget(udid: udid)
            }
            let target = try injector.selectedTarget()
            let stored = try store.load(from: url)
            let sink = IndigoTouchSink(injector: injector, logger: logger)
            try await CLIReplaySession.replay(
                stored.recording,
                target: target,
                sink: sink,
                playbackRate: playbackRate
            )
        default:
            throw GlidexError.usage("unknown recordings subcommand '\(arguments[2])'\n\n\(Self.usage)")
        }
    }

    private func parsePointFlags(_ args: ArraySlice<String>, xFlag: String, yFlag: String) throws -> CGPoint {
        let parser = ArgumentCursor(Array(args))
        let x = try parser.double(for: xFlag)
        let y = try parser.double(for: yFlag)
        return CGPoint(x: x, y: y)
    }

    private func runLiveDrag(injector: SimulatorInjector, from: CGPoint, to: CGPoint, duration: TimeInterval) async throws {
        let session = try injector.makeLiveTouchSession()
        let distance = hypot(to.x - from.x, to.y - from.y)
        let steps = max(1, Int(distance / 10))
        let dx = (to.x - from.x) / CGFloat(steps)
        let dy = (to.y - from.y) / CGFloat(steps)
        let stepDelay = duration / Double(steps + 1)

        session.begin(at: from)
        for index in 1...steps {
            session.update(to: CGPoint(x: from.x + dx * CGFloat(index), y: from.y + dy * CGFloat(index)))
            try await Task.sleep(nanoseconds: UInt64(stepDelay * 1_000_000_000))
        }
        session.end(at: to)
        session.waitUntilIdle()
    }

    static let usage = """
    Usage:
      glidex list
      glidex probe
      glidex swift-probe
      glidex multitouch-probe --duration 10 --source default --mode 0
      glidex tap --x 120 --y 300
      glidex digitizer-tap --x 120 --y 300
      glidex drag --from 120,300 --to 120,700 --duration 0.5
      glidex live-drag --from 120,300 --to 120,700 --duration 0.5
      glidex pinch --center 200,400 --scale 1.2 --duration 0.5
      glidex recordings list [--directory "~/Library/Application Support/Glidex/Recordings"]
      glidex recordings replay --file recording.json [--udid DEVICE_UDID] [--rate 1.0]
    """
}

struct ArgumentCursor {
    private let args: [String]

    init(_ args: [String]) {
        self.args = args
    }

    func value(for flag: String) throws -> String {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else {
            throw GlidexError.usage("missing value for \(flag)")
        }
        return args[index + 1]
    }

    func double(for flag: String, defaultValue: Double? = nil) throws -> Double {
        if let index = args.firstIndex(of: flag) {
            guard index + 1 < args.count, let value = Double(args[index + 1]) else {
                throw GlidexError.usage("expected numeric value for \(flag)")
            }
            return value
        }
        if let defaultValue {
            return defaultValue
        }
        throw GlidexError.usage("missing numeric value for \(flag)")
    }

    func int(for flag: String, defaultValue: Int? = nil) throws -> Int {
        if let index = args.firstIndex(of: flag) {
            guard index + 1 < args.count, let value = Int(args[index + 1]) else {
                throw GlidexError.usage("expected integer value for \(flag)")
            }
            return value
        }
        if let defaultValue {
            return defaultValue
        }
        throw GlidexError.usage("missing integer value for \(flag)")
    }

    func string(for flag: String, defaultValue: String? = nil) throws -> String {
        if let index = args.firstIndex(of: flag), index + 1 < args.count {
            return args[index + 1]
        }
        if let defaultValue {
            return defaultValue
        }
        throw GlidexError.usage("missing value for \(flag)")
    }

    func optionalString(for flag: String) throws -> String? {
        guard let index = args.firstIndex(of: flag) else { return nil }
        guard index + 1 < args.count else {
            throw GlidexError.usage("missing value for \(flag)")
        }
        return args[index + 1]
    }

    func point(for flag: String) throws -> CGPoint {
        let raw = try value(for: flag)
        let parts = raw.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else {
            throw GlidexError.usage("expected \(flag) in x,y form")
        }
        return CGPoint(x: x, y: y)
    }
}

@MainActor
private final class CLIReplaySession {
    private let engine: GestureReplayEngine
    private var continuation: CheckedContinuation<Void, Error>?
    private var finished = false

    private init(sink: IndigoTouchSink) {
        self.engine = GestureReplayEngine(sink: sink)
        sink.onError = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.finish(.failure(GlidexError.commandFailed(message)))
            }
        }
    }

    static func replay(
        _ recording: GestureRecording,
        target: SimulatorTarget,
        sink: IndigoTouchSink,
        playbackRate: Double
    ) async throws {
        let session = CLIReplaySession(sink: sink)
        try await withCheckedThrowingContinuation { continuation in
            session.continuation = continuation
            do {
                try session.engine.play(
                    recording,
                    targetScreen: target.pointSize,
                    playbackRate: playbackRate
                ) { outcome in
                    switch outcome {
                    case .completed:
                        session.finish(.success(()))
                    case .stopped:
                        session.finish(.failure(GlidexError.commandFailed("gesture replay stopped")))
                    case let .failed(message):
                        session.finish(.failure(GlidexError.commandFailed(message)))
                    }
                }
            } catch {
                session.finish(.failure(error))
            }
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard !finished else { return }
        finished = true
        if case .failure = result {
            engine.stop()
        }
        continuation?.resume(with: result)
        continuation = nil
    }
}
