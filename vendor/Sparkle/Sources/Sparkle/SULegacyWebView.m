//
//  SULegacyWebView.m
//  Sparkle
//
//  Created by Mayur Pawashe on 12/30/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS && DOWNLOADER_XPC_SERVICE_EMBEDDED

#import "SULegacyWebView.h"
#import "SUReleaseNotesCommon.h"
#import "SULog.h"
#import <WebKit/WebKit.h>

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

@interface SULegacyWebView () <WebPolicyDelegate, WebFrameLoadDelegate, WebUIDelegate>
@end

@implementation SULegacyWebView
{
    WebView *_webView;
    NSArray<NSString *> *_customAllowedURLSchemes;
    
    void (^_completionHandler)(NSError * _Nullable);
}

- (instancetype)initWithColorStyleSheetLocation:(NSURL *)colorStyleSheetLocation fontFamily:(NSString *)fontFamily fontPointSize:(int)fontPointSize javaScriptEnabled:(BOOL)javaScriptEnabled customAllowedURLSchemes:(NSArray<NSString *> *)customAllowedURLSchemes
{
    self = [super init];
    if (self != nil) {
        _webView = [[WebView alloc] initWithFrame:NSZeroRect];

        WebPreferences *preferences = [[WebPreferences alloc] initWithIdentifier:@"sparkle-project.org.legacy-web-view"];
        preferences.autosaves = NO;
        preferences.javaScriptEnabled = javaScriptEnabled;
        preferences.javaEnabled = NO;
        preferences.plugInsEnabled = NO;
        
        // Mimicking settings when WebView used to be in SUUpdateAlert nib
        preferences.loadsImagesAutomatically = YES;
        preferences.allowsAnimatedImages = YES;
        preferences.allowsAnimatedImageLooping = YES;
        
        // Settings for default style
        preferences.userStyleSheetEnabled = YES;
        preferences.userStyleSheetLocation = colorStyleSheetLocation;
        preferences.standardFontFamily = fontFamily;
        preferences.defaultFontSize = fontPointSize;
        
        _webView.preferences = preferences;
        _webView.policyDelegate = self;
        _webView.frameLoadDelegate = self;
        _webView.UIDelegate = self;
        
        _customAllowedURLSchemes = customAllowedURLSchemes;
    }
    return self;
}

- (NSView *)view
{
    return _webView;
}

- (void)loadString:(NSString *)htmlString baseURL:(NSURL * _Nullable)baseURL completionHandler:(void (^)(NSError * _Nullable))completionHandler
{
    _completionHandler = [completionHandler copy];
    [[_webView mainFrame] loadHTMLString:htmlString baseURL:baseURL];
}

- (void)loadData:(NSData *)data MIMEType:(NSString *)MIMEType textEncodingName:(NSString *)textEncodingName baseURL:(NSURL *)baseURL completionHandler:(void (^)(NSError * _Nullable))completionHandler
{
    _completionHandler = [completionHandler copy];
    [[_webView mainFrame] loadData:data MIMEType:MIMEType textEncodingName:textEncodingName baseURL:baseURL];
}

- (void)stopLoading
{
    _completionHandler = nil;
    [_webView stopLoading:self];
}

- (void)setDrawsBackground:(BOOL)drawsBackground
{
    _webView.drawsBackground = drawsBackground;
}

- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
    if ([frame parentFrame] == nil) {
        if (_completionHandler != nil) {
            _completionHandler(nil);
            _completionHandler = nil;
        }
        [sender display]; // necessary to prevent weird scroll bar artifacting
    }
}

- (void)webView:(WebView *)sender didFailLoadWithError:(NSError *)error forFrame:(WebFrame *)frame
{
    if ([frame parentFrame] == nil) {
        if (_completionHandler != nil) {
            _completionHandler(error);
            _completionHandler = nil;
        }
    }
}

- (void)webView:(WebView *)__unused sender decidePolicyForNavigationAction:(NSDictionary *)__unused actionInformation request:(NSURLRequest *)request frame:(WebFrame *)__unused frame decisionListener:(id<WebPolicyDecisionListener>)listener
{
    NSURL *requestURL = request.URL;
    BOOL isAboutBlank = NO;
    BOOL safeURL = SUReleaseNotesIsSafeURL(requestURL, _customAllowedURLSchemes, &isAboutBlank);

    // Do not allow redirects to dangerous protocols such as file://
    if (!safeURL) {
        SULog(SULogLevelDefault, @"Blocked display of %@ URL which may be dangerous", requestURL.scheme);
        [listener ignore];
        return;
    }

    // Ensure we are finished loading
    if (_completionHandler == nil) {
        if (requestURL && !isAboutBlank) {
            [[NSWorkspace sharedWorkspace] openURL:requestURL];
        }

        [listener ignore];
    }
    else {
        [listener use];
    }
}

// Clean up the contextual menu.
- (NSArray *)webView:(WebView *)__unused sender contextMenuItemsForElement:(NSDictionary *)__unused element defaultMenuItems:(NSArray *)defaultMenuItems
{
    NSMutableArray *webViewMenuItems = [defaultMenuItems mutableCopy];

    if (webViewMenuItems)
    {
        for (NSMenuItem *menuItem in defaultMenuItems)
        {
            NSInteger tag = [menuItem tag];

            switch (tag)
            {
                case WebMenuItemTagOpenLinkInNewWindow:
                case WebMenuItemTagDownloadLinkToDisk:
                case WebMenuItemTagOpenImageInNewWindow:
                case WebMenuItemTagDownloadImageToDisk:
                case WebMenuItemTagOpenFrameInNewWindow:
                case WebMenuItemTagGoBack:
                case WebMenuItemTagGoForward:
                case WebMenuItemTagStop:
                case WebMenuItemTagReload:
                    [webViewMenuItems removeObjectIdenticalTo:menuItem];
            }
        }
    }

    return webViewMenuItems;
}

@end

#pragma clang diagnostic pop

#endif
