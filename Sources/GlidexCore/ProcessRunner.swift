import Foundation

enum ProcessRunner {
    @discardableResult
    static func run(_ launchPath: String, arguments: [String]) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        let err = stderr.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let text = String(data: err.isEmpty ? out : err, encoding: .utf8) ?? "unknown failure"
            throw GlidexError.commandFailed("\(launchPath) \(arguments.joined(separator: " ")) failed: \(text)")
        }
        return out
    }
}
