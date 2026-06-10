import CoreGraphics
import Foundation

struct SimulatorDevice: Decodable {
    public let udid: String
    let name: String
    let state: String
    let isAvailable: Bool?
    public let deviceTypeIdentifier: String?
    public let dataPath: String?
    let logPath: String?
    let lastBootedAt: String?
    public let runtime: String?

    var deviceTypeSummary: String {
        deviceTypeIdentifier ?? "unknown"
    }
}

struct SimctlListResponse: Decodable {
    let devices: [String: [SimulatorDevice]]
}

public struct BootedSimulatorRecord: Sendable {
    public let name: String
    public let udid: String
    public let runtime: String
    public let deviceType: String
    public let screenSize: CGSize?
    public let nativeResolution: CGSize?
    public let scale: Double?
    public let dataPath: String?
    public let source: String
}

public struct SimulatorTarget: Equatable, Sendable {
    public let name: String
    public let udid: String
    public let runtime: String
    public let deviceType: String
    public let pointSize: SimulatorPointSize

    public init(
        name: String,
        udid: String,
        runtime: String,
        deviceType: String,
        pointSize: SimulatorPointSize
    ) {
        self.name = name
        self.udid = udid
        self.runtime = runtime
        self.deviceType = deviceType
        self.pointSize = pointSize
    }

    public func withPointSize(_ pointSize: SimulatorPointSize) -> SimulatorTarget {
        SimulatorTarget(
            name: name,
            udid: udid,
            runtime: runtime,
            deviceType: deviceType,
            pointSize: pointSize
        )
    }
}

struct ScreenMetrics {
    let pointSize: CGSize
    let scale: Double
}
