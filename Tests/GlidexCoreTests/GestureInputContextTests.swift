import Foundation
import GlidexCore
import Testing

@Suite("Gesture input context")
@MainActor
struct GestureInputContextTests {
    @Test("Option uses the mouse position captured at raw begin")
    func optionUsesMouseAnchor() throws {
        let fixture = try loadSwipe()
        let sink = ContextRecordingSink()
        var sampleCount = 0
        var sample = GestureInputSample(
            optionPressed: true,
            globalMouseLocation: DesktopPoint(x: 1_200, y: 700),
            captureMouseLocation: CapturePoint(x: 100, y: 674)
        )
        let coordinator = makeCoordinator(sink: sink) {
            sampleCount += 1
            return sample
        }

        fixture.forEach(coordinator.handleRawFrame)

        #expect(sink.firstSnapshot?.anchor == SimulatorPoint(x: 100, y: 200))
        #expect(sampleCount == 1)
        sample = .none
    }

    @Test("Option outside the capture area falls back to ordinary Navigate")
    func optionOutsideFallsBack() throws {
        let fixture = try loadSwipe()
        let optionSink = ContextRecordingSink()
        let ordinarySink = ContextRecordingSink()
        let option = makeCoordinator(sink: optionSink) {
            GestureInputSample(
                optionPressed: true,
                globalMouseLocation: DesktopPoint(x: -100, y: -100),
                captureMouseLocation: nil
            )
        }
        let ordinary = makeCoordinator(sink: ordinarySink) { .none }

        fixture.forEach(option.handleRawFrame)
        fixture.forEach(ordinary.handleRawFrame)

        #expect(optionSink.firstSnapshot?.anchor == ordinarySink.firstSnapshot?.anchor)
    }

    @Test("releasing Option during a gesture does not change its anchor")
    func optionIsLatched() throws {
        let fixture = try loadSwipe()
        let sink = ContextRecordingSink()
        var sampleCount = 0
        var sample = GestureInputSample(
            optionPressed: true,
            globalMouseLocation: DesktopPoint(x: 800, y: 600),
            captureMouseLocation: CapturePoint(x: 80, y: 774)
        )
        let coordinator = makeCoordinator(sink: sink) {
            sampleCount += 1
            return sample
        }

        for frame in fixture {
            coordinator.handleRawFrame(frame)
            if sink.firstSnapshot != nil {
                sample = GestureInputSample(
                    optionPressed: false,
                    globalMouseLocation: DesktopPoint(x: 1_400, y: 900),
                    captureMouseLocation: CapturePoint(x: 350, y: 100)
                )
            }
        }

        let anchors = sink.events.compactMap(\.snapshot).map(\.anchor)
        #expect(!anchors.isEmpty)
        #expect(Set(anchors.map { "\($0.x),\($0.y)" }).count == 1)
        #expect(anchors.first == SimulatorPoint(x: 80, y: 100))
        #expect(sampleCount == 1)
    }

    @Test("ordinary Navigate ignores mouse position")
    func navigateWithoutOptionIgnoresMouse() throws {
        let fixture = try loadSwipe()
        let firstSink = ContextRecordingSink()
        let secondSink = ContextRecordingSink()
        let first = makeCoordinator(sink: firstSink) {
            GestureInputSample(
                globalMouseLocation: DesktopPoint(x: 10, y: 10),
                captureMouseLocation: CapturePoint(x: 10, y: 10)
            )
        }
        let second = makeCoordinator(sink: secondSink) {
            GestureInputSample(
                globalMouseLocation: DesktopPoint(x: 1_000, y: 900),
                captureMouseLocation: CapturePoint(x: 390, y: 800)
            )
        }

        fixture.forEach(first.handleRawFrame)
        fixture.forEach(second.handleRawFrame)

        #expect(firstSink.firstSnapshot?.anchor == secondSink.firstSnapshot?.anchor)
    }

    @Test("Point and Edge ignore the temporary Option anchor")
    func persistentModesStayIsolated() throws {
        let fixture = try loadSwipe()
        let pointSink = ContextRecordingSink()
        let edgeSink = ContextRecordingSink()
        let sample = GestureInputSample(
            optionPressed: true,
            globalMouseLocation: DesktopPoint(x: 1_000, y: 700),
            captureMouseLocation: CapturePoint(x: 350, y: 100)
        )
        let point = makeCoordinator(sink: pointSink) { sample }
        point.setMode(.point)
        point.updatePointer(CapturePoint(x: 60, y: 774))
        let edge = makeCoordinator(sink: edgeSink) { sample }
        edge.setMode(.edge)
        edge.updatePointer(CapturePoint(x: 2, y: 437))

        fixture.forEach(point.handleRawFrame)
        fixture.forEach(edge.handleRawFrame)

        #expect(abs((pointSink.firstSnapshot?.anchor.x ?? 0) - 60) < 0.001)
        #expect(abs((pointSink.firstSnapshot?.anchor.y ?? 0) - 100) < 0.001)
        #expect(edgeSink.firstSnapshot?.anchor.x == 1)
    }

    @Test("Option sampling belongs only to raw gesture begin")
    func mouseInputDoesNotSampleOption() {
        let sink = ContextRecordingSink()
        var sampleCount = 0
        let coordinator = makeCoordinator(sink: sink) {
            sampleCount += 1
            return GestureInputSample(
                optionPressed: true,
                captureMouseLocation: CapturePoint(x: 300, y: 300)
            )
        }

        coordinator.beginMouse(at: CapturePoint(x: 20, y: 20))
        coordinator.endMouse(at: CapturePoint(x: 20, y: 20))

        #expect(sampleCount == 0)
        #expect(sink.firstSnapshot?.anchor.x == 20)
    }

    private func makeCoordinator(
        sink: ContextRecordingSink,
        provider: @escaping () -> GestureInputSample
    ) -> GestureCoordinator {
        GestureCoordinator(
            mapper: CoordinateMapper(
                captureRect: CGRect(x: 0, y: 0, width: 402, height: 874),
                simulatorSize: SimulatorPointSize(width: 402, height: 874)
            ),
            sink: sink,
            logger: Logger(),
            rawGestureInputProvider: provider
        )
    }

    private func loadSwipe() throws -> [RawTouchFrame] {
        struct Fixture: Decodable { let frames: [RawTouchFrame] }
        let url = try #require(Bundle.module.url(forResource: "swipe-right", withExtension: "json"))
        return try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)).frames
    }
}

private final class ContextRecordingSink: TouchSink {
    var events: [TouchLifecycleEvent] = []
    var firstSnapshot: TouchTransactionSnapshot? { events.first?.snapshot }
    func receive(_ event: TouchLifecycleEvent) { events.append(event) }
}

private extension TouchLifecycleEvent {
    var snapshot: TouchTransactionSnapshot {
        switch self {
        case let .begin(value), let .update(value), let .end(value), let .cancel(value): value
        }
    }
}
