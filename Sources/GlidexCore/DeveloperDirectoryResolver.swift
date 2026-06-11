import Foundation

public struct DeveloperDirectoryResolution: Equatable, Sendable {
    public var developerDirectory: String
    public var simulatorKitPath: String
}

public enum SimulatorKitFrameworkSwitch: Equatable, Sendable {
    case useRequested
    case alreadySelected
    case incompatibleLoadedFramework(String)

    public static func decide(loadedPath: String?, requestedPath: String) -> SimulatorKitFrameworkSwitch {
        guard let loadedPath else { return .useRequested }
        return loadedPath == requestedPath ? .alreadySelected : .incompatibleLoadedFramework(loadedPath)
    }
}

public struct DeveloperDirectoryResolver {
    private let fileExists: (String) -> Bool
    private let selectedDeveloperDirectory: () -> String?

    public init() {
        self.init(
            fileExists: { FileManager.default.fileExists(atPath: $0) },
            selectedDeveloperDirectory: {
            guard let data = try? ProcessRunner.run("/usr/bin/xcode-select", arguments: ["-p"]),
                  let value = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return value
            }
        )
    }

    public init(
        fileExists: @escaping (String) -> Bool,
        selectedDeveloperDirectory: @escaping () -> String?
    ) {
        self.fileExists = fileExists
        self.selectedDeveloperDirectory = selectedDeveloperDirectory
    }

    public func resolve(hostBundleURL: URL?) -> DeveloperDirectoryResolution? {
        var candidates: [String] = []
        if let hostBundleURL, let hostDeveloperDirectory = developerDirectory(containing: hostBundleURL) {
            candidates.append(hostDeveloperDirectory)
        }
        if let selected = selectedDeveloperDirectory() { candidates.append(selected) }
        candidates += [
            "/Applications/Xcode.app/Contents/Developer",
            "/Applications/Xcode-beta.app/Contents/Developer",
        ]

        for directory in candidates.uniqued() {
            for path in simulatorKitPaths(for: directory) where fileExists(path) {
                return DeveloperDirectoryResolution(
                    developerDirectory: directory,
                    simulatorKitPath: path
                )
            }
        }
        return nil
    }

    private func developerDirectory(containing bundleURL: URL) -> String? {
        var url: URL? = bundleURL.standardizedFileURL
        while let current = url {
            if current.pathExtension == "app", current.lastPathComponent.hasPrefix("Xcode") {
                return current.appendingPathComponent("Contents/Developer").path
            }
            url = current.deletingLastPathComponent()
            if url == current { break }
        }
        return nil
    }

    private func simulatorKitPaths(for developerDirectory: String) -> [String] {
        let developerURL = URL(fileURLWithPath: developerDirectory)
        let contentsURL = developerURL.deletingLastPathComponent()
        return [
            developerURL.appendingPathComponent("Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit").path,
            contentsURL.appendingPathComponent("SharedFrameworks/SimulatorKit.framework/SimulatorKit").path,
        ]
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
