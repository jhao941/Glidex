import Foundation

public final class Logger: @unchecked Sendable {
    public init() {}
    private let lock = NSLock()
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public func info(_ message: String) {
        print("[INFO] \(timestamp()) \(message)")
        fflush(stdout)
    }

    public func warn(_ message: String) {
        print("[WARN] \(timestamp()) \(message)")
        fflush(stdout)
    }

    public func error(_ message: String) {
        fputs("[ERROR] \(timestamp()) \(message)\n", stderr)
    }

    public func debug(_ message: String) {
        print("[DEBUG] \(timestamp()) \(message)")
        fflush(stdout)
    }

    private func timestamp() -> String {
        lock.lock()
        defer { lock.unlock() }
        return dateFormatter.string(from: Date())
    }
}
