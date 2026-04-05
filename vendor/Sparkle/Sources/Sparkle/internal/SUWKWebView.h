//
//  SUWKWebView.h
//  Sparkle
//
//  Created by Mayur Pawashe on 12/30/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS

#import <Foundation/Foundation.h>
#import "SUReleaseNotesView.h"

NS_ASSUME_NONNULL_BEGIN

SPU_OBJC_DIRECT_MEMBERS @interface SUWKWebView : NSObject <SUReleaseNotesView>

- (instancetype)initWithColorStyleSheetLocation:(NSURL *)colorStyleSheetLocation fontFamily:(NSString *)fontFamily fontPointSize:(int)fontPointSize javaScriptEnabled:(BOOL)javaScriptEnabled customAllowedURLSchemes:(NSArray<NSString *> *)customAllowedURLSchemes allowsLoadingExternalReferences:(BOOL)allowsLoadingExternalReferences installedVersion:(NSString *)installedVersion;

@end

NS_ASSUME_NONNULL_END

#endif
