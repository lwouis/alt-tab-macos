//
//  SPUDownloadDataPrivate.h
//  SPUDownloadDataPrivate
//
//  Created by Mayur Pawashe on 8/13/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPUDownloadData (Private)

- (instancetype)initWithData:(NSData *)data URL:(NSURL *)URL textEncodingName:(NSString * _Nullable)textEncodingName MIMEType:(NSString * _Nullable)MIMEType;

@end

NS_ASSUME_NONNULL_END
