// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

// -reserved-id-macro
// PLCrashReporter uses lots of _-prefixed macros and it's not an issue but
// enabling -Weveryting being too pedantic.
// https://stackoverflow.com/questions/228783/what-are-the-rules-about-using-an-underscore-in-a-c-identifier
// explains rules about using an underscore macro pretty well.

// -disabled-macro-expansion
// This silences warnings when consuming PLCrashReporter for macOS. The warning
// here actually just complains about regular Preprocessor behavior.

// -objc-interface-ivars
// This causes warnings when consuming PLCrashReporter for macOS. It complains
// about the old way of defining private ivars. PLCrashReporter doesn't use ARC,
// so we cannot just remove the old ivars and be done. Changing PLCrashReporter
// just because of this warning doesn't make any sense.

// -documentation-unknown-command
// This causes 1 warning when consuming PLCrashReporter for macOS. The reason
// for the warning is that PLCRashReporter exposes Doxygen's @internal (it uses
// Doxygen to generate it's header docs) in a public header. There's no problem
// not knowing @internal, so we just ignore the warning.

// MSAC prefix for PLCrashReporter API is defined in PLCrashNamespace.h and handled
// implicitly by preprocessor, so all API calls can be done without explicit prefix usage.

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wreserved-id-macro"
#pragma clang diagnostic ignored "-Wdisabled-macro-expansion"
#pragma clang diagnostic ignored "-Wobjc-interface-ivars"
#pragma clang diagnostic ignored "-Wdocumentation-unknown-command"
#import "CrashReporter.h"
#pragma clang diagnostic pop
