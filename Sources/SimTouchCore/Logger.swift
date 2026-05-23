import Foundation

public final class Logger {
    public init() {}
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    public func info(_ message: String) {
        print("[INFO] \(timestamp()) \(message)")
    }

    public func warn(_ message: String) {
        print("[WARN] \(timestamp()) \(message)")
    }

    public func error(_ message: String) {
        fputs("[ERROR] \(timestamp()) \(message)\n", stderr)
    }

    public func debug(_ message: String) {
        print("[DEBUG] \(timestamp()) \(message)")
    }

    private func timestamp() -> String {
        dateFormatter.string(from: Date())
    }
}
