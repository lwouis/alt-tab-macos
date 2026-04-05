// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

@interface MSACCSEpochAndSeq : NSObject

@property(nonatomic) NSUInteger seq;
@property(nonatomic) NSString *epoch;

/**
 * Create a MSACCSEpochAndSeq with the given epoch.
 *
 * @param epoch The random unique UUID.
 *
 * @return A MSACCSEpochAndSeq with the given epoch and default seq to 0.
 */
- (instancetype)initWithEpoch:(NSString *)epoch;

@end
