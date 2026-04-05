// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

/*
 * Authors:
 *  Landon Fuller <landonf@plausiblelabs.com>
 *  Damian Morris <damian@moso.com.au>
 *  Andreas Linde <mail@andreaslinde.de>
 *
 * Copyright (c) 2008-2013 Plausible Labs Cooperative, Inc.
 * Copyright (c) 2010 MOSO Corporation, Pty Ltd.
 * Copyright (c) 2012-2014 HockeyApp, Bit Stadium GmbH.
 * Copyright (c) 2015-16 Microsoft Corporation.
 *
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 */

#import <mach-o/dyld.h>
#import <mach-o/getsect.h>
#import <mach-o/ldsyms.h>

#if defined(__OBJC2__)
#define SEL_NAME_SECT "__objc_methname"
#else
#define SEL_NAME_SECT "__cstring"
#endif

#import "MSACAppCenterInternal.h"
#import "MSACAppleErrorLog.h"
#import "MSACBinary.h"
#import "MSACCrashReporter.h"
#import "MSACCrashesInternal.h"
#import "MSACDeviceTrackerPrivate.h"
#import "MSACErrorLogFormatterPrivate.h"
#import "MSACErrorReportPrivate.h"
#import "MSACExceptionModel.h"
#import "MSACStackFrame.h"
#import "MSACThread.h"
#import "MSACWrapperException.h"
#import "MSACWrapperExceptionManagerInternal.h"
#import "MSACWrapperSdkInternal.h"

static NSString *unknownString = @"???";

/**
 * Sort PLCrashReportBinaryImageInfo instances by their starting address.
 */
static NSInteger bit_binaryImageSort(id binary1, id binary2, void *__unused context) {
  uint64_t addr1 = [(PLCrashReportBinaryImageInfo *)binary1 imageBaseAddress];
  uint64_t addr2 = [(PLCrashReportBinaryImageInfo *)binary2 imageBaseAddress];

  if (addr1 < addr2)
    return NSOrderedAscending;
  else if (addr1 > addr2)
    return NSOrderedDescending;
  else
    return NSOrderedSame;
}

/**
 * Validates that the given @a string terminates prior to @a limit.
 */
static const char *safer_string_read(const char *string, const char *limit) {
  const char *p = string;
  do {
    if (p >= limit || p + 1 >= limit) {
      return NULL;
    }
    p++;
  } while (*p != '\0');

  return string;
}

/**
 * The relativeAddress should be `<ecx/rsi/r1/x1 ...> - <image base>`, extracted
 * from the crash report's thread
 * and binary image list.
 *
 * For the (architecture-specific) registers to attempt, see:
 *  http://sealiesoftware.com/blog/archive/2008/09/22/objc_explain_So_you_crashed_in_objc_msgSend.html
 */
static const char *findSEL(const char *imageName, NSString *imageUUID, uint64_t relativeAddress) {
  unsigned int images_count = _dyld_image_count();
  for (unsigned int i = 0; i < images_count; ++i) {
    intptr_t slide = _dyld_get_image_vmaddr_slide(i);
    const struct mach_header *header = _dyld_get_image_header(i);
    const struct mach_header_64 *header64 = (const struct mach_header_64 *)header;
    const char *name = _dyld_get_image_name(i);

    // Image disappeared?.
    if (name == NULL || header == NULL)
      continue;

    // Check if this is the correct image. If we were being even more careful,
    // we'd check the LC_UUID.
    if (strcmp(name, imageName) != 0)
      continue;

    // Determine whether this is a 64-bit or 32-bit Mach-O file.
    BOOL m64 = NO;
    if (header->magic == MH_MAGIC_64)
      m64 = YES;

    NSString *uuidString = nil;
    const uint8_t *command;
    uint32_t ncmds;

    if (m64) {
      command = (const uint8_t *)(header64 + 1);
      ncmds = header64->ncmds;
    } else {
      command = (const uint8_t *)(header + 1);
      ncmds = header->ncmds;
    }
    for (uint32_t idx = 0; idx < ncmds; ++idx) {
      const struct load_command *load_command = (const struct load_command *)command;
      if (load_command->cmd == LC_UUID) {
        const struct uuid_command *uuid_command = (const struct uuid_command *)command;
        const uint8_t *uuid = uuid_command->uuid;
        uuidString = [[NSString stringWithFormat:@"%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%"
                                                 @"02X%02X%02X%02X%02X",
                                                 uuid[0], uuid[1], uuid[2], uuid[3], uuid[4], uuid[5], uuid[6], uuid[7], uuid[8], uuid[9],
                                                 uuid[10], uuid[11], uuid[12], uuid[13], uuid[14], uuid[15]] lowercaseString];
        break;
      } else {
        command += load_command->cmdsize;
      }
    }

    // Check if this is the correct image by comparing the UUIDs.
    if (!uuidString || ![uuidString isEqualToString:imageUUID])
      continue;

    // Fetch the __objc_methname section.
    const char *methname_sect;
    uint64_t methname_sect_size;
    if (m64) {
      methname_sect = getsectdatafromheader_64(header64, SEG_TEXT, SEL_NAME_SECT, &methname_sect_size);
    } else {
      uint32_t meth_size_32;
      methname_sect = getsectdatafromheader(header, SEG_TEXT, SEL_NAME_SECT, &meth_size_32);
      methname_sect_size = meth_size_32;
    }

    // Apply the slide, as per getsectdatafromheader(3)
    methname_sect += slide;
    if (methname_sect == NULL) {
      return NULL;
    }

    // Calculate the target address within this image, and verify that it is
    // within __objc_methname.
    const char *target = ((const char *)header) + relativeAddress;
    const char *limit = methname_sect + methname_sect_size;
    if (target < methname_sect || target >= limit) {
      return NULL;
    }

    // Read the actual method name.
    return safer_string_read(target, limit);
  }

  return NULL;
}

@implementation MSACErrorLogFormatter

/**
 * Formats the provided report as human-readable text in the given @a
 * textFormat, and return the formatted result as a string.
 *
 * @param report The report to format.
 *
 * @return Returns the formatted result on success, or nil if an error occurs.
 */
+ (MSACAppleErrorLog *)errorLogFromCrashReport:(PLCrashReport *)report {
  MSACAppleErrorLog *errorLog = [MSACAppleErrorLog new];

  // errorId – Used for de-duplication in case we sent the same crashreport twice.
  errorLog.errorId = [self errorIdForCrashReport:report];

  // Set applicationpath and process info.
  errorLog = [self addProcessInfoAndApplicationPathTo:errorLog fromCrashReport:report];

  // Find the crashed thread.
  PLCrashReportThreadInfo *crashedThread = [self findCrashedThreadInReport:report];

  // Error Thread Id from the crashed thread.
  errorLog.errorThreadId = @(crashedThread.threadNumber);

  // errorLog.errorThreadName won't be used on iOS right now, this will be
  // relevant for handled exceptions.

  // All errors are fatal for now, until we add support for handled exceptions.
  errorLog.fatal = YES;

  // Application launch and crash timestamps
  errorLog.appLaunchTimestamp = [self getAppLaunchTimeFromReport:report];
  errorLog.timestamp = [self getCrashTimeFromReport:report];

  // FIXME: PLCrashReporter doesn't support millisecond precision, here is a
  // workaround to fill 999 for its millisecond.
  double timestampInSeconds = [errorLog.timestamp timeIntervalSince1970];
  if (timestampInSeconds - (int)timestampInSeconds == 0) {
    errorLog.timestamp = [NSDate dateWithTimeIntervalSince1970:(timestampInSeconds + 0.999)];
  }

  // CPU Type and Subtype for the crash. We need to query the binary images for that.
  uint64_t type = report.machineInfo.processorInfo.type;
  uint64_t subtype = report.machineInfo.processorInfo.subtype;
  for (PLCrashReportBinaryImageInfo *image in report.images) {
    if (image.codeType != nil && image.codeType.typeEncoding == PLCrashReportProcessorTypeEncodingMach) {
      type = image.codeType.type;
      subtype = image.codeType.subtype;
      break;
    }
  }
  BOOL is64bit = [self isCodeType64bit:type];
  errorLog.primaryArchitectureId = @(type);
  errorLog.architectureVariantId = @(subtype);

  /*
   * errorLog.architecture is an optional. The Android SDK will set it while for
   * iOS, the file will be set on the server using primaryArchitectureId and
   * architectureVariantId.
   */

  /*
   * HockeyApp didn't use report.exceptionInfo for this field but exception.name
   * in case of an unhandled exception or the report.signalInfo.name. More so,
   * for BITCrashDetails, we used the exceptionInfo.exceptionName for a field
   * called exceptionName.
   */
  errorLog.osExceptionType = report.signalInfo.name;
  errorLog.osExceptionCode = report.signalInfo.code;
  errorLog.osExceptionAddress = [NSString stringWithFormat:@"0x%" PRIx64, report.signalInfo.address];

  // We need the architecture of the system and the crashed thread to get the
  // exceptionReason, threads and registers.
  errorLog.exceptionReason = [self extractExceptionReasonFromReport:report];
  errorLog.exceptionType = report.hasExceptionInfo ? report.exceptionInfo.exceptionName : nil;

  // The registers of the crashed thread might contain the last method call,
  // this can be very helpful.
  errorLog.selectorRegisterValue = [self selectorRegisterValueFromReport:report ofCrashedThread:crashedThread codeType:type];

  // Extract all threads and registers.
  errorLog.threads = [self extractThreadsFromReport:report crashedThread:crashedThread is64bit:is64bit];
  errorLog.registers = [self extractRegistersFromCrashedThread:crashedThread is64bit:is64bit];
  errorLog.binaries = [self extractBinaryImagesFromReport:report is64bit:is64bit];

  /*
   * Set the device here to make sure we don't use the current device
   * information but the one from history that matches the time of our crash.
   */
  errorLog.device = [MSACErrorLogFormatter deviceForTimestamp:errorLog.timestamp crashReport:report];

  // Set the exception from the wrapper SDK.
  MSACWrapperException *wrapperException =
      [MSACWrapperExceptionManager loadWrapperExceptionWithUUIDString:[self uuidRefToString:report.uuidRef]];
  if (wrapperException) {
    errorLog.exception = wrapperException.modelException;
  }
  return errorLog;
}

+ (MSACErrorReport *)errorReportFromCrashReport:(PLCrashReport *)report {
  if (!report) {
    return nil;
  }

  MSACAppleErrorLog *errorLog = [self errorLogFromCrashReport:report];
  MSACErrorReport *errorReport = [self errorReportFromLog:errorLog];
  return errorReport;
}

+ (MSACErrorReport *)errorReportFromLog:(MSACAppleErrorLog *)errorLog {
  MSACErrorReport *errorReport = nil;
  NSString *errorId = errorLog.errorId;

  /*
   * There should always be an installId. Leaving the empty string out of
   * paranoia as [UUID UUID] – used in [MSACAppCenter installId] – might, in
   * theory, return nil.
   */
  NSString *reporterKey = [[MSACAppCenter installId] UUIDString] ?: @"";

  NSString *signal = errorLog.osExceptionType;
  NSString *exceptionReason = errorLog.exceptionReason;
  NSString *exceptionName = errorLog.exceptionType;
  NSDate *appStartTime = errorLog.appLaunchTimestamp;
  NSDate *appErrorTime = errorLog.timestamp;

  // Retrieve the process' id.
  NSUInteger processId = [errorLog.processId unsignedIntegerValue];

  // Finally create the MSACErrorReport instance.
  errorReport = [[MSACErrorReport alloc] initWithErrorId:errorId
                                             reporterKey:reporterKey
                                                  signal:signal
                                           exceptionName:exceptionName
                                         exceptionReason:exceptionReason
                                            appStartTime:appStartTime
                                            appErrorTime:appErrorTime
                                                  device:errorLog.device
                                    appProcessIdentifier:processId];

  return errorReport;
}

#pragma mark - Private

#pragma mark - Parse PLCrashReport

+ (NSString *)errorIdForCrashReport:(PLCrashReport *)report {
  NSString *errorId = report.uuidRef ? (NSString *)CFBridgingRelease(CFUUIDCreateString(NULL, report.uuidRef)) : MSAC_UUID_STRING;
  return errorId;
}

+ (MSACAppleErrorLog *)addProcessInfoAndApplicationPathTo:(MSACAppleErrorLog *)errorLog fromCrashReport:(PLCrashReport *)crashReport {
  // Set the defaults first.
  errorLog.processId = @(0);
  errorLog.processName = unknownString;
  errorLog.parentProcessName = unknownString;
  errorLog.parentProcessId = nil;
  errorLog.applicationPath = unknownString;

  // Convert PLCrashReport process information.
  if (crashReport.hasProcessInfo) {
    errorLog.processId = @(crashReport.processInfo.processID);
    errorLog.processName = crashReport.processInfo.processName ?: errorLog.processName;

    // Process Path.
    if (crashReport.processInfo.processPath != nil) {
      NSString *processPath = crashReport.processInfo.processPath;

// Remove username from the path
#if TARGET_OS_SIMULATOR || TARGET_OS_OSX || TARGET_OS_MACCATALYST
      processPath = [self anonymizedPathFromPath:processPath];
#endif
      errorLog.applicationPath = processPath;
    }

    // Parent Process Name.
    if (crashReport.processInfo.parentProcessName != nil) {
      errorLog.parentProcessName = crashReport.processInfo.parentProcessName;
    }
    // Parent Process ID.
    errorLog.parentProcessId = @(crashReport.processInfo.parentProcessID);
  }
  return errorLog;
}

+ (NSDate *)getAppLaunchTimeFromReport:(PLCrashReport *)report {
  return report.processInfo ? report.processInfo.processStartTime : report.systemInfo.timestamp;
}

+ (NSDate *)getCrashTimeFromReport:(PLCrashReport *)report {
  return report.systemInfo.timestamp;
}

+ (NSArray<MSACThread *> *)extractThreadsFromReport:(PLCrashReport *)report
                                      crashedThread:(PLCrashReportThreadInfo *)crashedThread
                                            is64bit:(BOOL)is64bit {
  NSMutableArray<MSACThread *> *formattedThreads = [NSMutableArray array];
  MSACExceptionModel *lastException = nil;

  // If CrashReport contains Exception, add the threads that belong to the
  // exception to the list of threads.
  if (report.exceptionInfo != nil && report.exceptionInfo.stackFrames != nil && [report.exceptionInfo.stackFrames count] > 0) {
    PLCrashReportExceptionInfo *exception = report.exceptionInfo;

    MSACThread *exceptionThread = [MSACThread new];
    exceptionThread.threadId = @(-1);

    // Gather frames from the thread's exception.
    for (PLCrashReportStackFrameInfo *frameInfo in exception.stackFrames) {
      MSACStackFrame *frame = [MSACStackFrame new];
      frame.address = [MSACErrorLogFormatter formatAddress:frameInfo.instructionPointer is64bit:is64bit];
      [exceptionThread.frames addObject:frame];
    }

    lastException = [MSACExceptionModel new];
    lastException.message = exception.exceptionReason;
    lastException.frames = exceptionThread.frames;
    lastException.type = report.exceptionInfo.exceptionName ?: report.signalInfo.name;

    /*
     * Don't add the thread to the array of threads (as in HockeyApp), the
     * exception will be added to the crashed thread instead.
     */
  }

  // Get all threads from the report (as opposed to the threads from the
  // exception).
  for (PLCrashReportThreadInfo *plCrashReporterThread in report.threads) {
    MSACThread *thread = [MSACThread new];
    thread.threadId = @(plCrashReporterThread.threadNumber);

    if ((lastException != nil) && (crashedThread != nil) && [thread.threadId isEqualToNumber:@(crashedThread.threadNumber)]) {
      thread.exception = lastException;
    }

    /*
     * Write out the frames. In raw reports, Apple writes this out as a simple
     * list of PCs. In the minimally post-processed report, Apple writes this
     * out as full frame entries. We use the latter format.
     */
    for (PLCrashReportStackFrameInfo *plCrashReporterFrameInfo in plCrashReporterThread.stackFrames) {
      MSACStackFrame *frame = [MSACStackFrame new];
      frame.address = [MSACErrorLogFormatter formatAddress:plCrashReporterFrameInfo.instructionPointer is64bit:is64bit];
      frame.code = [self formatStackFrame:plCrashReporterFrameInfo report:report];
      [thread.frames addObject:frame];
    }

    [formattedThreads addObject:thread];
  }

  return formattedThreads;
}

/**
 * Format a stack frame for display in a thread backtrace.
 *
 * @param frameInfo The stack frame to format
 * @param report The report from which this frame was acquired.
 *
 * @return Returns a formatted frame line.
 */
+ (NSString *)formatStackFrame:(PLCrashReportStackFrameInfo *)frameInfo report:(PLCrashReport *)report {

  /*
   * Base image address containing instrumentation pointer, offset of the IP
   * from that base address, and the associated image name.
   */
  uint64_t baseAddress = 0x0;
  uint64_t pcOffset = 0x0;
  NSString *symbolString = nil;

  PLCrashReportBinaryImageInfo *imageInfo = [report imageForAddress:frameInfo.instructionPointer];
  if (imageInfo != nil) {
    baseAddress = imageInfo.imageBaseAddress;
    pcOffset = frameInfo.instructionPointer - imageInfo.imageBaseAddress;
  } else if (frameInfo.instructionPointer) {
    MSACLogWarning([MSACCrashes logTag], @"Cannot find image for 0x%" PRIx64, frameInfo.instructionPointer);
  }

  /*
   * If symbol info is available, the format used in Apple's reports is Sym +
   * OffsetFromSym. Otherwise, the format used is imageBaseAddress + offsetToIP.
   */
  MSACBinaryImageType imageType = [self imageTypeForImagePath:imageInfo.imageName processPath:report.processInfo.processPath];
  if (frameInfo.symbolInfo != nil && imageType == MSACBinaryImageTypeOther) {
    NSString *symbolName = frameInfo.symbolInfo.symbolName;

    // Apple strips the _ symbol prefix in their reports.
    if ([symbolName rangeOfString:@"_"].location == 0 && [symbolName length] > 1) {
      switch (report.systemInfo.operatingSystem) {
      case PLCrashReportOperatingSystemMacOSX:
      case PLCrashReportOperatingSystemiPhoneOS:
      case PLCrashReportOperatingSystemAppleTVOS:
      case PLCrashReportOperatingSystemiPhoneSimulator:
        symbolName = [symbolName substringFromIndex:1];
        break;

      case PLCrashReportOperatingSystemUnknown:
        MSACLogWarning([MSACCrashes logTag], @"Symbol \"%@\" prefix rules are unknown for this OS!", symbolName);
        break;
      }
    }

    uint64_t symOffset = frameInfo.instructionPointer - frameInfo.symbolInfo.startAddress;
    symbolString = [NSString stringWithFormat:@"%@ + %" PRId64, symbolName, symOffset];
  } else {
    symbolString = [NSString stringWithFormat:@"0x%" PRIx64 " + %" PRId64, baseAddress, pcOffset];
  }

  /*
   * Note that width specifiers are ignored for %@, but work for C strings.
   * UTF-8 is not correctly handled with %s (it depends on the system encoding),
   * but UTF-16 is supported via %S, so we use it here.
   */
  return symbolString;
}

+ (NSDictionary<NSString *, NSString *> *)extractRegistersFromCrashedThread:(PLCrashReportThreadInfo *)crashedThread is64bit:(BOOL)is64bit {
  NSMutableDictionary<NSString *, NSString *> *registers = [NSMutableDictionary new];

  for (PLCrashReportRegisterInfo *registerInfo in crashedThread.registers) {

    // No need to format the register's name but, we need to format the value.
    NSString *registerName = registerInfo.registerName;
    NSString *formattedRegisterValue = [MSACErrorLogFormatter formatAddress:registerInfo.registerValue is64bit:is64bit];
    registers[registerName] = formattedRegisterValue;
  }

  return registers;
}

+ (NSString *)extractExceptionReasonFromReport:(PLCrashReport *)report {
  NSString *exceptionReason = nil;

  // Uncaught Exception.
  if (report.hasExceptionInfo) {
    exceptionReason = [NSString stringWithString:report.exceptionInfo.exceptionReason];
  }
  return exceptionReason;
}

+ (NSString *)selectorRegisterValueFromReport:(PLCrashReport *)report
                              ofCrashedThread:(PLCrashReportThreadInfo *)crashedThread
                                     codeType:(uint64_t)codeType {

  /*
   * Try to find the selector in case this was a crash in obj_msgSend.
   * We search this whether the crash happened in objc_msgSend or not since we
   * don't have the symbol!
   */
  NSString *foundSelector = nil;

  // Search the registers value for the current architecture.
  switch (codeType) {
  case CPU_TYPE_ARM:
    foundSelector = [[self class] selectorForRegisterWithName:@"r1" ofThread:crashedThread report:report];
    if (foundSelector == NULL) {
      foundSelector = [[self class] selectorForRegisterWithName:@"r2" ofThread:crashedThread report:report];
    }
    break;

  case CPU_TYPE_ARM64:
    foundSelector = [[self class] selectorForRegisterWithName:@"x1" ofThread:crashedThread report:report];
    break;

  case CPU_TYPE_X86:
    foundSelector = [[self class] selectorForRegisterWithName:@"ecx" ofThread:crashedThread report:report];
    break;

  case CPU_TYPE_X86_64:
    foundSelector = [[self class] selectorForRegisterWithName:@"rsi" ofThread:crashedThread report:report];
    if (foundSelector == NULL) {
      foundSelector = [[self class] selectorForRegisterWithName:@"rdx" ofThread:crashedThread report:report];
    }
    break;
  }
  return foundSelector;
}

+ (NSArray<MSACBinary *> *)extractBinaryImagesFromReport:(PLCrashReport *)report is64bit:(BOOL)is64bit {

  // Gather all addresses for which we need to preserve the binary images.
  NSArray *addresses = [self addressesFromReport:report];

  NSMutableArray<MSACBinary *> *binaryImages = [NSMutableArray array];

  // Images. The iPhone crash report format sorts these in ascending order, by the base address.
  for (PLCrashReportBinaryImageInfo *imageInfo in [report.images sortedArrayUsingFunction:bit_binaryImageSort context:nil]) {
    MSACBinary *binary = [MSACBinary new];
    binary.binaryId = (imageInfo.hasImageUUID) ? imageInfo.imageUUID : unknownString;
    uint64_t startAddress = imageInfo.imageBaseAddress;
    binary.startAddress = [MSACErrorLogFormatter formatAddress:startAddress is64bit:is64bit];
    uint64_t endAddress = imageInfo.imageBaseAddress + (MAX((uint64_t)1, imageInfo.imageSize) - 1);
    binary.endAddress = [MSACErrorLogFormatter formatAddress:endAddress is64bit:is64bit];
    BOOL binaryIsInAddresses = [self isBinaryWithStart:startAddress end:endAddress inAddresses:addresses];
    MSACBinaryImageType imageType = [self imageTypeForImagePath:imageInfo.imageName processPath:report.processInfo.processPath];

    // Remove username from the image path.
    if (binaryIsInAddresses || (imageType != MSACBinaryImageTypeOther)) {
      NSString *imagePath = @"";
      if (imageInfo.imageName && [imageInfo.imageName length] > 0) {
#if TARGET_OS_SIMULATOR
        imagePath = [imageInfo.imageName stringByAbbreviatingWithTildeInPath];
#else
        imagePath = imageInfo.imageName;
#endif
      }
#if TARGET_OS_SIMULATOR || TARGET_OS_OSX || TARGET_OS_MACCATALYST
      imagePath = [self anonymizedPathFromPath:imagePath];
#endif

      binary.path = imagePath;

      NSString *imageName = [imageInfo.imageName lastPathComponent] ?: @"\?\?\?";
      binary.name = imageName;

      // Fetch the UUID if it exists.
      binary.binaryId = (imageInfo.hasImageUUID) ? imageInfo.imageUUID : unknownString;

      // Determine the architecture string.
      binary.primaryArchitectureId = @(imageInfo.codeType.type);
      binary.architectureVariantId = @(imageInfo.codeType.subtype);

      [binaryImages addObject:binary];
    }
  }
  return binaryImages;
}

+ (BOOL)isBinaryWithStart:(uint64_t)start end:(uint64_t)end inAddresses:(NSArray *)addresses {
  for (NSNumber *address in addresses) {

    if ([address unsignedLongLongValue] >= start && [address unsignedLongLongValue] <= end) {
      return YES;
    }
  }
  return NO;
}

/**
 *  Remove the user's name from a crash's process path.
 *  This is only necessary when sending crashes from the simulator as the path
 *  then contains the username of the Mac the simulator is running on.
 *
 *  @param path A string containing the username
 *
 *  @return An anonymized string where the real username is replaced by "USER"
 */
+ (NSString *)anonymizedPathFromPath:(NSString *)path {
  NSString *anonymizedProcessPath = [NSString string];
  if (([path length] > 0) && [path hasPrefix:@"/Users/"]) {
    NSError *error = nil;
    NSString *regexPattern = @"(/Users/[^/]+/)";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:regexPattern options:0 error:&error];
    if (!regex) {
      MSACLogError([MSACCrashes logTag], @"Couldn't create regular expression with pattern\"%@\": %@", regexPattern,
                   error.localizedDescription);
      return anonymizedProcessPath;
    }
    anonymizedProcessPath = [regex stringByReplacingMatchesInString:path
                                                            options:0
                                                              range:NSMakeRange(0, [path length])
                                                       withTemplate:@"/Users/USER/"];
  } else if (([path length] > 0) && ([path rangeOfString:@"Users"].length == 0)) {
    return path;
  }
  return anonymizedProcessPath;
}

/**
 * Return the selector string of a given register name
 *
 * @param regName The name of the register to use for getting the address
 * @param thread  The crashed thread
 * @param report  The crash report created by PLCrashReporter.
 *
 * @return The selector as a C string or NULL if no selector was found
 */
+ (NSString *)selectorForRegisterWithName:(NSString *)regName ofThread:(PLCrashReportThreadInfo *)thread report:(PLCrashReport *)report {

  // Get the address for the register.
  uint64_t regAddress = 0;
  for (PLCrashReportRegisterInfo *reg in thread.registers) {
    if ([reg.registerName isEqualToString:regName]) {
      regAddress = reg.registerValue;
      break;
    }
  }

  // Return nil if we couldn't find an address.
  if (regAddress == 0) {
    return nil;
  }

  // Get the selector.
  PLCrashReportBinaryImageInfo *imageForRegAddress = [report imageForAddress:regAddress];
  if (imageForRegAddress) {
    const char *foundSelector = findSEL([imageForRegAddress.imageName UTF8String], imageForRegAddress.imageUUID,
                                        regAddress - (uint64_t)imageForRegAddress.imageBaseAddress);
    if (foundSelector != NULL) {
      return [NSString stringWithUTF8String:foundSelector];
    }
  }

  return nil;
}

// Determine if in binary image is the app executable or app specific framework.
+ (MSACBinaryImageType)imageTypeForImagePath:(NSString *)imagePath processPath:(NSString *)processPath {
  MSACBinaryImageType imageType = MSACBinaryImageTypeOther;

  if (!imagePath || !processPath) {
    return imageType;
  }

  NSString *standardizedImagePath = [[imagePath stringByStandardizingPath] lowercaseString];
  imagePath = [imagePath lowercaseString];
  processPath = [processPath lowercaseString];

  NSRange appRange = [standardizedImagePath rangeOfString:@".app/"];

  /*
   * Exclude iOS swift dylibs. These are provided as part of the app binary by
   * Xcode for now, but we never get a dSYM for those.
   */
  NSRange swiftLibRange = [standardizedImagePath rangeOfString:@"frameworks/libswift"];
  BOOL dylibSuffix = [standardizedImagePath hasSuffix:@".dylib"];
  if (appRange.location != NSNotFound && !(swiftLibRange.location != NSNotFound && dylibSuffix)) {
    NSString *appBundleContentsPath = [standardizedImagePath substringToIndex:appRange.location + 5];

    /*
     * Fix issue with iOS 8 `stringByStandardizingPath` removing leading
     * `/private` path (when not running in the debugger or simulator only).
     */
    if ([standardizedImagePath isEqual:processPath] || [imagePath hasPrefix:processPath]) {
      imageType = MSACBinaryImageTypeAppBinary;
    } else if ([standardizedImagePath hasPrefix:appBundleContentsPath] || [imagePath hasPrefix:appBundleContentsPath]) {
      imageType = MSACBinaryImageTypeAppFramework;
    }
  }

  return imageType;
}

#pragma mark - Helpers

+ (MSACDevice *)deviceForTimestamp:(NSDate *)timestamp crashReport:(PLCrashReport *)report {
  MSACDevice *device = [[MSACDeviceTracker sharedInstance] deviceForTimestamp:timestamp];
  MSACDevice *alteredDevice = [MSACDevice new];

  // Merge PLCR system information with the SDK`s device information as the PLCR report
  // is more relevant in cases when the time on the device has been manually changed.
  // These fields are expected not to be empty:
  // https://github.com/microsoft/plcrashreporter/blob/b7b88ee14bbc25ce408ae05464cb6f1cdd747948/Source/PLCrashReport.m#L135
  // https://github.com/microsoft/plcrashreporter/blob/b7b88ee14bbc25ce408ae05464cb6f1cdd747948/Source/PLCrashReport.m#L475
  // but still adding a fallback in case if it changes in the future.
  alteredDevice.osVersion = report.systemInfo.operatingSystemVersion ?: device.osVersion;
  alteredDevice.osBuild = report.systemInfo.operatingSystemBuild ?: device.osBuild;
  alteredDevice.model = report.machineInfo.modelName ?: device.model;
  alteredDevice.appBuild = report.applicationInfo.applicationVersion ?: device.appBuild;
  alteredDevice.appVersion = report.applicationInfo.applicationMarketingVersion ?: device.appVersion;
  alteredDevice.appNamespace = report.applicationInfo.applicationIdentifier ?: device.appNamespace;

  // Use the remaining fields from the found device information.
  alteredDevice.sdkName = device.sdkName;
  alteredDevice.sdkVersion = device.sdkVersion;
  alteredDevice.oemName = device.oemName;
  alteredDevice.osName = device.osName;
  alteredDevice.osApiLevel = device.osApiLevel;
  alteredDevice.locale = device.locale;
  alteredDevice.timeZoneOffset = device.timeZoneOffset;
  alteredDevice.screenSize = device.screenSize;
  alteredDevice.carrierName = device.carrierName;
  alteredDevice.carrierCountry = device.carrierCountry;
  alteredDevice.wrapperSdkName = device.wrapperSdkName;
  alteredDevice.wrapperSdkVersion = device.wrapperSdkVersion;
  alteredDevice.wrapperRuntimeVersion = device.wrapperRuntimeVersion;
  alteredDevice.liveUpdatePackageHash = device.liveUpdatePackageHash;
  alteredDevice.liveUpdateReleaseLabel = device.liveUpdateReleaseLabel;
  alteredDevice.liveUpdateDeploymentKey = device.liveUpdateDeploymentKey;
  return alteredDevice;
}

+ (BOOL)isCodeType64bit:(uint64_t)type {
  return type == CPU_TYPE_ARM64 || type == CPU_TYPE_X86_64;
}

+ (PLCrashReportThreadInfo *)findCrashedThreadInReport:(PLCrashReport *)report {
  PLCrashReportThreadInfo *crashedThread;
  for (PLCrashReportThreadInfo *thread in report.threads) {
    if (thread.crashed) {
      crashedThread = thread;
      break;
    }
  }
  return crashedThread;
}

+ (NSArray *)addressesFromReport:(PLCrashReport *)report {
  NSMutableArray *addresses = [NSMutableArray new];
  if (report.exceptionInfo != nil && report.exceptionInfo.stackFrames != nil && [report.exceptionInfo.stackFrames count] > 0) {
    PLCrashReportExceptionInfo *exception = report.exceptionInfo;
    for (PLCrashReportStackFrameInfo *frameInfo in exception.stackFrames) {
      [addresses addObject:@(frameInfo.instructionPointer)];
    }
  }
  for (PLCrashReportThreadInfo *plCrashReporterThread in report.threads) {
    for (PLCrashReportStackFrameInfo *frameInfo in plCrashReporterThread.stackFrames) {
      [addresses addObject:@(frameInfo.instructionPointer)];
    }
    for (PLCrashReportRegisterInfo *registerInfo in plCrashReporterThread.registers) {
      [addresses addObject:@(registerInfo.registerValue)];
    }
  }

  return addresses;
}

+ (NSString *)uuidRefToString:(CFUUIDRef)uuidRef {
  if (!uuidRef) {
    return nil;
  }
  CFStringRef uuidStringRef = CFUUIDCreateString(kCFAllocatorDefault, uuidRef);
  return (__bridge_transfer NSString *)uuidStringRef;
}

+ (NSString *)formatAddress:(uint64_t)address is64bit:(BOOL)is64bit {
  return [NSString stringWithFormat:@"0x%0*" PRIx64, 8 << is64bit, address];
}

@end
