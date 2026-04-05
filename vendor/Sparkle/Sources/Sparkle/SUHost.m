//
//  SUHost.m
//  Sparkle
//
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#import "SUHost.h"

#import "SUConstants.h"
#include <sys/mount.h> // For statfs for isRunningOnReadOnlyVolume
#import "SULog.h"
#import "SUSignatures.h"


#include "AppKitPrevention.h"

NS_ASSUME_NONNULL_BEGIN

// This class should not rely on AppKit and should also be process independent
// For example, it should not have code that tests writabilty to somewhere on disk,
// as that may depend on the privileges of the process owner. Or code that depends on
// if the process is sandboxed or not; eg: finding the user's caches directory. Or code that depends
// on compilation flags and if other files exist relative to the host bundle.

static void *SUHostObservableContext = &SUHostObservableContext;

@implementation SUHost
{
    NSUserDefaults *_userDefaults;
    NSSet<NSString *> *_observedUserDefaultKeyPaths;
    NSMutableSet<NSString *> *_modifyingKeyPaths;
    
    void (^_changeObservationHandler)(NSString *);
    
    BOOL _isMainBundle;
}

@synthesize bundle = _bundle;

- (instancetype)initWithBundle:(NSBundle *)aBundle
{
	if ((self = [super init]))
	{
        NSParameterAssert(aBundle);
        _bundle = aBundle;
        if (_bundle.bundleIdentifier == nil) {
            SULog(SULogLevelError, @"Error: the bundle being updated at %@ has no %@! This will cause preference read/write to not work properly.", _bundle, kCFBundleIdentifierKey);
        }
        
        _isMainBundle = [aBundle isEqualTo:[NSBundle mainBundle]];

        NSString *domainIdentifier;
        {
            NSString *defaultsDomain = [self objectForInfoDictionaryKey:SUDefaultsDomainKey ofClass:NSString.class];
            if (defaultsDomain != nil) {
                domainIdentifier = defaultsDomain;
            } else if (!_isMainBundle) {
                domainIdentifier = aBundle.bundleIdentifier;
            } else {
                domainIdentifier = nil;
            }
        }
        
        if (domainIdentifier == nil) {
            _userDefaults = [NSUserDefaults standardUserDefaults];
        } else {
            _userDefaults = [[NSUserDefaults alloc] initWithSuiteName:domainIdentifier];
        }
    }
    return self;
}

- (void)dealloc
{
    if (_observedUserDefaultKeyPaths != nil) {
        for (NSString *keyPath in _observedUserDefaultKeyPaths) {
            [_userDefaults removeObserver:self forKeyPath:keyPath];
        }
    }
}

- (void)observeChangesFromUserDefaultKeys:(NSSet<NSString *> *)keyPaths changeHandler:(void (^)(NSString *))changeHandler
{
    _modifyingKeyPaths = [NSMutableSet set];
    
    for (NSString *keyPath in keyPaths) {
        [_userDefaults addObserver:self forKeyPath:keyPath options:NSKeyValueObservingOptionNew context:SUHostObservableContext];
    }
    
    _observedUserDefaultKeyPaths = keyPaths;
    _changeObservationHandler = [changeHandler copy];
}

- (void)observeValueForKeyPath:(nullable NSString *)keyPath ofObject:(nullable id)object change:(nullable NSDictionary<NSKeyValueChangeKey,id> *)change context:(nullable void *)context
{
    if (context != SUHostObservableContext)
    {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    
    if (keyPath == nil || [_modifyingKeyPaths containsObject:(NSString * _Nonnull)keyPath]) {
        return;
    }
    
    if (_changeObservationHandler == nil) {
        return;
    }
    
    _changeObservationHandler((NSString * _Nonnull)keyPath);
}

- (NSString *)description { return [NSString stringWithFormat:@"%@ <%@>", [self class], [self bundlePath]]; }

- (NSString *)bundlePath
{
    return _bundle.bundlePath;
}

- (NSString * _Nonnull)name
{
    NSString *name;

    // Allow host bundle to provide a custom name
    name = [self objectForInfoDictionaryKey:@"SUBundleName" ofClass:NSString.class];
    if (name && name.length > 0) return name;

    name = [self objectForInfoDictionaryKey:@"CFBundleDisplayName" ofClass:NSString.class];
	if (name && name.length > 0) return name;

    name = [self objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleNameKey ofClass:NSString.class];
	if (name && name.length > 0) return name;

    return [[[NSFileManager defaultManager] displayNameAtPath:[self bundlePath]] stringByDeletingPathExtension];
}

- (BOOL)validVersion
{
    return [self isValidVersion:[self _version]];
}

- (BOOL)isValidVersion:(NSString * _Nullable)version SPU_OBJC_DIRECT
{
    return (version != nil && version.length != 0);
}

- (NSString * _Nullable)_version SPU_OBJC_DIRECT
{
    NSString *version = [self objectForInfoDictionaryKey:(__bridge NSString *)kCFBundleVersionKey ofClass:NSString.class];
    return ([self isValidVersion:version] ? version : nil);
}

- (NSString * _Nonnull)version
{
    NSString *version = [self _version];
    if (version == nil) {
        SULog(SULogLevelError, @"This host (%@) has no %@! This attribute is required.", [self bundlePath], (__bridge NSString *)kCFBundleVersionKey);
        // Instead of abort()-ing, return an empty string to satisfy the _Nonnull contract.
        return @"";
    }
    return version;
}

- (NSString * _Nonnull)displayVersion
{
    NSString *shortVersionString = [self objectForInfoDictionaryKey:@"CFBundleShortVersionString" ofClass:NSString.class];
    if (shortVersionString)
        return shortVersionString;
    else
        return [self version]; // Fall back on the normal version string.
}

- (BOOL)isRunningOnReadOnlyVolume
{
    struct statfs statfs_info;
    if (statfs(_bundle.bundlePath.fileSystemRepresentation, &statfs_info) != 0)
    {
        return NO;
    }
    
    return (statfs_info.f_flags & MNT_RDONLY) != 0;
}

- (BOOL)isRunningTranslocated
{
    NSString *path = _bundle.bundlePath;
    return [path rangeOfString:@"/AppTranslocation/"].location != NSNotFound;
}

- (NSString *_Nullable)publicEDKey SPU_OBJC_DIRECT
{
    return [self objectForInfoDictionaryKey:SUPublicEDKeyKey ofClass:NSString.class];
}

- (NSString *_Nullable)publicDSAKey SPU_OBJC_DIRECT
{
    // Maybe the key is just a string in the Info.plist.
    NSString *key = [self objectForInfoDictionaryKey:SUPublicDSAKeyKey ofClass:NSString.class];
	if (key) {
        return key;
    }

    // More likely, we've got a reference to a Resources file by filename:
    NSString *keyFilename = [self publicDSAKeyFileKey];
	if (!keyFilename) {
        return nil;
    }

    NSString *keyPath = [_bundle pathForResource:keyFilename ofType:nil];
    if (!keyPath) {
        return nil;
    }
    NSError *error = nil;
    key = [NSString stringWithContentsOfFile:keyPath encoding:NSASCIIStringEncoding error:&error];
    if (error) {
        SULog(SULogLevelError, @"Error loading %@: %@", keyPath, error);
    }
    return key;
}

- (BOOL)hasUpdateSecurityPolicy
{
    NSDictionary<NSString *, id> *updateSecurityPolicy = [self objectForInfoDictionaryKey:@"NSUpdateSecurityPolicy" ofClass:NSDictionary.class];
    
    return (updateSecurityPolicy != nil);
}

- (BOOL)requiresSignedAppcast
{
    return [self boolForInfoDictionaryKey:SURequireSignedFeedKey];
}

- (SUPublicKeys *)publicKeys
{
    return [[SUPublicKeys alloc] initWithEd:[self publicEDKey]
                                        dsa:[self publicDSAKey]];
}

- (NSString * _Nullable)publicDSAKeyFileKey
{
    return [self objectForInfoDictionaryKey:SUPublicDSAKeyFileKey ofClass:NSString.class];
}

static _Nullable id validateObject(id _Nullable object, NSSet<Class> * classes, NSString *key, NSString *keyType)
{
    if (object == nil) {
        return nil;
    }
    
    for (Class aClass in classes) {
        if ([(NSObject *)object isKindOfClass:aClass]) {
            return object;
        }
    }
    
    SULog(SULogLevelError, @"Error: Reading %@ key %@ with expected classes %@ but instead found %@", keyType, key, classes, ((NSObject *)object).className);
    
    return nil;
}

- (nullable id)objectForInfoDictionaryKey:(NSString *)key ofClasses:(NSSet<Class> *)classes SPU_OBJC_DIRECT
{
    id object;
    if (_isMainBundle) {
        // Common fast path - if we're updating the main bundle, that means our updater and host bundle's lifetime is the same
        // If the bundle happens to be updated or change, that means our updater process needs to be terminated first to do it safely
        // Thus we can rely on the cached Info dictionary
        object = [_bundle objectForInfoDictionaryKey:key];
    } else {
        // Slow path - if we're updating another bundle, we should read in the most up to date Info dictionary because
        // the bundle can be replaced externally or even by us.
        // This is the easiest way to read the Info dictionary values *correctly* despite some performance loss.
        // A mutable method to reload the Info dictionary at certain points and have it cached at other points is challenging to do correctly.
        CFDictionaryRef cfInfoDictionary = CFBundleCopyInfoDictionaryInDirectory((CFURLRef)_bundle.bundleURL);
        NSDictionary *infoDictionary = CFBridgingRelease(cfInfoDictionary);
        
        object = [infoDictionary objectForKey:key];
    }
    
    return validateObject(object, classes, key, @"info dictionary");
}

- (nullable id)objectForInfoDictionaryKey:(NSString *)key ofClass:(Class)aClass
{
    return [self objectForInfoDictionaryKey:key ofClasses:[NSSet setWithObject:aClass]];
}

static NSNumber * _Nullable convertObjectToBoolNumber(NSObject * _Nullable object, NSString *key, NSString *keyType)
{
    if (object == nil) {
        return nil;
    }
    
    if ([object isKindOfClass:NSNumber.class]) {
        return (NSNumber *)object;
    }
    
    if ([object isKindOfClass:NSString.class]) {
        return @(((NSString *)object).boolValue);
    }
    
    SULog(SULogLevelError, @"Error: Reading %@ key %@ expecting convertible bool but instead found class %@", keyType, key, ((NSObject *)object).className);
    
    return nil;
}

static NSNumber * _Nullable convertObjectToDoubleNumber(NSObject * _Nullable object, NSString *key, NSString *keyType)
{
    if (object == nil) {
        return nil;
    }
    
    if ([object isKindOfClass:NSNumber.class]) {
        return (NSNumber *)object;
    }
    
    if ([object isKindOfClass:NSString.class]) {
        return @(((NSString *)object).doubleValue);
    }
    
    SULog(SULogLevelError, @"Error: Reading %@ key %@ expecting convertible double but instead found class %@", keyType, key, ((NSObject *)object).className);
    
    return nil;
}

- (nullable NSNumber *)boolNumberForInfoDictionaryKey:(NSString *)key
{
    NSObject *object = [self objectForInfoDictionaryKey:key ofClasses:[NSSet setWithArray:@[NSNumber.class, NSString.class]]];
    return convertObjectToBoolNumber(object, key, @"info dictionary");
}

- (BOOL)boolForInfoDictionaryKey:(NSString *)key
{
    return [[self boolNumberForInfoDictionaryKey:key] boolValue];
}

- (nullable NSNumber *)doubleNumberForInfoDictionaryKey:(NSString *)key
{
    NSObject *object = [self objectForInfoDictionaryKey:key ofClasses:[NSSet setWithArray:@[NSNumber.class, NSString.class]]];
    return convertObjectToDoubleNumber(object, key, @"info dictionary");
}

- (nullable id)objectForUserDefaultsKey:(NSString *)defaultName ofClasses:(NSSet<Class> *)classes SPU_OBJC_DIRECT
{
    if (defaultName == nil || _userDefaults == nil) {
        return nil;
    }

    id object = [_userDefaults objectForKey:defaultName];
    return validateObject(object, classes, defaultName, @"user default");
}

- (nullable id)objectForUserDefaultsKey:(NSString *)defaultName ofClass:(Class)aClass
{
    return [self objectForUserDefaultsKey:defaultName ofClasses:[NSSet setWithObject:aClass]];
}

// Note this handles nil being passed for defaultName, in which case the user default will be removed
- (void)setObject:(nullable id)value forUserDefaultsKey:(NSString *)defaultName
{
    [_modifyingKeyPaths addObject:defaultName];
    
    [_userDefaults setObject:value forKey:defaultName];
    
    [_modifyingKeyPaths removeObject:defaultName];
}

- (nullable NSNumber *)boolNumberForUserDefaultsKey:(NSString *)key;
{
    NSObject *object = [self objectForUserDefaultsKey:key ofClasses:[NSSet setWithArray:@[NSNumber.class, NSString.class]]];
    return convertObjectToBoolNumber(object, key, @"user default");
}

- (BOOL)boolForUserDefaultsKey:(NSString *)defaultName
{
    return [[self boolNumberForUserDefaultsKey:defaultName] boolValue];
}

- (void)setBool:(BOOL)value forUserDefaultsKey:(NSString *)defaultName
{
    [_modifyingKeyPaths addObject:defaultName];
    
    [_userDefaults setBool:value forKey:defaultName];
    
    [_modifyingKeyPaths removeObject:defaultName];
}

- (nullable NSNumber *)doubleNumberForUserDefaultsKey:(NSString *)key
{
    NSObject *object = [self objectForUserDefaultsKey:key ofClasses:[NSSet setWithArray:@[NSNumber.class, NSString.class]]];
    return convertObjectToDoubleNumber(object, key, @"user default");
}

- (nullable id)objectForKey:(NSString *)key ofClass:(Class)aClass {
    id userDefaultsObject = [self objectForUserDefaultsKey:key ofClass:aClass];
    return userDefaultsObject != nil ? userDefaultsObject : [self objectForInfoDictionaryKey:key ofClass:aClass];
}

- (nullable NSNumber *)boolNumberForKey:(NSString *)key
{
    NSNumber *boolFromUserDefaults = [self boolNumberForUserDefaultsKey:key];
    return (boolFromUserDefaults != nil) ? boolFromUserDefaults : [self boolNumberForInfoDictionaryKey:key];
}

- (BOOL)boolForKey:(NSString *)key
{
    return [[self boolNumberForKey:key] boolValue];
}

- (nullable NSNumber *)doubleNumberForKey:(NSString *)key
{
    NSNumber *doubleFromUserDefaults = [self doubleNumberForUserDefaultsKey:key];
    return (doubleFromUserDefaults != nil) ? doubleFromUserDefaults : [self doubleNumberForInfoDictionaryKey:key];
}

@end

NS_ASSUME_NONNULL_END
