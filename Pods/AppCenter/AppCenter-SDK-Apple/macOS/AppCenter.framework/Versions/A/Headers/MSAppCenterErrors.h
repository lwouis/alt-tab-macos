// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#ifndef MS_APP_CENTER_ERRORS_H
#define MS_APP_CENTER_ERRORS_H

#import <Foundation/Foundation.h>

#define MS_APP_CENTER_BASE_DOMAIN @"com.Microsoft.AppCenter."

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Domain

static NSString *const kMSACErrorDomain = MS_APP_CENTER_BASE_DOMAIN @"ErrorDomain";

#pragma mark - General

// Error codes.
NS_ENUM(NSInteger){MSACLogInvalidContainerErrorCode = 1, MSACCanceledErrorCode = 2, MSACDisabledErrorCode = 3};

// Error descriptions.
static NSString const *kMSACLogInvalidContainerErrorDesc = @"Invalid log container.";
static NSString const *kMSACCanceledErrorDesc = @"The operation was canceled.";
static NSString const *kMSACDisabledErrorDesc = @"The service is disabled.";

#pragma mark - Connection

// Error codes.
NS_ENUM(NSInteger){MSACConnectionPausedErrorCode = 100, MSACConnectionHttpErrorCode = 101};

// Error descriptions.
static NSString const *kMSACConnectionHttpErrorDesc = @"An HTTP error occured.";
static NSString const *kMSACConnectionPausedErrorDesc = @"Canceled, connection paused with log deletion.";

// Error user info keys.
static NSString const *kMSACConnectionHttpCodeErrorKey = @"MSACConnectionHttpCode";

NS_ASSUME_NONNULL_END

#endif
