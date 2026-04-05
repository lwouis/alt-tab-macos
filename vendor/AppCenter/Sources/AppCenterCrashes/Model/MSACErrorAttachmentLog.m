// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACCrashesUtil.h"
#import "MSACErrorAttachmentLog+Utility.h"
#import "MSACErrorAttachmentLogInternal.h"
#import "MSACUtility.h"

static NSString *const kMSACTextType = @"text/plain";

// API property names.
static NSString *const kMSACTypeAttachment = @"errorAttachment";
static NSString *const kMSACId = @"id";
static NSString *const kMSACErrorId = @"errorId";
static NSString *const kMSACContentType = @"contentType";
static NSString *const kMSACFileName = @"fileName";
static NSString *const kMSACData = @"data";

@implementation MSACErrorAttachmentLog

/**
 * @discussion Workaround for exporting symbols from category object files. See article
 * https://medium.com/ios-os-x-development/categories-in-static-libraries-78e41f8ddb96#.aedfl1kl0
 */
__attribute__((used)) static void importCategories() { [NSString stringWithFormat:@"%@", MSACMSACErrorLogAttachmentLogUtilityCategory]; }

- (instancetype)init {
  if ((self = [super init])) {
    self.type = kMSACTypeAttachment;
    _attachmentId = MSAC_UUID_STRING;
  }
  return self;
}

- (instancetype)initWithFilename:(nullable NSString *)filename attachmentBinary:(NSData *)data contentType:(NSString *)contentType {
  if ((self = [self init])) {
    _data = data;
    _contentType = contentType;
    _filename = filename;
  }
  return self;
}

- (instancetype)initWithFilename:(nullable NSString *)filename attachmentText:(NSString *)text {
  if ((self = [self init])) {
    self = [self initWithFilename:filename attachmentBinary:[text dataUsingEncoding:NSUTF8StringEncoding] contentType:kMSACTextType];
  }
  return self;
}

- (NSMutableDictionary *)serializeToDictionary {
  NSMutableDictionary *dict = [super serializeToDictionary];

  // Fill in the dictionary.
  if (self.attachmentId) {
    dict[kMSACId] = self.attachmentId;
  }
  if (self.errorId) {
    dict[kMSACErrorId] = self.errorId;
  }
  if (self.contentType) {
    dict[kMSACContentType] = self.contentType;
  }
  if (self.filename) {
    dict[kMSACFileName] = self.filename;
  }
  if (self.data) {
    dict[kMSACData] = [self.data base64EncodedStringWithOptions:NSDataBase64EncodingEndLineWithCarriageReturn];
  }
  return dict;
}

- (BOOL)isEqual:(id)object {
  if (![(NSObject *)object isKindOfClass:[MSACErrorAttachmentLog class]] && ![super isEqual:object])
    return NO;
  MSACErrorAttachmentLog *attachment = (MSACErrorAttachmentLog *)object;
  return ((!self.attachmentId && !attachment.attachmentId) || [self.attachmentId isEqualToString:attachment.attachmentId]) &&
         ((!self.errorId && !attachment.errorId) || [self.errorId isEqualToString:attachment.errorId]) &&
         ((!self.contentType && !attachment.contentType) || [self.contentType isEqualToString:attachment.contentType]) &&
         ((!self.filename && !attachment.filename) || [self.filename isEqualToString:attachment.filename]) &&
         ((!self.data && !attachment.data) || [self.data isEqualToData:attachment.data]);
}

- (BOOL)isValid {
  return [super isValid] && MSACLOG_VALIDATE_NOT_NIL(errorId) && MSACLOG_VALIDATE_NOT_NIL(attachmentId) && MSACLOG_VALIDATE_NOT_NIL(data) &&
         MSACLOG_VALIDATE_NOT_NIL(contentType);
}

#pragma mark - NSCoding

- (instancetype)initWithCoder:(NSCoder *)coder {
  self = [super initWithCoder:coder];
  if (self) {
    _attachmentId = [coder decodeObjectForKey:kMSACId];
    _errorId = [coder decodeObjectForKey:kMSACErrorId];
    _contentType = [coder decodeObjectForKey:kMSACContentType];
    _filename = [coder decodeObjectForKey:kMSACFileName];
    _data = [coder decodeObjectForKey:kMSACData];
  }
  return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
  [super encodeWithCoder:coder];
  [coder encodeObject:self.attachmentId forKey:kMSACId];
  [coder encodeObject:self.errorId forKey:kMSACErrorId];
  [coder encodeObject:self.contentType forKey:kMSACContentType];
  [coder encodeObject:self.filename forKey:kMSACFileName];
  [coder encodeObject:self.data forKey:kMSACData];
}

@end
