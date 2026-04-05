//
//  SULog.m
//  Sparkle
//
//  Created by Mayur Pawashe on 5/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#include "SULog.h"
#include <os/log.h>


#include "AppKitPrevention.h"

void SULog(SULogLevel level, NSString *format, ...)
{
    static dispatch_once_t onceToken;
    static os_log_t logger;

    dispatch_once(&onceToken, ^{
        const char *subsystem = SPARKLE_BUNDLE_IDENTIFIER;
        // This creates a thread-safe object
        logger = os_log_create(subsystem, "Sparkle");
    });

    va_list ap;
    va_start(ap, format);
    NSString *logMessage = [[NSString alloc] initWithFormat:format arguments:ap];
    va_end(ap);
    
    // We'll make all of our messages formatted as public; just don't log sensitive information.
    // Note we don't take advantage of info like the source line number because we wrap this macro inside our own function
    // And we don't really leverage of os_log's deferred formatting processing because we format the string before passing it in
    switch (level) {
#pragma clang diagnostic push
#if __has_warning("-Wpre-c11-compat")
#pragma clang diagnostic ignored "-Wpre-c11-compat"
#endif
        case SULogLevelDefault:
            // See docs for OS_LOG_TYPE_DEFAULT
            // By default, OS_LOG_TYPE_DEFAULT seems to be more noticeable than OS_LOG_TYPE_INFO
            os_log(logger, "%{public}@", logMessage);
            break;
        case SULogLevelError:
            // See docs for OS_LOG_TYPE_ERROR
            os_log_error(logger, "%{public}@", logMessage);
            break;
#pragma clang diagnostic pop
    }
}
