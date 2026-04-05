//
//  SUWKWebView.m
//  Sparkle
//
//  Created by Mayur Pawashe on 12/30/20.
//  Copyright © 2020 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS

#import "SUWKWebView.h"
#import "SUReleaseNotesCommon.h"
#import "SULog.h"
#import "SUErrors.h"
#import <WebKit/WebKit.h>

@interface WKWebView (Private)

- (void)_setDrawsBackground:(BOOL)drawsBackground;
- (void)_setDrawsTransparentBackground:(BOOL)drawsTransparentBackground;

@end

@interface SUWKWebView () <WKNavigationDelegate>
@end

@implementation SUWKWebView
{
    WKWebView *_webView;
    WKNavigation *_currentNavigation;
    NSArray<NSString *> *_customAllowedURLSchemes;
    
    void (^_completionHandler)(NSError * _Nullable);
    
    BOOL _drawsWebViewBackground;
    BOOL _allowsLoadingExternalReferences;
}

static WKUserScript *makeUserScriptWithInjectedStyleSource(NSString *styleSource)
{
    // We must remove newlines when inserting the style source in this interpolated string below
    NSString *strippedStyleSource = [styleSource stringByReplacingOccurrencesOfString:@"\n" withString:@""];
    
    NSString *scriptSource = [NSString stringWithFormat:
        @"var style = document.createElement('style');\n"
        @"style.innerHTML = '%@'\n"
        @"var head = document.head;\n"
        @"if (head.firstChild) {"
        @"\tdocument.head.insertBefore(style, document.head.firstChild);\n"
        @"} else {\n"
        @"\tdocument.head.appendChild(style)\n"
        @"}", strippedStyleSource];
    
    return [[WKUserScript alloc] initWithSource:scriptSource injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
}

static WKUserScript *makeUserScriptForExposingCurrentRelease(NSString *releaseString)
{
    // Check that release string can be safely injected
    NSMutableCharacterSet *allowedCharacterSet = [NSMutableCharacterSet alphanumericCharacterSet];
    [allowedCharacterSet addCharactersInString:@"_.- "];
    if ([releaseString rangeOfCharacterFromSet:allowedCharacterSet.invertedSet].location != NSNotFound) {
        SULog(SULogLevelDefault, @"warning: App version '%@' has characters unsafe for injection. The version number will not be exposed to the release notes CSS. Only [a-zA-Z0-9._- ] is allowed.", releaseString);
        return nil;
    }
    
    // This script adds the `sparkle-installed-version` class to all elements which have a matching `data-sparkle-version` attribute
    NSString *scriptSource = [NSString stringWithFormat:
        @"document.querySelectorAll(\'[data-sparkle-version=\"%@\"]\')\n"
        @".forEach(installedVersionElement =>\n"
        @"installedVersionElement.classList.add('sparkle-installed-version')\n"
        @");", releaseString];
    
    return [[WKUserScript alloc] initWithSource:scriptSource injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:YES];
}

- (instancetype)initWithColorStyleSheetLocation:(NSURL *)colorStyleSheetLocation fontFamily:(NSString *)fontFamily fontPointSize:(int)fontPointSize javaScriptEnabled:(BOOL)javaScriptEnabled customAllowedURLSchemes:(NSArray<NSString *> *)customAllowedURLSchemes allowsLoadingExternalReferences:(BOOL)allowsLoadingExternalReferences installedVersion:(NSString *)installedVersion
{
    self = [super init];
    if (self != nil) {
        // Synchronize with web view defaulting to drawing background to avoid unnecessary invocations in -setDrawsBackground:
        _drawsWebViewBackground = YES;
        
        _allowsLoadingExternalReferences = allowsLoadingExternalReferences;
        
        WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
        
        // Note: this javaScriptEnabled property is deprecated in favor of another webpage preference property,
        // that involves implementing a delegate method that is only available on macOS 11.. to get it properly working.
        // To simplify things, just rely on deprecated property for now.
        // Future reader: if you change how JS is disabled, please be sure to test that JS code is properly disabled in HTML release notes.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        configuration.preferences.javaScriptEnabled = javaScriptEnabled;
#pragma clang diagnostic pop
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = NO;
        
        NSError *colorStyleContentsError = nil;
        NSString *colorStyleContents = [NSString stringWithContentsOfURL:colorStyleSheetLocation encoding:NSUTF8StringEncoding error:&colorStyleContentsError];
        
        WKUserContentController *userContentController = [[WKUserContentController alloc] init];
        
        NSString *fontStyleContents = [NSString stringWithFormat:@"body { font-family: %@; font-size: %dpx; }", fontFamily, fontPointSize];
        
        NSString *finalStyleContents;
        if (colorStyleContents == nil) {
            SULog(SULogLevelError, @"Failed to load style contents from %@ with %@", colorStyleSheetLocation, colorStyleContentsError);
            
            finalStyleContents = fontStyleContents;
        } else {
            finalStyleContents = [NSString stringWithFormat:@"%@ %@", fontStyleContents, colorStyleContents];
        }
        
        // Note: we can still execute javascript via WKUserScript even if javascript is otherwise disabled from the web content
        // In fact, we must execute javascript to properly inject our default CSS style into the DOM
        // Legacy WebView has exposed methods for custom stylesheets and default fonts,
        // but WKWebView seems to forgo that type of API surface in favor of user scripts like this
        WKUserScript *userScriptWithInjectedStyleSource = makeUserScriptWithInjectedStyleSource(finalStyleContents);
        if (userScriptWithInjectedStyleSource == nil) {
            SULog(SULogLevelError, @"Failed to create script for injecting style");
        } else {
            [userContentController addUserScript:userScriptWithInjectedStyleSource];
        }
        
        WKUserScript *userScriptForExposingCurrentRelease = makeUserScriptForExposingCurrentRelease(installedVersion);
        if (userScriptForExposingCurrentRelease == nil) {
            SULog(SULogLevelDefault, @"warning: Failed to create script for injecting version %@", installedVersion);
        } else {
            [userContentController addUserScript:userScriptForExposingCurrentRelease];
        }
        
        configuration.userContentController = userContentController;
        
        _webView = [[WKWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
        _webView.navigationDelegate = self;
        
        _customAllowedURLSchemes = customAllowedURLSchemes;
    }
    return self;
}

- (NSView *)view
{
    return _webView;
}

static void SPULoadWebContent(BOOL allowsExternalReferences, WKUserContentController *userContentController, void (^loadHTMLContent)(void))
{
    if (allowsExternalReferences) {
        loadHTMLContent();
        return;
    }
    
    // Block loading all external resources for signed appcasts & signed release notes
    NSString *encodedContentRuleList =
        @"[{\"trigger\": { \"url-filter\": \".*\" }, \"action\": { \"type\": \"block\" } }]";
    
    [WKContentRuleListStore.defaultStore compileContentRuleListForIdentifier:@"sparkle-updater" encodedContentRuleList:encodedContentRuleList completionHandler:^(WKContentRuleList *contentRuleList, NSError *contentRuleListError) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (contentRuleList == nil) {
                SULog(SULogLevelError, @"Error: failed to load content rule list for WKWebView with error: %@", contentRuleListError);
            } else {
                [userContentController addContentRuleList:contentRuleList];
            }
            
            loadHTMLContent();
        });
    }];
}

- (void)loadString:(NSString *)htmlString baseURL:(NSURL * _Nullable)baseURL completionHandler:(void (^)(NSError * _Nullable))completionHandler
{
    _completionHandler = [completionHandler copy];
    
    SPULoadWebContent(_allowsLoadingExternalReferences, _webView.configuration.userContentController, ^{
        self->_currentNavigation = [self->_webView loadHTMLString:htmlString baseURL:baseURL];
    });
}

- (void)loadData:(NSData *)data MIMEType:(NSString *)MIMEType textEncodingName:(NSString *)textEncodingName baseURL:(NSURL *)baseURL completionHandler:(void (^)(NSError * _Nullable))completionHandler
{
    _completionHandler = [completionHandler copy];

    SPULoadWebContent(_allowsLoadingExternalReferences, _webView.configuration.userContentController, ^{
        self->_currentNavigation = [self->_webView loadData:data MIMEType:MIMEType characterEncodingName:textEncodingName baseURL:baseURL];
    });
}

- (void)setDrawsBackground:(BOOL)drawsBackground
{
    if (_drawsWebViewBackground != drawsBackground) {
        // Unfortunately we have to rely on a private API
        // FB7539179: https://github.com/feedback-assistant/reports/issues/81 | https://bugs.webkit.org/show_bug.cgi?id=155550
        // But it seems like others are already relying on it, passed App Review, and apps couldn't be broken due to compatibility
        // Note: before we were using _setDrawsTransparentBackground < macOS 10.12
        if ([_webView respondsToSelector:@selector(_setDrawsBackground:)]) {
            [_webView _setDrawsBackground:drawsBackground];
        }
        
        _drawsWebViewBackground = drawsBackground;
    }
}

- (void)stopLoading
{
    _completionHandler = nil;
    [_webView stopLoading];
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation
{
    if (navigation == _currentNavigation) {
        if (_completionHandler != nil) {
            _completionHandler(nil);
            _completionHandler = nil;
        }
        _currentNavigation = nil;
    }
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error
{
    if (navigation == _currentNavigation) {
        if (_completionHandler != nil) {
            _completionHandler(error);
            _completionHandler = nil;
        }
        _currentNavigation = nil;
    }
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView
{
    if (_currentNavigation != nil) {
        if (_completionHandler != nil) {
            _completionHandler([NSError errorWithDomain:SUSparkleErrorDomain code:SUWebKitTerminationError userInfo:nil]);
            _completionHandler = nil;
        }
        
        _currentNavigation = nil;
    }
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler
{
    NSURLRequest *request = navigationAction.request;
    NSURL *requestURL = request.URL;
    BOOL isAboutBlank = NO;
    BOOL safeURL = SUReleaseNotesIsSafeURL(requestURL, _customAllowedURLSchemes, &isAboutBlank);
    
    // Do not allow redirects to dangerous protocols such as file://
    if (!safeURL) {
        SULog(SULogLevelDefault, @"Blocked display of %@ URL which may be dangerous", requestURL.scheme);
        decisionHandler(WKNavigationActionPolicyCancel);
    } else {
        // Ensure we're finished loading
        if (_completionHandler == nil) {
            if (!isAboutBlank) {
                [[NSWorkspace sharedWorkspace] openURL:requestURL];
            }
            
            decisionHandler(WKNavigationActionPolicyCancel);
        } else {
            decisionHandler(WKNavigationActionPolicyAllow);
        }
    }
}

@end

#endif
