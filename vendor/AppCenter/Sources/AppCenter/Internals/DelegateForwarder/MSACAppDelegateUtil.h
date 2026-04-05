// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#if TARGET_OS_OSX
#import <AppKit/AppKit.h>

#ifndef MSACApplicationDelegate
#define MSACApplicationDelegate NSApplicationDelegate
#endif

#ifndef MSACApplication
#define MSACApplication NSApplication
#endif
#else
#import <UIKit/UIKit.h>

#ifndef MSACApplicationDelegate
#define MSACApplicationDelegate UIApplicationDelegate
#endif

#ifndef MSACApplication
#define MSACApplication UIApplication
#endif

#endif
