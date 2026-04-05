// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACErrorAttachmentLog+Utility.h"

// Exporting symbols for category.
NSString *MSACMSACErrorLogAttachmentLogUtilityCategory;

// This category is used to avoid adding more logic than needed to the model implementation file.
@implementation MSACErrorAttachmentLog (Utility)

+ (nonnull MSACErrorAttachmentLog *)attachmentWithText:(nonnull NSString *)text filename:(nullable NSString *)filename {
  return [[MSACErrorAttachmentLog alloc] initWithFilename:filename attachmentText:text];
}

+ (nonnull MSACErrorAttachmentLog *)attachmentWithBinary:(nonnull NSData *)data
                                                filename:(nullable NSString *)filename
                                             contentType:(nonnull NSString *)contentType {
  return [[MSACErrorAttachmentLog alloc] initWithFilename:filename attachmentBinary:data contentType:contentType];
}

@end
