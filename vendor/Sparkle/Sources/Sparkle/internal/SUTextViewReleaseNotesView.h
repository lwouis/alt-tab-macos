//
//  SUTextViewReleaseNotesView.h
//  Sparkle
//
//  Created on 9/11/22.
//  Copyright © 2022 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS

#import <Foundation/Foundation.h>

#import "SUReleaseNotesView.h"

@protocol SPUStandardUserDriverDelegate;
@class SUAppcastItem;
@class SUHost;

NS_ASSUME_NONNULL_BEGIN

SPU_OBJC_DIRECT_MEMBERS @interface SUTextViewReleaseNotesView : NSObject <SUReleaseNotesView>

- (instancetype)initWithFontPointSize:(int)fontPointSize appcastItem:(SUAppcastItem *)appcastItem host:(SUHost *)host delegate:(id<SPUStandardUserDriverDelegate>)delegate prefersMarkdown:(BOOL)prefersMarkdown customAllowedURLSchemes:(NSArray<NSString *> *)customAllowedURLSchemes;

@end

NS_ASSUME_NONNULL_END

#endif
