/**
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <Foundation/Foundation.h>

#pragma pack(push, 4)

/**
 Indigo HID wire format — adapted from FBSimulatorControl's Indigo definitions.
 These structs intentionally model only the wire-level layout used by simtouch.
 */

typedef struct {
  double field1;
  double field2;
  double field3;
  double field4;
} IndigoQuad;

typedef struct {
  unsigned int field1;
  unsigned int field2;
  unsigned int field3;
  double xRatio;
  double yRatio;
  double field6;
  double field7;
  double field8;
  unsigned int field9;
  unsigned int field10;
  unsigned int field11;
  unsigned int field12;
  unsigned int field13;
  double field14;
  double field15;
  double field16;
  double field17;
  double field18;
} IndigoTouch;

typedef struct {
  unsigned int field1;
  double field2;
  double field3;
  double field4;
  unsigned int field5;
} IndigoWheel;

typedef struct {
  unsigned int eventSource;
  unsigned int eventType;
  unsigned int eventTarget;
  unsigned int keyCode;
  unsigned int field5;
} IndigoButton;

typedef struct {
  unsigned int field1;
  unsigned char field2[40];
} IndigoAccelerometer;

typedef struct {
  unsigned int field1;
  double field2;
  unsigned int field3;
  double field4;
} IndigoForce;

typedef struct {
  IndigoQuad dpad;
  IndigoQuad face;
  IndigoQuad shoulder;
  IndigoQuad joystick;
} IndigoGameController;

typedef union {
  IndigoTouch touch;
  IndigoWheel wheel;
  IndigoButton button;
  IndigoAccelerometer accelerometer;
  IndigoForce force;
  IndigoGameController gameController;
} IndigoEvent;

typedef struct {
  unsigned int field1;
  unsigned long long timestamp;
  unsigned int field3;
  IndigoEvent event;
} IndigoPayload;

typedef struct {
  char header[0x18];
  unsigned int innerSize;
  unsigned char eventType;
  char padding[3];
  IndigoPayload payload;
} IndigoMessage;

enum {
  IndigoEventTypeButton = 1,
  IndigoEventTypeTouch = 2,
  IndigoEventTypeUnknown = 3,
};

#pragma pack(pop)
