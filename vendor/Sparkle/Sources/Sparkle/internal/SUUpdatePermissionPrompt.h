//
//  SUUpdatePermissionPrompt.h
//  Sparkle
//
//  Created by Andy Matuschak on 1/24/08.
//  Copyright 2008 Andy Matuschak. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS

#ifndef SUUPDATEPERMISSIONPROMPT_H
#define SUUPDATEPERMISSIONPROMPT_H

#import <Cocoa/Cocoa.h>

@class SUHost, SPUUpdatePermissionRequest, SUUpdatePermissionResponse;

SPU_OBJC_DIRECT_MEMBERS @interface SUUpdatePermissionPrompt : NSWindowController

- (instancetype)initPromptWithHost:(SUHost *)theHost request:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply;

@end

#endif

#endif
