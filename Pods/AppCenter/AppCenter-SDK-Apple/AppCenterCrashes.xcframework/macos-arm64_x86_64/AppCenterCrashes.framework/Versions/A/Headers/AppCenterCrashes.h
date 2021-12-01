// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#if __has_include(<AppCenterCrashes/MSACCrashes.h>)
#import <AppCenterCrashes/MSACCrashHandlerSetupDelegate.h>
#import <AppCenterCrashes/MSACCrashes.h>
#import <AppCenterCrashes/MSACCrashesDelegate.h>
#import <AppCenterCrashes/MSACErrorAttachmentLog+Utility.h>
#import <AppCenterCrashes/MSACErrorAttachmentLog.h>
#import <AppCenterCrashes/MSACExceptionModel.h>
#import <AppCenterCrashes/MSACStackFrame.h>
#import <AppCenterCrashes/MSACWrapperCrashesHelper.h>
#import <AppCenterCrashes/MSACWrapperExceptionModel.h>
#else
#import "MSACCrashHandlerSetupDelegate.h"
#import "MSACCrashes.h"
#import "MSACCrashesDelegate.h"
#import "MSACErrorAttachmentLog+Utility.h"
#import "MSACErrorAttachmentLog.h"
#import "MSACExceptionModel.h"
#import "MSACStackFrame.h"
#import "MSACWrapperCrashesHelper.h"
#import "MSACWrapperExceptionModel.h"
#endif
