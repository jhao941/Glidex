import AppKit
import ApplicationServices
import Foundation
import GlidexCore

struct CaptureDiagnostics {
    let snapshot: GlidexAppSnapshot
    let rawTouchStreamRunning: Bool
    let windowTrackingRunning: Bool
    let hostDescriptor: SimulatorDisplayDescriptor?
    let overlayFrame: CGRect
    let overlayVisible: Bool
    let compatibility: CompatibilitySelfCheck

    func report(recovery: String?) -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "Development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "SwiftPM"
        let target = snapshot.target
        let host = hostDescriptor
        let statusDetail: String
        switch snapshot.status {
        case let .waiting(reason): statusDetail = "Waiting: \(reason)"
        case .connecting: statusDetail = "Connecting"
        case .active: statusDetail = "Active"
        case .paused: statusDetail = "Paused"
        case let .error(error): statusDetail = "Error: \(error.message)"
        }

        var sections = [
            "Glidex\n" +
                "  Version: \(version) (\(build))\n" +
                "  macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\n" +
                "  Process: \(ProcessInfo.processInfo.processIdentifier)",
            "Runtime\n" +
                "  Status: \(statusDetail)\n" +
                "  Enabled: \(yesNo(snapshot.preferences.isEnabled))\n" +
                "  Input mode: \(snapshot.preferences.inputMode.rawValue)\n" +
                "  Calibration: \(yesNo(snapshot.isCalibrationMode))\n" +
                "  Active contacts: \(snapshot.activeTouches.count)",
            "Input Pipeline\n" +
                "  Accessibility trusted: \(yesNo(AXIsProcessTrusted()))\n" +
                "  Raw trackpad stream: \(running(rawTouchStreamRunning))\n" +
                "  Window tracking: \(running(windowTrackingRunning))\n" +
                "  HID target ready: \(yesNo(target != nil && snapshot.status == .active))",
            "Simulator\n" +
                "  Name: \(target?.name ?? "None")\n" +
                "  UDID: \(target?.udid ?? "None")\n" +
                "  Runtime: \(target?.runtime ?? host?.runtime ?? "Unknown")\n" +
                "  Device type: \(target?.deviceType ?? "Unknown")\n" +
                "  Point size: \(target.map { size($0.pointSize.cgSize) } ?? "Unknown")",
            "Display Host\n" +
                "  Kind: \(host.map { hostName($0.hostKind) } ?? "None")\n" +
                "  PID: \(host.map { String($0.ownerPID) } ?? "None")\n" +
                "  Window: \(host?.windowTitle ?? "Unknown")\n" +
                "  Xcode developer directory: \(host?.developerDirectory ?? "Unknown")\n" +
                "  Window frame: \(host.map { rect($0.windowFrame) } ?? "Unknown")\n" +
                "  Content frame: \(host.map { rect($0.contentFrame) } ?? "Unknown")\n" +
                "  Overlay frame: \(rect(overlayFrame))\n" +
                "  Overlay visible: \(yesNo(overlayVisible))",
            "Configuration\n" +
                "  Simulator targeting: \(snapshot.preferences.simulatorTargetingMode.rawValue)\n" +
                "  Pinned Simulator: \(snapshot.preferences.pinnedSimulatorUDID ?? "None")\n" +
                "  Pointer/visibility constraint: \(yesNo(snapshot.preferences.requiresPointerOverSimulator))\n" +
                "  Border: \(snapshot.preferences.borderVisibility.rawValue)\n" +
                "  Anchor indicator: \(yesNo(snapshot.preferences.showsAnchorIndicator))\n" +
                "  Touch indicators: \(yesNo(snapshot.preferences.showsActiveTouches))\n" +
                "  Anchor lock: \(snapshot.anchorLockState.rawValue)",
            "Compatibility Self-Check\n" +
                "  Overall: \(compatibility.overallStatus.rawValue)\n" +
                compatibility.checks.map {
                    "  [\($0.status.rawValue)] \($0.name): \($0.detail)"
                }.joined(separator: "\n"),
        ]
        if let recovery, !recovery.isEmpty {
            sections.append("Suggested Recovery\n  \(recovery)")
        }
        return sections.joined(separator: "\n\n")
    }

    private func yesNo(_ value: Bool) -> String { value ? "Yes" : "No" }
    private func running(_ value: Bool) -> String { value ? "Running" : "Stopped" }
    private func size(_ value: CGSize) -> String { "\(Int(value.width)) x \(Int(value.height))" }
    private func rect(_ value: CGRect) -> String {
        "x=\(Int(value.minX)) y=\(Int(value.minY)) w=\(Int(value.width)) h=\(Int(value.height))"
    }
    private func hostName(_ kind: SimulatorDisplayHostKind) -> String {
        switch kind {
        case .deviceHub: "Device Hub"
        case .legacySimulator: "Simulator"
        }
    }
}
