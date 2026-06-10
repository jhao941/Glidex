import Foundation
import Testing
@testable import GlidexCore

private struct GestureFixture: Decodable {
    let name: String
    let mode: CaptureInputMode
    let pointer: CapturePoint?
    let frames: [RawTouchFrame]
}

@Suite("Raw frame replay")
@MainActor
struct GestureReplayTests {
    @Test("typical left and right swipes each produce one lifecycle", arguments: ["swipe-left", "swipe-right"])
    func ordinarySwipe(name: String) throws {
        let events = try replay(name)
        assertSingleLifecycle(events, expectedIntent: .navigate, contactCount: 1)
        #expect(events.filter(\.isTapLike).isEmpty)
    }

    @Test("rapid reversal remains one transaction")
    func rapidReversal() throws {
        let events = try replay("rapid-reversal")
        assertSingleLifecycle(events, expectedIntent: .navigate, contactCount: 1)
        #expect(events.filter(\.isTapLike).isEmpty)
    }

    @Test("pinch remains a two-contact transaction")
    func pinch() throws {
        let events = try replay("pinch")
        assertSingleLifecycle(events, expectedIntent: .pinch, contactCount: 2)
        #expect(events.first?.snapshot?.anchor == SimulatorPoint(x: 201, y: 437))
    }

    @Test("edge mode is explicit and isolated")
    func edge() throws {
        let events = try replay("edge-leading")
        assertSingleLifecycle(events, expectedIntent: .edge, contactCount: 1)
        guard case let .begin(snapshot) = events.first else {
            Issue.record("missing edge begin")
            return
        }
        #expect(snapshot.anchor.x == 1)
    }

    @Test("single-finger noise produces no transaction")
    func accidentalContact() throws {
        #expect(try replay("single-finger-noise").isEmpty)
    }

    @Test("Navigate ignores a previously moved pointer")
    func navigateIgnoresPointer() throws {
        let fixture = try load("swipe-right")
        let first = try replay(fixture, overridingPointer: CapturePoint(x: 10, y: 10))
        let second = try replay(fixture, overridingPointer: CapturePoint(x: 390, y: 790))
        #expect(first.first?.snapshot?.anchor == second.first?.snapshot?.anchor)
    }

    @Test("Navigate Edge and Disabled remain isolated for the same frames")
    func modeIsolation() throws {
        let fixture = try load("swipe-right")
        let navigate = try replay(fixture, overridingPointer: CapturePoint(x: 2, y: 437), overridingMode: .navigate)
        let edge = try replay(fixture, overridingPointer: CapturePoint(x: 2, y: 437), overridingMode: .edge)
        let disabled = try replay(fixture, overridingPointer: nil, overridingMode: .disabled)
        #expect(navigate.first?.snapshot?.intent == .navigate)
        #expect(edge.first?.snapshot?.intent == .edge)
        #expect(disabled.isEmpty)
    }

    private func replay(_ name: String) throws -> [TouchLifecycleEvent] {
        try replay(load(name), overridingPointer: nil, overridingMode: nil)
    }

    private func replay(
        _ fixture: GestureFixture,
        overridingPointer: CapturePoint?,
        overridingMode: CaptureInputMode? = nil
    ) throws -> [TouchLifecycleEvent] {
        let sink = ReplayRecordingSink()
        let coordinator = GestureCoordinator(
            mapper: CoordinateMapper(
                captureRect: CGRect(x: 0, y: 0, width: 402, height: 874),
                simulatorSize: SimulatorPointSize(width: 402, height: 874)
            ),
            sink: sink,
            logger: Logger()
        )
        coordinator.setMode(overridingMode ?? fixture.mode)
        if let pointer = overridingPointer ?? fixture.pointer {
            coordinator.updatePointer(pointer)
        }
        fixture.frames.forEach(coordinator.handleRawFrame)
        return sink.events
    }

    private func load(_ name: String) throws -> GestureFixture {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
        return try JSONDecoder().decode(GestureFixture.self, from: Data(contentsOf: url))
    }

    private func assertSingleLifecycle(
        _ events: [TouchLifecycleEvent],
        expectedIntent: GestureIntent,
        contactCount: Int
    ) {
        #expect(events.filter(\.isBegin).count == 1)
        #expect(events.filter(\.isEnd).count == 1)
        #expect(events.filter(\.isCancel).isEmpty)
        #expect(events.first?.snapshot?.intent == expectedIntent)
        #expect(events.first?.snapshot?.contacts.count == contactCount)
        #expect(events.last?.snapshot?.gestureID == events.first?.snapshot?.gestureID)
    }
}

private final class ReplayRecordingSink: TouchSink {
    private(set) var events: [TouchLifecycleEvent] = []
    func receive(_ event: TouchLifecycleEvent) { events.append(event) }
}

private extension TouchLifecycleEvent {
    var snapshot: TouchTransactionSnapshot? {
        switch self {
        case let .begin(value), let .update(value), let .end(value), let .cancel(value): value
        }
    }

    var isBegin: Bool { if case .begin = self { true } else { false } }
    var isEnd: Bool { if case .end = self { true } else { false } }
    var isCancel: Bool { if case .cancel = self { true } else { false } }
    var isTapLike: Bool { isBegin && snapshot?.source == .mouse }
}
