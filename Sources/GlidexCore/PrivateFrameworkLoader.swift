import Darwin
import Foundation
import ObjectiveC.runtime

struct PrivateFrameworkHandle {
    let path: String
    let handle: UnsafeMutableRawPointer
}

final class PrivateFrameworkLoader {
    private let logger: Logger
    private(set) var loaded: [String: PrivateFrameworkHandle] = [:]

    init(logger: Logger) {
        self.logger = logger
    }

    func loadFramework(at path: String) throws -> PrivateFrameworkHandle {
        if let existing = loaded[path] {
            return existing
        }
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            let error = String(cString: dlerror())
            throw GlidexError.frameworkLoadFailed("failed to dlopen \(path): \(error)")
        }
        let framework = PrivateFrameworkHandle(path: path, handle: handle)
        loaded[path] = framework
        logger.info("loaded framework: \(path)")
        return framework
    }

    func symbol<T>(named name: String, in framework: PrivateFrameworkHandle, as type: T.Type) throws -> T {
        guard let raw = dlsym(framework.handle, name) else {
            throw GlidexError.symbolMissing("symbol not found: \(name) in \(framework.path)")
        }
        return unsafeBitCast(raw, to: type)
    }

    func classNamed(_ name: String) -> AnyClass? {
        NSClassFromString(name)
    }

    func selector(named name: String) -> Selector {
        NSSelectorFromString(name)
    }
}
