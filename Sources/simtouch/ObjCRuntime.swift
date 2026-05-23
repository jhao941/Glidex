import CSimTouchShim
import Foundation

enum ObjCRuntime {
    static func selectorNames(for cls: AnyClass) -> [String] {
        var pointer: UnsafeMutablePointer<UnsafePointer<CChar>?>?
        let count = st_copyMethodNames(cls, &pointer)
        guard count > 0, let pointer else {
            return []
        }
        defer { st_freeMethodNames(pointer, count) }
        return (0..<Int(count)).compactMap { index in
            guard let cString = pointer[index] else {
                return nil
            }
            return String(cString: cString)
        }.sorted()
    }

    static func typeEncoding(for cls: AnyClass, selector: String, isClassMethod: Bool = false) -> String? {
        guard let encoding = st_copyMethodTypeEncoding(cls, selector, isClassMethod) else {
            return nil
        }
        defer { free(UnsafeMutableRawPointer(mutating: encoding)) }
        return String(cString: encoding)
    }
}
