import CoreGraphics
import Foundation

struct SimulatorDevice: Decodable {
    let udid: String
    let name: String
    let state: String
    let isAvailable: Bool?
    let deviceTypeIdentifier: String?
    let dataPath: String?
    let logPath: String?
    let lastBootedAt: String?
    let runtime: String?

    var deviceTypeSummary: String {
        deviceTypeIdentifier ?? "unknown"
    }
}

struct SimctlListResponse: Decodable {
    let devices: [String: [SimulatorDevice]]
}

struct BootedSimulatorRecord {
    let name: String
    let udid: String
    let runtime: String
    let deviceType: String
    let screenSize: CGSize?
    let nativeResolution: CGSize?
    let scale: Double?
    let dataPath: String?
    let source: String
}
