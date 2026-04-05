//
//  SPUSecureCoding.m
//  Sparkle
//
//  Created by Mayur Pawashe on 3/24/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#import "SPUSecureCoding.h"
#import "SULog.h"


#include "AppKitPrevention.h"

static NSString *SURootObjectArchiveKey = @"SURootObjectArchive";

NSData * _Nullable SPUArchiveRootObjectSecurely(id<NSSecureCoding> rootObject)
{
    NSError *error = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:rootObject requiringSecureCoding:YES error:&error];
    if (data == nil) {
        SULog(SULogLevelError, @"Error while securely archiving object: %@", error);
    }
    return data;
}

id<NSSecureCoding> _Nullable SPUUnarchiveRootObjectSecurely(NSData *data, Class klass)
{
    NSError *error = nil;
    id<NSSecureCoding> rootObject = [NSKeyedUnarchiver unarchivedObjectOfClass:klass fromData:data error:&error];
    if (rootObject == nil) {
        SULog(SULogLevelError, @"Error while securely unarchiving object: %@", error);
    }
    return rootObject;
}
