//
//  SPUSecureCoding.h
//  Sparkle
//
//  Created by Mayur Pawashe on 3/24/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import <Foundation/Foundation.h>

// If we are using XPC without using XPC Services, our custom classes will not be (de)serialized automatically,
// hence needing functions to archive/unarchive NSSecureCoding objects.

NS_ASSUME_NONNULL_BEGIN

NSData * _Nullable SPUArchiveRootObjectSecurely(id<NSSecureCoding> rootObject);

id<NSSecureCoding> _Nullable SPUUnarchiveRootObjectSecurely(NSData *data, Class klass);

NS_ASSUME_NONNULL_END
