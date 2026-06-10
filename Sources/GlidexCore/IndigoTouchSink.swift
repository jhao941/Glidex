import Foundation

public final class IndigoTouchSink: TouchSink {
    private enum ActiveSession {
        case single(LiveTouchSession)
        case twoFinger(LiveTwoFingerTouchSession)
    }

    private let injector: SimulatorInjector
    private let logger: Logger
    private var sessions: [UUID: ActiveSession] = [:]
    private var reusableSingleSession: LiveTouchSession?
    private var reusableTwoFingerSession: LiveTwoFingerTouchSession?

    public init(injector: SimulatorInjector, logger: Logger) {
        self.injector = injector
        self.logger = logger
    }

    public func receive(_ event: TouchLifecycleEvent) {
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

    private func begin(_ snapshot: TouchTransactionSnapshot) {
        guard sessions[snapshot.gestureID] == nil else {
            logger.warn("touch sink ignored duplicate begin gestureID=\(snapshot.gestureID)")
            return
        }

        do {
            switch snapshot.contacts.count {
            case 1:
                let session = try reusableSingleSession ?? injector.makeLiveTouchSession()
                reusableSingleSession = session
                sessions[snapshot.gestureID] = .single(session)
                session.begin(at: snapshot.contacts[0].point.cgPoint)
            case 2:
                let session = try reusableTwoFingerSession ?? injector.makeLiveTwoFingerTouchSession()
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
        }
    }
}
