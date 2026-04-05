// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "MSACAbstractLogInternal.h"
#import "MSACErrorAttachmentLog.h"

/**
 * Error attachment log.
 */
@interface MSACErrorAttachmentLog ()

/**
 * Error attachment identifier.
 */
@property(nonatomic, copy) NSString *attachmentId;

/**
 * Error log identifier to attach this log to.
 */
@property(nonatomic, copy) NSString *errorId;

/**
 * Checks if the object's values are valid.
 *
 * @return YES, if the object is valid.
 */
- (BOOL)isValid;

@end
