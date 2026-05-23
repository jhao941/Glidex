import Foundation

final class Logger {
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func info(_ message: String) {
        print("[INFO] \(timestamp()) \(message)")
    }

    func warn(_ message: String) {
        print("[WARN] \(timestamp()) \(message)")
    }

    func error(_ message: String) {
        fputs("[ERROR] \(timestamp()) \(message)\n", stderr)
    }

    func debug(_ message: String) {
        print("[DEBUG] \(timestamp()) \(message)")
    }

    private func timestamp() -> String {
        dateFormatter.string(from: Date())
    }
}
