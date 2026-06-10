#import "IndigoMessageBuilder.h"

#import <dlfcn.h>
#import <mach/mach_time.h>
#import <malloc/malloc.h>
#import <stddef.h>

static const unsigned int STButtonEventTypeDown = 0x1;
static const unsigned int STButtonEventTypeUp = 0x2;
static const unsigned int STTouchTarget = 0x32;
static const size_t STIndigoPayloadSize = 0xA0;
static const size_t STSingleTouchMessageSize = offsetof(IndigoMessage, payload) + (STIndigoPayloadSize * 2);
static const char *STSimulatorKitPath = "/Applications/Xcode.app/Contents/Developer/Library/PrivateFrameworks/SimulatorKit.framework/SimulatorKit";

#pragma mark - IndigoMessageBuilder

static unsigned int st_eventTypeForDirection(int direction) {
    return direction == 2 ? STButtonEventTypeUp : STButtonEventTypeDown;
}

static CGPoint st_screenRatioFromPoint(CGPoint point, CGSize screenPointSize) {
    return CGPointMake(point.x / screenPointSize.width, point.y / screenPointSize.height);
}

static STIndigoMessageForMouseNSEventFunc st_lookup_mouse_factory(const char **errorOut) {
    void *handle = dlopen(STSimulatorKitPath, RTLD_NOW | RTLD_LOCAL);
    if (handle == NULL) {
        if (errorOut != NULL) {
            *errorOut = strdup(dlerror());
        }
        return NULL;
    }
    void *symbol = dlsym(handle, "IndigoHIDMessageForMouseNSEvent");
    if (symbol == NULL && errorOut != NULL) {
        *errorOut = strdup("IndigoHIDMessageForMouseNSEvent not resolved in SimulatorKit handle");
    }
    return (STIndigoMessageForMouseNSEventFunc)symbol;
}

static IndigoMessage *st_touch_message_with_payload(IndigoTouch *payload, size_t *messageSizeOut) {
    IndigoMessage *message = calloc(1, STSingleTouchMessageSize);
    message->innerSize = (unsigned int)STIndigoPayloadSize;
    message->eventType = IndigoEventTypeTouch;
    message->payload.field1 = 0x0000000b;
    message->payload.timestamp = mach_absolute_time();

    memcpy(&(message->payload.event.touch), payload, sizeof(IndigoTouch));

    char *destination = (char *)&(message->payload);
    char *source = destination;
    destination += STIndigoPayloadSize;
    memcpy(destination, source, STIndigoPayloadSize);

    IndigoPayload *second = (IndigoPayload *)destination;
    second->event.touch.field1 = 0x00000001;
    second->event.touch.field2 = 0x00000002;

    if (messageSizeOut != NULL) {
        *messageSizeOut = STSingleTouchMessageSize;
    }
    return message;
}

void *st_create_indigo_touch_message(CGPoint point, CGSize screenPointSize, int direction, size_t *messageSizeOut, const char **errorOut) {
    STIndigoMessageForMouseNSEventFunc factory = st_lookup_mouse_factory(errorOut);
    if (factory == NULL) {
        return NULL;
    }

    CGPoint ratio = st_screenRatioFromPoint(point, screenPointSize);
    IndigoMessage *seed = factory(&ratio, NULL, STTouchTarget, st_eventTypeForDirection(direction), screenPointSize, 0);
    if (seed == NULL) {
        if (errorOut != NULL) {
            *errorOut = strdup("mouse factory returned NULL for single touch seed");
        }
        return NULL;
    }

    seed->payload.event.touch.xRatio = ratio.x;
    seed->payload.event.touch.yRatio = ratio.y;

    IndigoMessage *message = st_touch_message_with_payload(&(seed->payload.event.touch), messageSizeOut);
    free(seed);
    return message;
}

void *st_create_indigo_two_finger_touch_message(CGPoint finger1, CGPoint finger2, CGSize screenPointSize, int direction, size_t *messageSizeOut, const char **errorOut) {
    STIndigoMessageForMouseNSEventFunc factory = st_lookup_mouse_factory(errorOut);
    if (factory == NULL) {
        return NULL;
    }

    CGPoint ratio1 = st_screenRatioFromPoint(finger1, screenPointSize);
    CGPoint ratio2 = st_screenRatioFromPoint(finger2, screenPointSize);
    IndigoMessage *message = factory(&ratio1, &ratio2, STTouchTarget, st_eventTypeForDirection(direction), screenPointSize, 0);
    if (message == NULL) {
        if (errorOut != NULL) {
            *errorOut = strdup("mouse factory returned NULL for two-finger touch seed");
        }
        return NULL;
    }

    char *bytes = (char *)message;
    memcpy(bytes + 0x3C, &ratio1.x, sizeof(double));
    memcpy(bytes + 0x44, &ratio1.y, sizeof(double));
    memcpy(bytes + 0xDC, &ratio1.x, sizeof(double));
    memcpy(bytes + 0xE4, &ratio1.y, sizeof(double));
    memcpy(bytes + 0x17C, &ratio2.x, sizeof(double));
    memcpy(bytes + 0x184, &ratio2.y, sizeof(double));

    if (messageSizeOut != NULL) {
        *messageSizeOut = malloc_size(message);
    }
    return message;
}

const char *st_copy_indigo_message_description(void *message) {
    if (message == NULL) {
        return strdup("message=NULL");
    }

    IndigoMessage *typed = (IndigoMessage *)message;
    size_t size = malloc_size(message);
    NSMutableString *description = [NSMutableString stringWithFormat:
        @"size=0x%zx innerSize=0x%x eventType=0x%02x payload.field1=0x%x xRatio=%.6f yRatio=%.6f touch={field1=0x%x field2=0x%x field3=0x%x field9=0x%x field10=0x%x field11=0x%x field12=0x%x field13=0x%x}",
        size,
        typed->innerSize,
        typed->eventType,
        typed->payload.field1,
        typed->payload.event.touch.xRatio,
        typed->payload.event.touch.yRatio,
        typed->payload.event.touch.field1,
        typed->payload.event.touch.field2,
        typed->payload.event.touch.field3,
        typed->payload.event.touch.field9,
        typed->payload.event.touch.field10,
        typed->payload.event.touch.field11,
        typed->payload.event.touch.field12,
        typed->payload.event.touch.field13
    ];

    char *bytes = (char *)message;
    if (size >= 0x188) {
        double finger1X = 0;
        double finger1Y = 0;
        double digitizerX = 0;
        double digitizerY = 0;
        double finger2X = 0;
        double finger2Y = 0;
        memcpy(&finger1X, bytes + 0x3C, sizeof(double));
        memcpy(&finger1Y, bytes + 0x44, sizeof(double));
        memcpy(&digitizerX, bytes + 0xDC, sizeof(double));
        memcpy(&digitizerY, bytes + 0xE4, sizeof(double));
        memcpy(&finger2X, bytes + 0x17C, sizeof(double));
        memcpy(&finger2Y, bytes + 0x184, sizeof(double));
        [description appendFormat:@" multiTouch={finger1=(%.6f,%.6f) digitizer=(%.6f,%.6f) finger2=(%.6f,%.6f)}",
         finger1X, finger1Y, digitizerX, digitizerY, finger2X, finger2Y];
    }

    return strdup(description.UTF8String);
}
