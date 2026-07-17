import Foundation

public final class Logger: @unchecked Sendable {
    public init() {}
    private let lock = NSLock()
    private var entries: [String] = []
    private let entryLimit = 500
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public func info(_ message: String) {
        write(level: "INFO", message: message)
    }

    public func warn(_ message: String) {
        write(level: "WARN", message: message)
    }

    public func error(_ message: String) {
        write(level: "ERROR", message: message, toStandardError: true)
    }

    public func debug(_ message: String) {
        write(level: "DEBUG", message: message)
    }

    public func recentEntries() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    private func write(level: String, message: String, toStandardError: Bool = false) {
        lock.lock()
        let line = "[\(level)] \(dateFormatter.string(from: Date())) \(message)"
        entries.append(line)
        if entries.count > entryLimit {
            entries.removeFirst(entries.count - entryLimit)
        }
        lock.unlock()

        if toStandardError {
            fputs("\(line)\n", stderr)
            fflush(stderr)
        } else {
            print(line)
            fflush(stdout)
        }
    }
}
