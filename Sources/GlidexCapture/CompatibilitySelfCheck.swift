import AppKit
import ApplicationServices
import Darwin
import Foundation
import GlidexCore

enum CompatibilityCheckStatus: String, Codable {
    case passed
    case warning
    case failed
}

struct CompatibilityCheck: Codable {
    let name: String
    let status: CompatibilityCheckStatus
    let detail: String
}

struct CompatibilitySelfCheck: Codable {
    enum OverallStatus: String, Codable {
        case compatible
        case limited
        case unavailable
    }

    let generatedAt: Date
    let overallStatus: OverallStatus
    let checks: [CompatibilityCheck]

    static func run(
        hostBundleURL: URL?,
        hostDetected: Bool,
        bootedSimulatorCount: Int,
        rawTouchStreamRunning: Bool,
        hidTargetReady: Bool
    ) -> CompatibilitySelfCheck {
        let resolution = DeveloperDirectoryResolver().resolve(hostBundleURL: hostBundleURL)
        let simulatorKitExists = resolution.map {
            FileManager.default.fileExists(atPath: $0.simulatorKitPath)
        } ?? false
        let multitouchPath = "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport"
        let multitouchLoadable = canLoadFramework(at: multitouchPath)
        var checks = [
            CompatibilityCheck(
                name: "Apple Silicon",
                status: isArm64 ? .passed : .failed,
                detail: isArm64 ? "arm64" : "Unsupported architecture"
            ),
            CompatibilityCheck(
                name: "Accessibility",
                status: AXIsProcessTrusted() ? .passed : .failed,
                detail: AXIsProcessTrusted() ? "Permission granted" : "Permission required"
            ),
            CompatibilityCheck(
                name: "SimulatorKit",
                status: simulatorKitExists ? .passed : .failed,
                detail: resolution?.simulatorKitPath ?? "Compatible framework not found"
            ),
            CompatibilityCheck(
                name: "MultitouchSupport",
                status: multitouchLoadable ? .passed : .failed,
                detail: multitouchLoadable
                    ? "Loadable (file or dyld shared cache)"
                    : multitouchPath
            ),
            CompatibilityCheck(
                name: "Simulator display host",
                status: hostDetected ? .passed : .warning,
                detail: hostDetected ? "Visible host detected" : "No visible Simulator window"
            ),
            CompatibilityCheck(
                name: "Booted Simulator",
                status: bootedSimulatorCount > 0 ? .passed : .warning,
                detail: "\(bootedSimulatorCount) booted device(s)"
            ),
            CompatibilityCheck(
                name: "Raw trackpad stream",
                status: rawTouchStreamRunning ? .passed : .warning,
                detail: rawTouchStreamRunning ? "Running" : "Not running"
            ),
            CompatibilityCheck(
                name: "HID target",
                status: hidTargetReady ? .passed : .warning,
                detail: hidTargetReady ? "Ready" : "Not attached"
            ),
        ]

        if simulatorKitExists {
            let requiredClasses = [
                "SimulatorKit.SimDeviceLegacyHIDClient",
                "SimulatorKit.SimDeviceScreen",
            ]
            for className in requiredClasses {
                let available = NSClassFromString(className) != nil
                checks.append(CompatibilityCheck(
                    name: className,
                    status: available || !hidTargetReady ? (available ? .passed : .warning) : .failed,
                    detail: available ? "Runtime class available" : "Runtime class not loaded"
                ))
            }
        }

        let overall: OverallStatus
        if checks.contains(where: { $0.status == .failed }) {
            overall = .unavailable
        } else if checks.contains(where: { $0.status == .warning }) {
            overall = .limited
        } else {
            overall = .compatible
        }
        return CompatibilitySelfCheck(generatedAt: Date(), overallStatus: overall, checks: checks)
    }

    private static var isArm64: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    private static func canLoadFramework(at path: String) -> Bool {
        guard let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else { return false }
        dlclose(handle)
        return true
    }
}
