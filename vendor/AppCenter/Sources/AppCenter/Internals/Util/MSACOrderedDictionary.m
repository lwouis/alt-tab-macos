// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACOrderedDictionaryPrivate.h"

@implementation MSACOrderedDictionary

/*
 * Why are we implementing methods that are defined in our parent class?
 * From Apple's documentation at
 * https://developer.apple.com/library/archive/documentation/General/Conceptual/DevPedia-CocoaCore/ClassCluster.html
 * "You create and interact with instances of the cluster just as you would any other class. Behind the scenes, though, when you
 * create an instance of the public class, the class returns an object of the appropriate subclass based on the creation method that
 * you invoke. (You don’t, and can’t, choose the actual class of the instance.)"
 */

- (instancetype)init {
  if ((self = [super init])) {
    _dictionary = [NSMutableDictionary new];
    _order = [NSMutableArray new];
  }
  return self;
}

- (instancetype)initWithCapacity:(NSUInteger)numItems {
  self = [super init];
  if (self != nil) {
    _dictionary = [[NSMutableDictionary alloc] initWithCapacity:numItems];
    _order = [[NSMutableArray alloc] initWithCapacity:numItems];
  }
  return self;
}

- (void)setObject:(id)anObject forKey:(id<NSCopying>)aKey {
  if (!self.dictionary[aKey]) {
    [self.order addObject:aKey];
  }
  self.dictionary[aKey] = anObject;
}

- (NSEnumerator *)keyEnumerator {
  return [self.order objectEnumerator];
}

- (id)objectForKey:(id)key {
  return self.dictionary[key];
}

- (NSUInteger)count {
  return [self.dictionary count];
}

- (void)removeAllObjects {
  [self.dictionary removeAllObjects];
}

- (NSMutableDictionary *)mutableCopy {
  MSACOrderedDictionary *copy = [MSACOrderedDictionary new];
  copy.dictionary = [self.dictionary mutableCopy];
  copy.order = [self.order mutableCopy];
  return copy;
}

- (BOOL)isEqualToDictionary:(NSDictionary *)otherDictionary {
  if (![(NSObject *)otherDictionary isKindOfClass:[MSACOrderedDictionary class]] || !
                                                                                    [self.dictionary isEqualToDictionary:otherDictionary]) {
    return NO;
  }
  return [self.order isEqualToArray:((MSACOrderedDictionary *)otherDictionary).order];
}

@end
