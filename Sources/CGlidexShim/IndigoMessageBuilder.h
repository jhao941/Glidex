#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>

#import "IndigoWireFormat.h"

typedef void *(*STIndigoMessageForMouseNSEventFunc)(CGPoint *, CGPoint *, unsigned int, unsigned int, CGSize, unsigned int);

void *st_create_indigo_touch_message(CGPoint point, CGSize screenPointSize, int direction, size_t *messageSizeOut, const char **errorOut);
void *st_create_indigo_two_finger_touch_message(CGPoint finger1, CGPoint finger2, CGSize screenPointSize, int direction, size_t *messageSizeOut, const char **errorOut);
const char *st_copy_indigo_message_description(void *message);
