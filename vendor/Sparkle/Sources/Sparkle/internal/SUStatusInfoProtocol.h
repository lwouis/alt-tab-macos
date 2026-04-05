//
//  SUStatusInfoProtocol.h
//  Sparkle
//
//  Created by Mayur Pawashe on 7/10/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol SUStatusInfoProtocol

- (void)probeStatusInfoWithReply:(void (^)(NSData * _Nullable installationInfoData))reply;

- (void)probeStatusConnectivityWithReply:(void (^)(void))reply;

@end

NS_ASSUME_NONNULL_END
