//
//  SPUResumableUpdate.h
//  Sparkle
//
//  Created by Mayur Pawashe on 7/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@class SUAppcastItem;

@protocol SPUResumableUpdate <NSObject>

@property (nonatomic, readonly) SUAppcastItem *updateItem;
@property (nonatomic, readonly, nullable) SUAppcastItem *secondaryUpdateItem;

@end

NS_ASSUME_NONNULL_END
