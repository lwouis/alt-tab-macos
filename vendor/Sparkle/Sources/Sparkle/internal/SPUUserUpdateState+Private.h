//
//  SPUUserUpdateState+Private.h
//  Sparkle
//
//  Created by Mayur Pawashe on 5/9/21.
//  Copyright © 2021 Sparkle Project. All rights reserved.
//

#ifndef SPUUserUpdateState_Private_h
#define SPUUserUpdateState_Private_h

#import "SPUUserUpdateState.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPUUserUpdateState (Private)

- (instancetype)initWithStage:(SPUUserUpdateStage)stage userInitiated:(BOOL)userInitiated;

@end

NS_ASSUME_NONNULL_END

#endif /* SPUUserUpdateState_Private_h */
