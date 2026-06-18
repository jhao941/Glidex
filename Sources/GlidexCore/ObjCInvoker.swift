import CGlidexShim
import Foundation

enum ObjCInvoker {
    enum CatchResult<T> {
        case success(T)
        case failure(String)
    }

    static func withOutObject<T>(_ body: (UnsafeMutableRawPointer) -> T) -> (result: T, object: AnyObject?) {
        var rawObject: Unmanaged<AnyObject>?
        let result = withUnsafeMutablePointer(to: &rawObject) { pointer in
            body(UnsafeMutableRawPointer(pointer))
        }
        return (result, rawObject?.takeUnretainedValue())
    }

    private static func base() -> UnsafeMutableRawPointer {
        UnsafeMutableRawPointer(st_objc_msgSend())
    }

    static func object(_ target: AnyObject, _ selector: Selector) -> AnyObject? {
        let fn = unsafeBitCast(base(), to: STObjCMsgSendObjectFunc.self)
        return unsafeBitCast(fn(Unmanaged.passUnretained(target).toOpaque(), selector), to: AnyObject?.self)
    }

    static func bool(_ target: AnyObject, _ selector: Selector) -> Bool {
        let fn = unsafeBitCast(base(), to: STObjCMsgSendBoolFunc.self)
        return fn(Unmanaged.passUnretained(target).toOpaque(), selector).boolValue
    }

    static func size(_ target: AnyObject, _ selector: Selector) -> CGSize {
        let fn = unsafeBitCast(base(), to: STObjCMsgSendCGSizeFunc.self)
        return fn(Unmanaged.passUnretained(target).toOpaque(), selector)
    }

    static func float(_ target: AnyObject, _ selector: Selector) -> Float {
        let fn = unsafeBitCast(base(), to: STObjCMsgSendFloatFunc.self)
        return fn(Unmanaged.passUnretained(target).toOpaque(), selector)
    }

    static func double(_ target: AnyObject, _ selector: Selector) -> Double {
        let fn = unsafeBitCast(base(), to: STObjCMsgSendDoubleFunc.self)
        return fn(Unmanaged.passUnretained(target).toOpaque(), selector)
    }

    static func object(_ target: AnyObject, _ selector: Selector, object arg: AnyObject?) -> AnyObject? {
        let fn = unsafeBitCast(base(), to: STObjCMsgSendObjectObjectFunc.self)
        let raw = fn(
            Unmanaged.passUnretained(target).toOpaque(),
            selector,
            arg.map { Unmanaged.passUnretained($0).toOpaque() }
        )
        return unsafeBitCast(raw, to: AnyObject?.self)
    }

    static func object(
        _ target: AnyObject,
        _ selector: Selector,
        object arg1: AnyObject?,
        object arg2: AnyObject?,
        pointer arg3: UnsafeMutableRawPointer?,
        object arg4: AnyObject?
    ) -> AnyObject? {
        let fn = unsafeBitCast(base(), to: STObjCMsgSendObjectObjectObjectPointerObjectFunc.self)
        let raw = fn(
            Unmanaged.passUnretained(target).toOpaque(),
            selector,
            arg1.map { Unmanaged.passUnretained($0).toOpaque() },
            arg2.map { Unmanaged.passUnretained($0).toOpaque() },
            arg3,
            arg4.map { Unmanaged.passUnretained($0).toOpaque() }
        )
        return unsafeBitCast(raw, to: AnyObject?.self)
    }

    static func void(_ target: AnyObject, _ selector: Selector, object arg: AnyObject?) {
        let fn = unsafeBitCast(base(), to: STObjCMsgSendVoidObjectFunc.self)
        fn(
            Unmanaged.passUnretained(target).toOpaque(),
            selector,
            arg.map { Unmanaged.passUnretained($0).toOpaque() }
        )
    }

    static func object(_ target: AnyObject, _ selector: Selector, pointer arg: UnsafeRawPointer?) -> AnyObject? {
        let fn = unsafeBitCast(base(), to: STObjCMsgSendObjectPointerFunc.self)
        let raw = fn(Unmanaged.passUnretained(target).toOpaque(), selector, arg)
        return unsafeBitCast(raw, to: AnyObject?.self)
    }

    static func object(_ target: AnyObject, _ selector: Selector, object arg1: AnyObject?, pointer arg2: UnsafeMutableRawPointer?) -> AnyObject? {
        let fn = unsafeBitCast(base(), to: STObjCMsgSendObjectPointerPointerFunc.self)
        let raw = fn(
            Unmanaged.passUnretained(target).toOpaque(),
            selector,
            arg1.map { Unmanaged.passUnretained($0).toOpaque() },
            arg2
        )
        return unsafeBitCast(raw, to: AnyObject?.self)
    }

    static func classObjectPointer(_ cls: AnyClass, _ selector: Selector, object arg1: AnyObject?, pointer arg2: UnsafeMutableRawPointer?) -> AnyObject? {
        let fn = unsafeBitCast(base(), to: STObjCMsgSendClassObjectPointerFunc.self)
        let raw = fn(cls, selector, arg1.map { Unmanaged.passUnretained($0).toOpaque() }, arg2)
        return unsafeBitCast(raw, to: AnyObject?.self)
    }

    static func objectUnsignedLongLong(_ target: AnyObject, _ selector: Selector, value: UInt64) -> AnyObject? {
        let fn = unsafeBitCast(base(), to: STObjCMsgSendObjectUnsignedLongLongFunc.self)
        let raw = fn(Unmanaged.passUnretained(target).toOpaque(), selector, value)
        return unsafeBitCast(raw, to: AnyObject?.self)
    }

    static func objectObjectUnsignedLongLong(_ target: AnyObject, _ selector: Selector, object arg1: AnyObject?, value arg2: UInt64) -> AnyObject? {
        let fn = unsafeBitCast(base(), to: STObjCMsgSendObjectObjectUnsignedLongLongFunc.self)
        let raw = fn(
            Unmanaged.passUnretained(target).toOpaque(),
            selector,
            arg1.map { Unmanaged.passUnretained($0).toOpaque() },
            arg2
        )
        return unsafeBitCast(raw, to: AnyObject?.self)
    }

    static func objectCGRect(_ target: AnyObject, _ selector: Selector, rect: CGRect) -> AnyObject? {
        let fn = unsafeBitCast(base(), to: STObjCMsgSendObjectCGRectFunc.self)
        let raw = fn(Unmanaged.passUnretained(target).toOpaque(), selector, rect)
        return unsafeBitCast(raw, to: AnyObject?.self)
    }

    static func objectObjectUnsignedLongLongCatching(
        _ target: AnyObject,
        _ selector: Selector,
        object arg1: AnyObject?,
        value arg2: UInt64
    ) -> CatchResult<AnyObject?> {
        var exception: UnsafePointer<CChar>?
        let raw = st_invokeObjectObjectUnsignedLongLongCatching(
            Unmanaged.passUnretained(target).toOpaque(),
            selector,
            arg1.map { Unmanaged.passUnretained($0).toOpaque() },
            arg2,
            &exception
        )
        if let exception {
            defer { free(UnsafeMutableRawPointer(mutating: exception)) }
            return .failure(String(cString: exception))
        }
        return .success(unsafeBitCast(raw, to: AnyObject?.self))
    }

    static func voidPointerBoolPointerBlock(
        _ target: AnyObject,
        _ selector: Selector,
        pointer arg1: UnsafeRawPointer?,
        bool arg2: Bool,
        object arg3: AnyObject?,
        object arg4: AnyObject?
    ) {
        let fn = unsafeBitCast(base(), to: STObjCMsgSendVoidPointerBoolPointerBlockFunc.self)
        fn(
            Unmanaged.passUnretained(target).toOpaque(),
            selector,
            arg1,
            ObjCBool(arg2),
            arg3.map { Unmanaged.passUnretained($0).toOpaque() },
            arg4.map { Unmanaged.passUnretained($0).toOpaque() }
        )
    }

    static func voidPointerBoolPointerBlockCatching(
        _ target: AnyObject,
        _ selector: Selector,
        pointer arg1: UnsafeRawPointer?,
        bool arg2: Bool,
        object arg3: AnyObject?,
        object arg4: AnyObject?
    ) -> String? {
        var exception: UnsafePointer<CChar>?
        st_invokeVoidPointerBoolPointerBlockCatching(
            Unmanaged.passUnretained(target).toOpaque(),
            selector,
            arg1,
            arg2,
            arg3.map { Unmanaged.passUnretained($0).toOpaque() },
            arg4.map { Unmanaged.passUnretained($0).toOpaque() },
            &exception
        )
        guard let exception else {
            return nil
        }
        defer { free(UnsafeMutableRawPointer(mutating: exception)) }
        return String(cString: exception)
    }
}
