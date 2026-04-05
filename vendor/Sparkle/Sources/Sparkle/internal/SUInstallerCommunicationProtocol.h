//
//  SUInstallerCommunicationProtocol.h
//  Sparkle
//
//  Created by Mayur Pawashe on 7/9/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SUInstallerCommunicationProtocol

- (void)handleMessageWithIdentifier:(int32_t)identifier data:(NSData *)data;

@end

NS_ASSUME_NONNULL_END
