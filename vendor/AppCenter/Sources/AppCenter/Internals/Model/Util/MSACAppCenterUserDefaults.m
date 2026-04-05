// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACAppCenterUserDefaults.h"
#import "MSACAppCenterInternal.h"
#import "MSACAppCenterUserDefaultsPrivate.h"
#import "MSACLogger.h"

static NSString *const kMSACAppCenterUserDefaultsMigratedKeyFormat = @"310%@UserDefaultsMigratedKey";

static MSACAppCenterUserDefaults *sharedInstance = nil;
static dispatch_once_t onceToken;

@implementation MSACAppCenterUserDefaults

+ (instancetype)shared {
  dispatch_once(&onceToken, ^{
    sharedInstance = [[MSACAppCenterUserDefaults alloc] init];
  });
  return sharedInstance;
}

+ (void)resetSharedInstance {

  // Reset the once_token so dispatch_once will run again.
  onceToken = 0;
  sharedInstance = nil;
}

- (void)migrateKeys:(NSDictionary *)migratedKeys forService:(NSString *)service {
  NSNumber *serviceMigrated = [self objectForKey:[NSString stringWithFormat:kMSACAppCenterUserDefaultsMigratedKeyFormat, service]];
  if (serviceMigrated) {
    return;
  }
  MSACLogVerbose([MSACAppCenter logTag], @"Migrating the old NSDefaults keys to new ones.");
  for (NSObject *newKey in migratedKeys) {
    NSAssert([newKey isKindOfClass:[NSString class]], @"Unsupported type");
    id<NSObject> oldKey = migratedKeys[newKey];
    NSString *newKeyString = (NSString *)newKey;
    if ([oldKey isKindOfClass:[NSString class]]) {
      id value = [[NSUserDefaults standardUserDefaults] objectForKey:(NSString *)oldKey];
      [self swapKeys:(NSString *)oldKey newKey:newKeyString value:value];
    } else {
      NSAssert([oldKey isKindOfClass:[MSACUserDefaultsPrefixKey class]], @"Unsupported type");

      // List all the keys starting with oldKey.
      NSString *oldKeyPrefix = ((MSACUserDefaultsPrefixKey *)oldKey).keyPrefix;
      NSArray *userDefaultsDictionary = [[[NSUserDefaults standardUserDefaults] dictionaryRepresentation] allKeys];
      for (NSString *userDefaultsKey in userDefaultsDictionary) {
        if ([userDefaultsKey isKindOfClass:[NSString class]] && [userDefaultsKey hasPrefix:oldKeyPrefix]) {
          NSString *suffix = [userDefaultsKey substringFromIndex:[oldKeyPrefix length]];
          NSString *newKeyWithSuffix = [newKeyString stringByAppendingString:suffix];
          id value = [[NSUserDefaults standardUserDefaults] objectForKey:userDefaultsKey];
          [self swapKeys:userDefaultsKey newKey:newKeyWithSuffix value:value];
        }
      }
    }
  }
  [self setObject:@YES forKey:[NSString stringWithFormat:kMSACAppCenterUserDefaultsMigratedKeyFormat, service]];
}

- (void)swapKeys:(NSString *)oldKey newKey:(NSString *)newKey value:(id)value {
  if (value == nil) {
    return;
  }
  [[NSUserDefaults standardUserDefaults] setObject:value forKey:newKey];
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:oldKey];
  MSACLogVerbose([MSACAppCenter logTag], @"Migrating key %@ -> %@", oldKey, newKey);
}

- (NSString *)getAppCenterKeyFrom:(NSString *)key {
  NSAssert(![key hasPrefix:kMSACUserDefaultsPrefix], @"Please do not prepend the key with 'MSAppCenter'. It's done automatically.");
  return [kMSACUserDefaultsPrefix stringByAppendingString:key];
}

- (id)objectForKey:(NSString *)key {
  NSString *keyPrefixed = [self getAppCenterKeyFrom:key];
  return [[NSUserDefaults standardUserDefaults] objectForKey:keyPrefixed];
}

- (void)setObject:(id)value forKey:(NSString *)key {
  NSString *keyPrefixed = [self getAppCenterKeyFrom:key];
  [[NSUserDefaults standardUserDefaults] setObject:value forKey:keyPrefixed];
}

- (void)removeObjectForKey:(NSString *)key {
  NSString *keyPrefixed = [self getAppCenterKeyFrom:key];
  [[NSUserDefaults standardUserDefaults] removeObjectForKey:keyPrefixed];
}

@end

#pragma mark - Prefix key

@implementation MSACUserDefaultsPrefixKey

- (instancetype)initWithPrefix:(NSString *)prefix {
  if ((self = [super init])) {
    _keyPrefix = prefix;
  }
  return self;
}

- (id)copyWithZone:(nullable __unused NSZone *)zone {
  return [[MSACUserDefaultsPrefixKey alloc] initWithPrefix:self.keyPrefix];
}

@end
