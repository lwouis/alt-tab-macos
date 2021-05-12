// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#ifndef MSAC_ENABLE_H
#define MSAC_ENABLE_H

#import <Foundation/Foundation.h>

/**
 * Protocol to define an instance that can be enabled/disabled.
 */
NS_SWIFT_NAME(Enable)
@protocol MSACEnable <NSObject>

@required

/**
 * Enable/disable this instance and delete data on disabled state.
 *
 * @param isEnabled  A boolean value set to YES to enable the instance or NO to disable it.
 * @param deleteData A boolean value set to YES to delete data or NO to keep it.
 */
- (void)setEnabled:(BOOL)isEnabled andDeleteDataOnDisabled:(BOOL)deleteData NS_SWIFT_NAME(setEnabled(_:deleteDataOnDisabled:));

@end

#endif
