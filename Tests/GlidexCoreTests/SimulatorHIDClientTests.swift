import Dispatch
import Foundation
import Testing
@testable import GlidexCore

@Suite("Simulator HID client")
struct SimulatorHIDClientTests {
    @Test("asynchronous completion errors reach the caller")
    func asyncCompletionErrorIsReported() async {
        let client = SimulatorHIDClient(rawClient: FailingHIDClient(), logger: Logger())

        await confirmation { completion in
            client.send(message: malloc(1)!, waitForCompletion: false) { error in
                #expect(error == "simulated HID failure")
                completion()
            }
        }
    }
}

private final class FailingHIDClient: NSObject {
    @objc(sendWithMessage:freeWhenDone:completionQueue:completion:)
    func send(
        message: UnsafeMutableRawPointer,
        freeWhenDone: Bool,
        completionQueue: DispatchQueue,
        completion: @escaping (NSError?) -> Void
    ) {
        if freeWhenDone {
            free(message)
        }
        completion(NSError(
            domain: "SimulatorHIDClientTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "simulated HID failure"]
        ))
    }
}
