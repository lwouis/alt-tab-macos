// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#import "AppCenter+Internal.h"
#import "MSACAbstractErrorLog.h"
#import "MSACNoAutoAssignSessionIdLog.h"

@class MSACThread, MSACBinary, MSACExceptionModel;

/**
 * Error log for Apple platforms.
 */
@interface MSACAppleErrorLog : MSACAbstractErrorLog <MSACNoAutoAssignSessionIdLog>

/**
 * CPU primary architecture.
 * Expected values are as follows:
 * public static primary_i386 = 0x00000007;
 * public static primary_x86_64 = 0x01000007;
 * public static primary_arm = 0x0000000C;
 * public static primary_arm64 = 0x0100000C;
 */
@property(nonatomic) NSNumber *primaryArchitectureId;

/**
 * CPU architecture variant [optional].
 *
 * If primary is arm64, the possible variants are
 * public static variant_arm64_1 = 0x00000000;
 * public static variant_arm64_2 = 0x0000000D;
 * public static variant_arm64_3 = 0x00000001;
 *
 * If primary is arm, the possible variants are
 * public static variant_armv6 = 0x00000006;
 * public static variant_armv7 = 0x00000009;
 * public static variant_armv7s = 0x0000000B;
 * public static variant_armv7k = 0x0000000C;
 */
@property(nonatomic) NSNumber *architectureVariantId;

/**
 * Path to the application.
 */
@property(nonatomic, copy) NSString *applicationPath;

/**
 * OS exception type.
 */
@property(nonatomic, copy) NSString *osExceptionType;

/**
 * OS exception code.
 */
@property(nonatomic, copy) NSString *osExceptionCode;

/**
 * OS exception address.
 */
@property(nonatomic, copy) NSString *osExceptionAddress;

/**
 * Exception type [optional].
 */
@property(nonatomic, copy) NSString *exceptionType;

/**
 * Exception reason [optional].
 */
@property(nonatomic, copy) NSString *exceptionReason;

/**
 * Content of register that might contain last method call [optional].
 */
@property(nonatomic, copy) NSString *selectorRegisterValue;

/**
 * Thread stack frames associated to the error [optional].
 */
@property(nonatomic) NSArray<MSACThread *> *threads;

/**
 * Binaries associated to the error [optional].
 */
@property(nonatomic) NSArray<MSACBinary *> *binaries;

/**
 * Registers. [optional]
 */
@property(nonatomic) NSDictionary<NSString *, NSString *> *registers;

/**
 * The last exception backtrace.
 */
@property(nonatomic) MSACExceptionModel *exception;

@end
