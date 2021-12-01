// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

#if __has_include(<AppCenter/MSACSerializableObject.h>)
#import <AppCenter/MSACSerializableObject.h>
#else
#import "MSACSerializableObject.h"
#endif

@interface MSACStackFrame : NSObject <MSACSerializableObject>

/*
 * Frame address [optional].
 */
@property(nonatomic, copy) NSString *address;

/*
 * Symbolized code line [optional].
 */
@property(nonatomic, copy) NSString *code;

/*
 * The fully qualified name of the Class containing the execution point represented by this stack trace element [optional].
 */
@property(nonatomic, copy) NSString *className;

/*
 * The name of the method containing the execution point represented by this stack trace element [optional].
 */
@property(nonatomic, copy) NSString *methodName;

/*
 * The line number of the source line containing the execution point represented by this stack trace element [optional].
 */
@property(nonatomic, copy) NSNumber *lineNumber;

/*
 * The name of the file containing the execution point represented by this stack trace element [optional].
 */
@property(nonatomic, copy) NSString *fileName;

@end
