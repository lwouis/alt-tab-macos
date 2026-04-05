//
//  SULog.h
//  Sparkle
//
//  Created by Mayur Pawashe on 5/18/16.
//  Copyright © 2016 Sparkle Project. All rights reserved.
//

#ifndef SULOG_H
#define SULOG_H

#include <Foundation/Foundation.h>

typedef NS_ENUM(uint8_t, SULogLevel) {
    // This level is for information that *might* result a failure
    // For now until other levels are added, this may serve as a level for other information as well
    SULogLevelDefault,
    // This level is for errors that occurred
    SULogLevelError
};

// Logging utility function that is thread-safe and uses os_log
// For debugging command line tools, you may have to use Console.app or log(1) to view log messages
// Try to keep log messages as compact/short as possible
void SULog(SULogLevel level, NSString *format, ...) NS_FORMAT_FUNCTION(2, 3);

#endif
