import Foundation

public enum ActiveTouchIndicatorLifecycle {
    public static func contacts(for event: TouchLifecycleEvent) -> [TouchContactPoint] {
        switch event {
        case let .begin(snapshot), let .update(snapshot): snapshot.contacts
        case .end, .cancel: []
        }
    }
}

public final class TouchObservingSink: DeviceAwareTouchSink {
    private let downstream: TouchSink
    private let observer: (TouchLifecycleEvent) -> Void

    public init(
        downstream: TouchSink,
        observer: @escaping (TouchLifecycleEvent) -> Void
    ) {
        self.downstream = downstream
        self.observer = observer
    }

    public func receive(_ event: TouchLifecycleEvent) {
        downstream.receive(event)
        observer(event)
    }

    public func prepareForDeviceChange() {
        (downstream as? DeviceAwareTouchSink)?.prepareForDeviceChange()
    }
}
