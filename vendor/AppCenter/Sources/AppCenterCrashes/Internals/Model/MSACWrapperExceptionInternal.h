// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACSerializableObject.h"
#import "MSACWrapperException.h"

/**
 * MSACWrapperException must be serializable, but only internally (so that MSACSerializableObject does not need to be bound for wrapper
 * SDKs)
 */
@interface MSACWrapperException () <MSACSerializableObject>
@end
