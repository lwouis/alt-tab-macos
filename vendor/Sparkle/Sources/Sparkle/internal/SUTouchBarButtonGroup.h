//
//  SUTouchBarButtonGroup.h
//  Sparkle
//
//  Created by Yuxin Wang on 05/01/2017.
//  Copyright © 2017 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS || !BUILDING_SPARKLE

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

SPU_OBJC_DIRECT_MEMBERS @interface SUTouchBarButtonGroup : NSViewController

@property (nonatomic, readonly, copy) NSArray<NSButton *> *buttons;

- (instancetype)initByReferencingButtons:(NSArray<NSButton *> *)buttons;

@end

NS_ASSUME_NONNULL_END

#endif
