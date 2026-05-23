#import "CSimTouchShim.h"
#import "IndigoMessageBuilder.h"
#import "IndigoWireFormat.h"

#import <dispatch/dispatch.h>
#import <Foundation/Foundation.h>
#import <objc/message.h>

void *st_objc_msgSend(void) {
    return (void *)objc_msgSend;
}

const char *st_class_getName(Class cls) {
    return class_getName(cls);
}

Class st_object_getClass(STObjCObject object) {
    return object_getClass((__bridge id)object);
}

unsigned int st_copyMethodNames(Class cls, const char ***namesOut) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    if (count == 0 || methods == NULL) {
        *namesOut = NULL;
        return 0;
    }

    const char **buffer = calloc(count, sizeof(char *));
    for (unsigned int i = 0; i < count; i++) {
        SEL selector = method_getName(methods[i]);
        const char *name = sel_getName(selector);
        buffer[i] = name ? strdup(name) : strdup("");
    }
    free(methods);
    *namesOut = buffer;
    return count;
}

void st_freeMethodNames(const char **names, unsigned int count) {
    if (names == NULL) {
        return;
    }
    for (unsigned int i = 0; i < count; i++) {
        free((void *)names[i]);
    }
    free((void *)names);
}

const char *st_getObjCTypeDescription(STObjCObject obj) {
    if (obj == NULL) {
        return "nil";
    }
    return [[NSString stringWithFormat:@"%s", object_getClassName((__bridge id)obj)] UTF8String];
}

const char *st_copyMethodTypeEncoding(Class cls, const char *selectorName, BOOL isClassMethod) {
    if (cls == Nil || selectorName == NULL) {
        return NULL;
    }

    SEL selector = sel_registerName(selectorName);
    Method method = isClassMethod ? class_getClassMethod(cls, selector) : class_getInstanceMethod(cls, selector);
    if (method == NULL) {
        return NULL;
    }

    const char *encoding = method_getTypeEncoding(method);
    return encoding ? strdup(encoding) : NULL;
}

STObjCObject st_invokeObjectObjectUnsignedLongLongCatching(STObjCObject target, SEL selector, STObjCObject arg1, unsigned long long arg2, const char **exceptionOut) {
    @try {
        STObjCMsgSendObjectObjectUnsignedLongLongFunc fn = (STObjCMsgSendObjectObjectUnsignedLongLongFunc)objc_msgSend;
        return fn(target, selector, arg1, arg2);
    } @catch (NSException *exception) {
        if (exceptionOut != NULL) {
            *exceptionOut = strdup(exception.reason.UTF8String ?: "");
        }
        return NULL;
    }
}

void st_invokeVoidPointerBoolPointerBlockCatching(STObjCObject target, SEL selector, const void *arg1, BOOL arg2, STObjCObject arg3, STObjCObject arg4, const char **exceptionOut) {
    @try {
        STObjCMsgSendVoidPointerBoolPointerBlockFunc fn = (STObjCMsgSendVoidPointerBoolPointerBlockFunc)objc_msgSend;
        fn(target, selector, arg1, arg2, arg3, arg4);
    } @catch (NSException *exception) {
        if (exceptionOut != NULL) {
            *exceptionOut = strdup(exception.reason.UTF8String ?: "");
        }
    }
}

const char *st_send_hid_message_sync(STObjCObject target, void *message, BOOL freeWhenDone, double timeoutSeconds) {
    id object = (__bridge id)target;
    SEL selector = NSSelectorFromString(@"sendWithMessage:freeWhenDone:completionQueue:completion:");
    if (![object respondsToSelector:selector]) {
        return strdup("target does not respond to sendWithMessage:freeWhenDone:completionQueue:completion:");
    }

    typedef void (^CompletionBlock)(NSError *);
    typedef void (*SendFn)(id, SEL, void *, BOOL, dispatch_queue_t, CompletionBlock);
    SendFn fn = (SendFn)objc_msgSend;

    __block NSError *callbackError = nil;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    CompletionBlock completion = ^(NSError *error) {
        callbackError = error;
        dispatch_semaphore_signal(semaphore);
    };

    @try {
        fn(object, selector, message, freeWhenDone, dispatch_get_main_queue(), completion);
    } @catch (NSException *exception) {
        return strdup(exception.reason.UTF8String ?: "");
    }

    dispatch_time_t deadline = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeoutSeconds * NSEC_PER_SEC));
    long result = dispatch_semaphore_wait(semaphore, deadline);
    if (result != 0) {
        return strdup("timed out waiting for HID send completion");
    }
    if (callbackError != nil) {
        return strdup(callbackError.localizedDescription.UTF8String ?: "");
    }
    return NULL;
}

void st_call_swift_digitizer_touch(void *function, STObjCObject digitizerView, const void *touchEvent, STObjCObject hidClient) {
#if defined(__arm64__)
    register void *x0 __asm__("x0") = digitizerView;
    register const void *x1 __asm__("x1") = touchEvent;
    register void *x20 __asm__("x20") = hidClient;
    __asm__ volatile(
        "blr %3"
        : "+r"(x0), "+r"(x1), "+r"(x20)
        : "r"(function)
        : "x2", "x3", "x4", "x5", "x6", "x7", "x8", "x9", "x10", "x11", "x12", "x13", "x14", "x15", "x16", "x17", "x30",
          "v0", "v1", "v2", "v3", "v4", "v5", "v6", "v7", "memory");
#else
    (void)function;
    (void)digitizerView;
    (void)touchEvent;
    (void)hidClient;
#endif
}

void st_call_swift_display_connect(void *function, STObjCObject displayView, STObjCObject screen, unsigned long inputs) {
#if defined(__arm64__)
    register void *x0 __asm__("x0") = screen;
    register unsigned long x1 __asm__("x1") = inputs;
    register void *x20 __asm__("x20") = displayView;
    __asm__ volatile(
        "blr %3"
        : "+r"(x0), "+r"(x1), "+r"(x20)
        : "r"(function)
        : "x2", "x3", "x4", "x5", "x6", "x7", "x8", "x9", "x10", "x11", "x12", "x13", "x14", "x15", "x16", "x17", "x21", "x30",
          "v0", "v1", "v2", "v3", "v4", "v5", "v6", "v7", "memory");
#else
    (void)function;
    (void)displayView;
    (void)screen;
    (void)inputs;
#endif
}
