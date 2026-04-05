//
//  SUReleaseNotesCommon.h
//  Sparkle
//
//  Created by Mayur Pawashe on 12/31/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

BOOL SUReleaseNotesIsSafeURL(NSURL *url, NSArray<NSString *> *customAllowedURLSchemes, BOOL *isAboutBlankURL);

NS_ASSUME_NONNULL_END

#endif
