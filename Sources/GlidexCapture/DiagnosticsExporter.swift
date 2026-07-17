import Foundation

enum DiagnosticsExporter {
    static func export(
        report: String,
        compatibility: CompatibilitySelfCheck,
        recentLogs: [String],
        to archiveURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent("Glidex-Diagnostics-\(UUID().uuidString)", isDirectory: true)
        let folder = temporaryRoot.appendingPathComponent("Glidex Diagnostics", isDirectory: true)
        defer { try? fileManager.removeItem(at: temporaryRoot) }
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(report.utf8).write(
            to: folder.appendingPathComponent("diagnostics.txt"),
            options: .atomic
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(compatibility).write(
            to: folder.appendingPathComponent("compatibility.json"),
            options: .atomic
        )
        try Data(recentLogs.joined(separator: "\n").utf8).write(
            to: folder.appendingPathComponent("recent.log"),
            options: .atomic
        )

        try? fileManager.removeItem(at: archiveURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", folder.path, archiveURL.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8) ?? "ditto failed"
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}
