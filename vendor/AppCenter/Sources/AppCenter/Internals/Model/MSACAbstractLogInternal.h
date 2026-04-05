// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACAbstractLog.h"
#import "MSACAppCenterInternal.h"
#import "MSACCommonSchemaLog.h"
#import "MSACLog.h"
#import "MSACLogConversion.h"
#import "MSACSerializableObject.h"

#if __has_include(<AppCenter/MSACConstants.h>)
#import <AppCenter/MSACConstants.h>
#else
#import "MSACConstants.h"
#endif

@interface MSACAbstractLog () <MSACLog, MSACSerializableObject, MSACLogConversion>

/**
 * Serialize logs into a JSON string.
 *
 * @param prettyPrint boolean indicates pretty printing.
 *
 * @return A serialized string.
 */
- (NSString *)serializeLogWithPrettyPrinting:(BOOL)prettyPrint;

/**
 * Convert an AppCenter log to the Common Schema 3.0 event log per tenant token.
 *
 * @param token The tenant token.
 * @param flags Flags to set for the common schema log.
 *
 * @return A common schema log.
 */
- (MSACCommonSchemaLog *)toCommonSchemaLogForTargetToken:(NSString *)token flags:(MSACFlags)flags;

@end

#define MSACLOG_VALIDATE(fieldName, rule)                                                                                                  \
  ({                                                                                                                                       \
    BOOL isValid = rule;                                                                                                                   \
    if (!isValid) {                                                                                                                        \
      MSACLogVerbose([MSACAppCenter logTag], @"%@: \"%@\" is not valid.", NSStringFromClass([self class]), @ #fieldName);                  \
    }                                                                                                                                      \
    isValid;                                                                                                                               \
  })

#define MSACLOG_VALIDATE_NOT_NIL(fieldName) MSACLOG_VALIDATE(fieldName, self.fieldName != nil)
