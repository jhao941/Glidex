import Foundation

public final class IndigoTouchSink: DeviceAwareTouchSink, @unchecked Sendable {
    private enum ActiveSession {
        case single(LiveTouchSession)
        case twoFinger(LiveTwoFingerTouchSession)
        case directTouch(LiveDirectTouchSession)
    }

    private let injector: SimulatorInjector
    private let logger: Logger
    private var sessions: [UUID: ActiveSession] = [:]
    private var reusableSingleSession: LiveTouchSession?
    private var reusableTwoFingerSession: LiveTwoFingerTouchSession?
    private var reusableDirectTouchSession: LiveDirectTouchSession?
    public var onError: (@Sendable (String) -> Void)?

    public init(injector: SimulatorInjector, logger: Logger) {
        self.injector = injector
        self.logger = logger
    }

    public func receive(_ event: TouchLifecycleEvent) {
        logger.touch(event)
        switch event {
        case let .begin(snapshot):
            begin(snapshot)
        case let .update(snapshot):
            update(snapshot)
        case let .end(snapshot):
            finish(snapshot, cancelled: false)
        case let .cancel(snapshot):
            finish(snapshot, cancelled: true)
        }
    }

    public func prepareForDeviceChange() {
        for session in sessions.values {
            switch session {
            case let .single(session):
                session.cancel()
            case let .twoFinger(session):
                session.cancel()
            case let .directTouch(session):
                session.cancel()
            }
        }
        sessions.removeAll()
        reusableSingleSession = nil
        reusableTwoFingerSession = nil
        reusableDirectTouchSession = nil
        logger.info("touch sink prepared for device change")
    }

    private func begin(_ snapshot: TouchTransactionSnapshot) {
        guard sessions[snapshot.gestureID] == nil else {
            logger.warn("touch sink ignored duplicate begin gestureID=\(snapshot.gestureID)")
            return
        }

        do {
            if snapshot.intent == .directTouch {
                guard snapshot.contacts.count == 1 || snapshot.contacts.count == 2 else {
                    logger.warn("touch sink unsupported Direct Touch contact count=\(snapshot.contacts.count) gestureID=\(snapshot.gestureID)")
                    return
                }
                let session = try reusableDirectTouchSession ?? injector.makeLiveDirectTouchSession()
                session.onError = { [weak self] message in self?.onError?(message) }
                reusableDirectTouchSession = session
                sessions[snapshot.gestureID] = .directTouch(session)
                session.begin(contacts: snapshot.contacts)
                return
            }
            switch snapshot.contacts.count {
            case 1:
                let session = try reusableSingleSession ?? injector.makeLiveTouchSession()
                session.onError = { [weak self] message in self?.onError?(message) }
                reusableSingleSession = session
                sessions[snapshot.gestureID] = .single(session)
                session.begin(at: snapshot.contacts[0].point.cgPoint)
            case 2:
                let session = try reusableTwoFingerSession ?? injector.makeLiveTwoFingerTouchSession()
                session.onError = { [weak self] message in self?.onError?(message) }
                reusableTwoFingerSession = session
                sessions[snapshot.gestureID] = .twoFinger(session)
                session.begin(
                    finger1: snapshot.contacts[0].point.cgPoint,
                    finger2: snapshot.contacts[1].point.cgPoint
                )
            default:
                logger.warn("touch sink unsupported contact count=\(snapshot.contacts.count) gestureID=\(snapshot.gestureID)")
            }
        } catch {
            logger.error("touch sink begin failed gestureID=\(snapshot.gestureID): \(error)")
            onError?(String(describing: error))
        }
    }

    private func update(_ snapshot: TouchTransactionSnapshot) {
        guard let session = sessions[snapshot.gestureID] else { return }
        switch session {
        case let .single(session):
            guard let contact = snapshot.contacts.first else { return }
            session.update(to: contact.point.cgPoint)
        case let .twoFinger(session):
            guard snapshot.contacts.count >= 2 else { return }
            session.update(
                finger1: snapshot.contacts[0].point.cgPoint,
                finger2: snapshot.contacts[1].point.cgPoint
            )
        case let .directTouch(session):
            session.update(contacts: snapshot.contacts)
        }
    }

    private func finish(_ snapshot: TouchTransactionSnapshot, cancelled: Bool) {
        guard let session = sessions.removeValue(forKey: snapshot.gestureID) else { return }
        switch session {
        case let .single(session):
            if cancelled {
                session.cancel()
            } else {
                session.end(at: snapshot.contacts.first?.point.cgPoint)
            }
        case let .twoFinger(session):
            if cancelled {
                session.cancel()
            } else {
                session.end(
                    finger1: snapshot.contacts.first?.point.cgPoint,
                    finger2: snapshot.contacts.dropFirst().first?.point.cgPoint
                )
            }
        case let .directTouch(session):
            if cancelled {
                session.cancel()
            } else {
                session.end(contacts: snapshot.contacts)
            }
        }
    }
}
