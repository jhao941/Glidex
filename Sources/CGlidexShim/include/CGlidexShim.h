#import <CoreGraphics/CoreGraphics.h>
#import <objc/runtime.h>

typedef void *STObjCObject;
typedef STObjCObject (*STObjCMsgSendObjectFunc)(STObjCObject, SEL);
typedef STObjCObject (*STObjCMsgSendObjectObjectFunc)(STObjCObject, SEL, STObjCObject);
typedef STObjCObject (*STObjCMsgSendObjectObjectObjectPointerObjectFunc)(STObjCObject, SEL, STObjCObject, STObjCObject, void *, STObjCObject);
typedef void (*STObjCMsgSendVoidObjectFunc)(STObjCObject, SEL, STObjCObject);
typedef STObjCObject (*STObjCMsgSendObjectPointerFunc)(STObjCObject, SEL, const void *);
typedef STObjCObject (*STObjCMsgSendObjectPointerPointerFunc)(STObjCObject, SEL, const void *, void *);
typedef STObjCObject (*STObjCMsgSendClassObjectPointerFunc)(Class, SEL, STObjCObject, void *);
typedef STObjCObject (*STObjCMsgSendObjectUnsignedLongLongFunc)(STObjCObject, SEL, unsigned long long);
typedef STObjCObject (*STObjCMsgSendObjectObjectUnsignedLongLongFunc)(STObjCObject, SEL, STObjCObject, unsigned long long);
typedef void (*STObjCMsgSendVoidPointerBoolPointerBlockFunc)(STObjCObject, SEL, const void *, BOOL, STObjCObject, STObjCObject);
typedef STObjCObject (*STObjCMsgSendObjectCGRectFunc)(STObjCObject, SEL, CGRect);
typedef BOOL (*STObjCMsgSendBoolFunc)(STObjCObject, SEL);
typedef BOOL (*STObjCMsgSendBoolObjectFunc)(STObjCObject, SEL, STObjCObject);
typedef const char *(*STObjCMsgSendUTF8StringFunc)(STObjCObject, SEL);
typedef CGSize (*STObjCMsgSendCGSizeFunc)(STObjCObject, SEL);
typedef float (*STObjCMsgSendFloatFunc)(STObjCObject, SEL);
typedef double (*STObjCMsgSendDoubleFunc)(STObjCObject, SEL);
typedef void (*STHIDSendCompletionFunc)(void *context, const char *error);

void *st_objc_msgSend(void);
const char *st_class_getName(Class cls);
Class st_object_getClass(STObjCObject object);
unsigned int st_copyMethodNames(Class cls, const char ***namesOut);
void st_freeMethodNames(const char **names, unsigned int count);
const char *st_getObjCTypeDescription(STObjCObject obj);
const char *st_copyMethodTypeEncoding(Class cls, const char *selectorName, BOOL isClassMethod);
STObjCObject st_invokeObjectObjectUnsignedLongLongCatching(STObjCObject target, SEL selector, STObjCObject arg1, unsigned long long arg2, const char **exceptionOut);
void st_invokeVoidPointerBoolPointerBlockCatching(STObjCObject target, SEL selector, const void *arg1, BOOL arg2, STObjCObject arg3, STObjCObject arg4, const char **exceptionOut);
void st_set_indigo_mouse_factory(void *function);
void *st_create_indigo_touch_message(CGPoint point, CGSize screenPointSize, int direction, size_t *messageSizeOut, const char **errorOut);
void *st_create_indigo_two_finger_touch_message(CGPoint finger1, CGPoint finger2, CGSize screenPointSize, int direction, size_t *messageSizeOut, const char **errorOut);
const char *st_send_hid_message_sync(STObjCObject target, void *message, BOOL freeWhenDone, double timeoutSeconds);
const char *st_send_hid_message_async(STObjCObject target, void *message, BOOL freeWhenDone, void *context, STHIDSendCompletionFunc completion);
const char *st_copy_indigo_message_description(void *message);
void st_call_swift_digitizer_touch(void *function, STObjCObject digitizerView, const void *touchEvent, STObjCObject hidClient);
void st_call_swift_display_connect(void *function, STObjCObject displayView, STObjCObject screen, unsigned long inputs);
