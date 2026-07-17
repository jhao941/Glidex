import Foundation

public struct StoredGestureRecording: Equatable, Sendable {
    public let url: URL
    public let recording: GestureRecording

    public init(url: URL, recording: GestureRecording) {
        self.url = url
        self.recording = recording
    }
}

public final class GestureRecordingStore: @unchecked Sendable {
    public let directoryURL: URL

    private let fileManager: FileManager

    public init(directoryURL: URL, fileManager: FileManager = .default) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
    }

    public static func defaultDirectoryURL(fileManager: FileManager = .default) throws -> URL {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw GestureRecordingStoreError.applicationSupportUnavailable
        }
        return applicationSupport
            .appendingPathComponent("Glidex", isDirectory: true)
            .appendingPathComponent("Recordings", isDirectory: true)
    }

    @discardableResult
    public func save(_ recording: GestureRecording) throws -> StoredGestureRecording {
        try prepareDirectory()
        let data = try GestureRecordingCodec.encode(recording)
        let url = availableURL(for: recording)
        try data.write(to: url, options: .atomic)
        return StoredGestureRecording(url: url, recording: recording)
    }

    public func recordings() throws -> [StoredGestureRecording] {
        guard fileManager.fileExists(atPath: directoryURL.path) else { return [] }
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return try urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .map { url in
                let data = try Data(contentsOf: url)
                return StoredGestureRecording(
                    url: url,
                    recording: try GestureRecordingCodec.decode(data)
                )
            }
            .sorted {
                if $0.recording.recordedAt != $1.recording.recordedAt {
                    return $0.recording.recordedAt > $1.recording.recordedAt
                }
                return $0.url.lastPathComponent > $1.url.lastPathComponent
            }
    }

    public func latest() throws -> StoredGestureRecording? {
        try recordings().first
    }

    public func load(from url: URL) throws -> StoredGestureRecording {
        let data = try Data(contentsOf: url)
        return StoredGestureRecording(
            url: url,
            recording: try GestureRecordingCodec.decode(data)
        )
    }

    @discardableResult
    public func importRecording(from url: URL) throws -> StoredGestureRecording {
        try save(load(from: url).recording)
    }

    @discardableResult
    public func rename(_ stored: StoredGestureRecording, to name: String) throws -> StoredGestureRecording {
        let renamed = stored.recording.renamed(name)
        guard renamed.name != stored.recording.name else { return stored }
        let replacement = try save(renamed)
        do {
            try fileManager.removeItem(at: stored.url)
            return replacement
        } catch {
            try? fileManager.removeItem(at: replacement.url)
            throw error
        }
    }

    public func delete(_ stored: StoredGestureRecording) throws {
        try fileManager.removeItem(at: stored.url)
    }

    public func export(_ stored: StoredGestureRecording, to url: URL) throws {
        try GestureRecordingCodec.encode(stored.recording).write(to: url, options: .atomic)
    }

    public func prepareDirectory() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    private func availableURL(for recording: GestureRecording) -> URL {
        let timestamp = filenameTimestamp(for: recording.recordedAt)
        let baseName = "\(timestamp)-\(sanitized(recording.name))"
        var candidate = directoryURL.appendingPathComponent(baseName).appendingPathExtension("json")
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directoryURL
                .appendingPathComponent("\(baseName)-\(suffix)")
                .appendingPathExtension("json")
            suffix += 1
        }
        return candidate
    }

    private func sanitized(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let components = name
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
        return components.joined(separator: "-").prefix(80).description.nonEmpty ?? "recording"
    }

    private func filenameTimestamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }
}

public enum GestureRecordingStoreError: Error, Equatable, Sendable {
    case applicationSupportUnavailable
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
