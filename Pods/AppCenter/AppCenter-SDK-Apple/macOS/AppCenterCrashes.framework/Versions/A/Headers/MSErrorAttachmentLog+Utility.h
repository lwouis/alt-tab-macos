// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSErrorAttachmentLog.h"

// Exporting symbols for category.
extern NSString *MSMSErrorLogAttachmentLogUtilityCategory;

@interface MSErrorAttachmentLog (Utility)

/**
 * Create an attachment with a given filename and text.
 *
 * @param filename The filename the attachment should get. If nil will get an automatically generated filename.
 * @param text The attachment text.
 *
 * @return An instance of `MSErrorAttachmentLog`.
 */
+ (MSErrorAttachmentLog *)attachmentWithText:(NSString *)text filename:(NSString *)filename;

/**
 * Create an attachment with a given filename and `NSData` object.
 *
 * @param filename The filename the attachment should get. If nil will get an automatically generated filename.
 * @param data The attachment data as NSData.
 * @param contentType The content type of your data as MIME type.
 *
 * @return An instance of `MSErrorAttachmentLog`.
 */
+ (MSErrorAttachmentLog *)attachmentWithBinary:(NSData *)data filename:(NSString *)filename contentType:(NSString *)contentType;

@end
