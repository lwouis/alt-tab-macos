//
//  SUSystemProfiler.m
//  Sparkle
//
//  Created by Andy Matuschak on 12/22/07.
//  Copyright 2007 Andy Matuschak. All rights reserved.
//  Adapted from Sparkle+, by Tom Harrington.
//

#import "SUSystemProfiler.h"
#import "SUHost.h"
#import "SUOperatingSystem.h"
#include <sys/sysctl.h>
#import "SPUUpdaterDelegate.h"
#import "SULocalizations.h"


#include "AppKitPrevention.h"

NSString *const SUSystemProfilerApplicationNameKey = @"appName";
NSString *const SUSystemProfilerApplicationVersionKey = @"appVersion";
NSString *const SUSystemProfilerCPU64bitKey = @"cpu64bit";
NSString *const SUSystemProfilerCPUCountKey = @"ncpu";
NSString *const SUSystemProfilerCPUFrequencyKey = @"cpuFreqMHz";
NSString *const SUSystemProfilerCPUTypeKey = @"cputype";
NSString *const SUSystemProfilerCPUSubtypeKey = @"cpusubtype";
NSString *const SUSystemProfilerHardwareModelKey = @"model";
NSString *const SUSystemProfilerMemoryKey = @"ramMB";
NSString *const SUSystemProfilerOperatingSystemVersionKey = @"osVersion";
NSString *const SUSystemProfilerPreferredLanguageKey = @"lang";

@implementation SUSystemProfiler

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)systemProfileArrayForHost:(SUHost *)host
{
#if SPARKLE_COPY_LOCALIZATIONS
    NSBundle *sparkleBundle = SUSparkleBundle();
#endif
    
    // Gather profile information and append it to the URL.
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *profileArray = [NSMutableArray array];
    NSArray *profileDictKeys = @[@"key", @"displayKey", @"value", @"displayValue"];
    int error = 0;
    int value = 0;
    size_t length = sizeof(value);

    // OS version
    NSString *currentSystemVersion = [SUOperatingSystem systemVersionString];
    if (currentSystemVersion != nil) {
        [profileArray addObject:[NSDictionary dictionaryWithObjects:@[SUSystemProfilerOperatingSystemVersionKey, SULocalizedStringFromTableInBundle(@"OS Version", SPARKLE_TABLE, sparkleBundle, nil), currentSystemVersion, currentSystemVersion] forKeys:profileDictKeys]];
    }

    // CPU type (decoder info for values found here is in mach/machine.h)
    error = sysctlbyname("hw.cputype", &value, &length, NULL, 0);
    int cpuType = -1;
    if (error == 0) {
        // Only the lower 24 bits of sysctl hw.cputype values contain the CPU type. On Macs with ARM processor, one of the top eight bits may be set.
        cpuType = value & (int)~CPU_ARCH_MASK;
        NSString *visibleCPUType;
        switch (cpuType) {
            case CPU_TYPE_ARM:      visibleCPUType = @"ARM";        break;
            case CPU_TYPE_X86:      visibleCPUType = @"Intel";      break;
            case CPU_TYPE_POWERPC:  visibleCPUType = @"PowerPC";    break;
            default:                visibleCPUType = @"Other";      break;
        }
        [profileArray addObject:[NSDictionary dictionaryWithObjects:@[SUSystemProfilerCPUTypeKey, SULocalizedStringFromTableInBundle(@"CPU Type", SPARKLE_TABLE, sparkleBundle, nil), [NSString stringWithFormat:@"%d", value], visibleCPUType] forKeys:profileDictKeys]];
    }
    error = sysctlbyname("hw.cpu64bit_capable", &value, &length, NULL, 0);
    if (error != 0) {
        error = sysctlbyname("hw.optional.x86_64", &value, &length, NULL, 0); //x86 specific
    }
    if (error != 0) {
        error = sysctlbyname("hw.optional.64bitops", &value, &length, NULL, 0); //PPC specific
    }

    BOOL is64bit = NO;

    if (error == 0) {
        is64bit = value == 1;
        [profileArray addObject:[NSDictionary dictionaryWithObjects:@[SUSystemProfilerCPU64bitKey, SULocalizedStringFromTableInBundle(@"CPU is 64-Bit?", SPARKLE_TABLE, sparkleBundle, nil), [NSString stringWithFormat:@"%d", is64bit], is64bit ? SULocalizedStringFromTableInBundle(@"Yes", SPARKLE_TABLE, sparkleBundle, nil) : SULocalizedStringFromTableInBundle(@"No", SPARKLE_TABLE, sparkleBundle, nil)] forKeys:profileDictKeys]];
    }
    error = sysctlbyname("hw.cpusubtype", &value, &length, NULL, 0);
    if (error == 0) {
        NSString *visibleCPUSubType;
        if (cpuType == CPU_TYPE_X86) {
            // Intel
            // TODO: other Intel processors, like Core i7, i5, i3, Xeon?
            visibleCPUSubType = is64bit ? @"Intel Core 2" : @"Intel Core"; // If anyone knows how to tell a Core Duo from a Core Solo, please email tph@atomicbird.com
        } else if (cpuType == CPU_TYPE_POWERPC) {
            // PowerPC
            switch (value) {
                case CPU_SUBTYPE_POWERPC_750:                                       visibleCPUSubType=@"G3";    break;
                case CPU_SUBTYPE_POWERPC_7400:    case CPU_SUBTYPE_POWERPC_7450:    visibleCPUSubType=@"G4";    break;
                case CPU_SUBTYPE_POWERPC_970:                                       visibleCPUSubType=@"G5";    break;
                default:                                                            visibleCPUSubType=@"Other"; break;
            }
        } else if (cpuType == CPU_TYPE_ARM) {
            switch (value) {
                case CPU_SUBTYPE_ARM64E:    visibleCPUSubType=@"ARM64E";  break;
                default:                    visibleCPUSubType = @"Other"; break;
            }
        } else {
            visibleCPUSubType = @"Other";
        }
        [profileArray addObject:[NSDictionary dictionaryWithObjects:@[SUSystemProfilerCPUSubtypeKey, SULocalizedStringFromTableInBundle(@"CPU Subtype", SPARKLE_TABLE, sparkleBundle, nil), [NSString stringWithFormat:@"%d", value], visibleCPUSubType] forKeys:profileDictKeys]];
    }
    error = sysctlbyname("hw.model", NULL, &length, NULL, 0);
    if (error == 0) {
        char *cpuModel = (char *)malloc(sizeof(char) * length);
        if (cpuModel != NULL) {
            error = sysctlbyname("hw.model", cpuModel, &length, NULL, 0);
            if (error == 0) {
                NSString *rawModelName = @(cpuModel);
                NSString *visibleModelName = rawModelName;
                [profileArray addObject:[NSDictionary dictionaryWithObjects:@[SUSystemProfilerHardwareModelKey, SULocalizedStringFromTableInBundle(@"Mac Model", SPARKLE_TABLE, sparkleBundle, nil), rawModelName, visibleModelName] forKeys:profileDictKeys]];
            }
            free(cpuModel);
        }
    }

    // Number of CPUs
    error = sysctlbyname("hw.ncpu", &value, &length, NULL, 0);
    if (error == 0) {
        NSString *stringValue = [NSString stringWithFormat:@"%d", value];
        [profileArray addObject:[NSDictionary dictionaryWithObjects:@[SUSystemProfilerCPUCountKey, SULocalizedStringFromTableInBundle(@"Number of CPUs", SPARKLE_TABLE, sparkleBundle, nil), stringValue, stringValue] forKeys:profileDictKeys]];
    }

    // User preferred language
    NSUserDefaults *defs = [NSUserDefaults standardUserDefaults];
    NSArray *languages = [defs objectForKey:@"AppleLanguages"];
    if ([languages count] > 0) {
        [profileArray addObject:[NSDictionary dictionaryWithObjects:@[SUSystemProfilerPreferredLanguageKey, SULocalizedStringFromTableInBundle(@"Preferred Language", SPARKLE_TABLE, sparkleBundle, nil), [languages objectAtIndex:0], [languages objectAtIndex:0]] forKeys:profileDictKeys]];
    }

    // Application sending the request
    NSString *appName = [host name];
    if (appName) {
        [profileArray addObject:[NSDictionary dictionaryWithObjects:@[SUSystemProfilerApplicationNameKey, SULocalizedStringFromTableInBundle(@"Application Name", SPARKLE_TABLE, sparkleBundle, nil), appName, appName] forKeys:profileDictKeys]];
    }
    NSString *appVersion = [host version];
    if (appVersion) {
        [profileArray addObject:[NSDictionary dictionaryWithObjects:@[SUSystemProfilerApplicationVersionKey, SULocalizedStringFromTableInBundle(@"Application Version", SPARKLE_TABLE, sparkleBundle, nil), appVersion, appVersion] forKeys:profileDictKeys]];
    }

    // Number of displays?

    // CPU speed
    unsigned long hz;
    size_t hz_size = sizeof(unsigned long);
    if (sysctlbyname("hw.cpufrequency", &hz, &hz_size, NULL, 0) == 0) {
        unsigned long mhz = hz / 1000000;
        NSString *stringValue = [NSString stringWithFormat:@"%lu", mhz];
        [profileArray addObject:[NSDictionary dictionaryWithObjects:@[SUSystemProfilerCPUFrequencyKey, SULocalizedStringFromTableInBundle(@"CPU Speed (MHz)", SPARKLE_TABLE, sparkleBundle, nil), stringValue, stringValue] forKeys:profileDictKeys]];
    }

    // amount of RAM
    unsigned long bytes;
    size_t bytes_size = sizeof(unsigned long);
    if (sysctlbyname("hw.memsize", &bytes, &bytes_size, NULL, 0) == 0) {
        double megabytes = (double)bytes / (1024. * 1024.);
        NSString *stringValue = [NSString stringWithFormat:@"%lu", (unsigned long)megabytes];
        [profileArray addObject:[NSDictionary dictionaryWithObjects:@[SUSystemProfilerMemoryKey, SULocalizedStringFromTableInBundle(@"Memory (MB)", SPARKLE_TABLE, sparkleBundle, nil), stringValue, stringValue] forKeys:profileDictKeys]];
    }

    return [profileArray copy];
}

@end
