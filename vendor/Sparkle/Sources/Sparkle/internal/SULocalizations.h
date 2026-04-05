//
//  SULocalizations.h
//  Sparkle
//
//  Created by Mayur Pawashe on 2/28/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#ifndef SULocalizations_h
#define SULocalizations_h

#if SPARKLE_COPY_LOCALIZATIONS
    #import "SUConstants.h"

    // This should only be used from inside the framework (not helper tools)
    #define SUSparkleBundle() ((NSBundle * _Nonnull)([NSBundle bundleWithIdentifier:SUBundleIdentifier]))

    #define SPARKLE_TABLE @"Sparkle"

    #define SULocalizedStringFromTableInBundle(key, tbl, bundle, comment) (NSLocalizedStringFromTableInBundle(key, tbl, bundle, comment) ?: key)

#else
    #define SULocalizedStringFromTableInBundle(key, tbl, bundle, comment) key
#endif

#endif /* SULocalizations_h */
