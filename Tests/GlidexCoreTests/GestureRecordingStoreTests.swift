import Foundation
import Testing
@testable import GlidexCore

@Suite("Gesture recording store")
struct GestureRecordingStoreTests {
    @Test("saves atomically and loads newest recordings first")
    func saveAndList() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GestureRecordingStore(directoryURL: directory)

        let older = recording(name: "Pinch / Rotate", date: Date(timeIntervalSince1970: 100))
        let newer = recording(name: "Direct Touch", date: Date(timeIntervalSince1970: 200))
        let first = try store.save(older)
        let second = try store.save(newer)

        #expect(first.url.lastPathComponent.hasSuffix("-Pinch-Rotate.json"))
        #expect(second.url.lastPathComponent.hasSuffix("-Direct-Touch.json"))
        #expect(try store.recordings().map(\.recording) == [newer, older])
        #expect(try store.latest()?.recording == newer)
    }

    @Test("duplicate filenames receive a stable numeric suffix")
    func duplicateNames() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GestureRecordingStore(directoryURL: directory)
        let value = recording(name: "Tap", date: Date(timeIntervalSince1970: 100))

        let first = try store.save(value)
        let second = try store.save(value)

        #expect(first.url != second.url)
        #expect(second.url.deletingPathExtension().lastPathComponent.hasSuffix("-2"))
    }

    @Test("missing recording directory is an empty library")
    func missingDirectory() throws {
        let directory = temporaryDirectory().appendingPathComponent("missing")
        let store = GestureRecordingStore(directoryURL: directory)
        #expect(try store.recordings().isEmpty)
        #expect(try store.latest() == nil)
        try store.prepareDirectory()
        #expect(FileManager.default.fileExists(atPath: directory.path))
        try? FileManager.default.removeItem(at: directory.deletingLastPathComponent())
    }

    @Test("loads a compatible recording from an arbitrary JSON path")
    func loadExternalRecording() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = GestureRecordingStore(directoryURL: directory.appendingPathComponent("library"))
        let expected = recording(name: "Shared Gesture", date: Date(timeIntervalSince1970: 300))
        let externalURL = directory.appendingPathComponent("shared.json")
        try GestureRecordingCodec.encode(expected).write(to: externalURL, options: .atomic)

        let loaded = try store.load(from: externalURL)
        #expect(loaded.url == externalURL)
        #expect(loaded.recording == expected)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("GlidexRecordingStoreTests-\(UUID())", isDirectory: true)
    }

    private func recording(name: String, date: Date) -> GestureRecording {
        GestureRecording(
            name: name,
            recordedAt: date,
            sourceScreen: RecordingScreen(width: 100, height: 200),
            events: []
        )
    }
}
