// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#ifndef MSAC_APP_CENTER_ERRORS_H
#define MSAC_APP_CENTER_ERRORS_H

#import <Foundation/Foundation.h>

#define MSAC_APP_CENTER_BASE_DOMAIN @"com.Microsoft.AppCenter."

NS_ASSUME_NONNULL_BEGIN

#pragma mark - Domain

static NSString *const kMSACACErrorDomain = MSAC_APP_CENTER_BASE_DOMAIN @"ErrorDomain";

#pragma mark - General

// Error codes.
NS_ENUM(NSInteger){MSACACLogInvalidContainerErrorCode = 1, MSACACCanceledErrorCode = 2, MSACACDisabledErrorCode = 3};

// Error descriptions.
static NSString const *kMSACACLogInvalidContainerErrorDesc = @"Invalid log container.";
static NSString const *kMSACACCanceledErrorDesc = @"The operation was canceled.";
static NSString const *kMSACACDisabledErrorDesc = @"The service is disabled.";

#pragma mark - Connection

// Error codes.
NS_ENUM(NSInteger){MSACACConnectionPausedErrorCode = 100, MSACACConnectionHttpErrorCode = 101};

// Error descriptions.
static NSString const *kMSACACConnectionHttpErrorDesc = @"An HTTP error occured.";
static NSString const *kMSACACConnectionPausedErrorDesc = @"Canceled, connection paused with log deletion.";

// Error user info keys.
static NSString const *kMSACACConnectionHttpCodeErrorKey = @"MSConnectionHttpCode";

NS_ASSUME_NONNULL_END

#endif
