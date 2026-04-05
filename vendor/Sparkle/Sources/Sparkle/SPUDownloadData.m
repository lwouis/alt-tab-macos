//
//  SPUDownloadData.m
//  Sparkle
//
//  Created by Mayur Pawashe on 8/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUDownloadData.h"


#include "AppKitPrevention.h"

static NSString *SPUDownloadDataKey = @"SPUDownloadData";
static NSString *SPUDownloadURLKey = @"SPUDownloadURL";
static NSString *SPUDownloadTextEncodingKey = @"SPUDownloadTextEncoding";
static NSString *SPUDownloadMIMETypeKey = @"SPUDownloadMIMEType";

@implementation SPUDownloadData

@synthesize data = _data;
@synthesize URL = _URL;
@synthesize textEncodingName = _textEncodingName;
@synthesize MIMEType = _MIMEType;

+ (BOOL)supportsSecureCoding
{
    return YES;
}

- (instancetype)initWithData:(NSData *)data URL:(NSURL *)URL textEncodingName:(NSString * _Nullable)textEncodingName MIMEType:(NSString *)MIMEType
{
    self = [super init];
    if (self != nil) {
        _data = data;
        _URL = URL;
        _textEncodingName = textEncodingName;
        _MIMEType = MIMEType;
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder
{
    [coder encodeObject:_data forKey:SPUDownloadDataKey];
    [coder encodeObject:_URL forKey:SPUDownloadURLKey];

    if (_textEncodingName != nil) {
        [coder encodeObject:_textEncodingName forKey:SPUDownloadTextEncodingKey];
    }
    
    if (_MIMEType != nil) {
        [coder encodeObject:_MIMEType forKey:SPUDownloadMIMETypeKey];
    }
}

- (nullable instancetype)initWithCoder:(NSCoder *)decoder
{
    NSData *data = [decoder decodeObjectOfClass:[NSData class] forKey:SPUDownloadDataKey];
    if (data == nil) {
        return nil;
    }

    NSURL *URL = [decoder decodeObjectOfClass:[NSURL class] forKey:SPUDownloadURLKey];
    if (URL == nil) {
        return nil;
    }

    NSString *textEncodingName = [decoder decodeObjectOfClass:[NSString class] forKey:SPUDownloadTextEncodingKey];
    
    NSString *MIMEType = [decoder decodeObjectOfClass:[NSString class] forKey:SPUDownloadMIMETypeKey];
    
    return [self initWithData:data URL:URL textEncodingName:textEncodingName MIMEType:MIMEType];
}

@end
