// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#ifndef MSAC_WRAPPER_EXCEPTION_MODEL_H
#define MSAC_WRAPPER_EXCEPTION_MODEL_H

#if __has_include(<AppCenterCrashes/MSACExceptionModel.h>)
#import <AppCenterCrashes/MSACExceptionModel.h>
#import <AppCenterCrashes/MSACWrapperExceptionModel.h>
#else
#import "MSACExceptionModel.h"
#import "MSACWrapperExceptionModel.h"
#endif

#if __has_include(<AppCenter/MSACSerializableObject.h>)
#import <AppCenter/MSACSerializableObject.h>
#else
#import "MSACSerializableObject.h"
#endif

@interface MSACWrapperExceptionModel : MSACExceptionModel

/*
 * Inner exceptions of this exception [optional].
 */
@property(nonatomic, strong) NSArray<MSACWrapperExceptionModel *> *innerExceptions;

/*
 * Name of the wrapper SDK that emitted this exception.
 * Consists of the name of the SDK and the wrapper platform, e.g. "appcenter.xamarin", "appcenter.react-native" [optional].
 */
@property(nonatomic, copy) NSString *wrapperSdkName;

@end

#endif
