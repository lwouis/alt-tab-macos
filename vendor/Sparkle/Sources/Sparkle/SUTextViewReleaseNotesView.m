//
//  SUTextViewReleaseNotesView.m
//  Sparkle
//
//  Created on 9/11/22.
//  Copyright © 2022 Sparkle Project. All rights reserved.
//

#if SPARKLE_BUILD_UI_BITS

#import "SUTextViewReleaseNotesView.h"
#import "SUReleaseNotesCommon.h"
#import "SPUStandardUserDriverDelegate.h"
#import "SULog.h"
#import "SUErrors.h"
#import "SUHost.h"

#import <AppKit/AppKit.h>

@interface SUTextViewReleaseNotesView () <NSTextViewDelegate>
@end

@implementation SUTextViewReleaseNotesView
{
    NSScrollView *_scrollView;
    NSTextView *_textView;
#if DEBUG
    id _textViewSwitchedToTextKit1Observer;
#endif
    NSArray<NSString *> *_customAllowedURLSchemes;
    
    SUAppcastItem *_updateItem;
    SUHost *_host;
    __weak id<SPUStandardUserDriverDelegate> _delegate;
    
    int _fontPointSize;
    BOOL _prefersMarkdown;
}

- (instancetype)initWithFontPointSize:(int)fontPointSize appcastItem:(SUAppcastItem *)appcastItem host:(SUHost *)host delegate:(id<SPUStandardUserDriverDelegate>)delegate prefersMarkdown:(BOOL)prefersMarkdown customAllowedURLSchemes:(NSArray<NSString *> *)customAllowedURLSchemes
{
    self = [super init];
    if (self != nil) {
        _fontPointSize = fontPointSize;
        _customAllowedURLSchemes = customAllowedURLSchemes;
        _prefersMarkdown = prefersMarkdown;
        _scrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
        
        _updateItem = appcastItem;
        _host = host;
        
        _delegate = delegate;
        
        // On macOS 12.7, TextKit 2 is very buggy in handling our simple text with NSParagraphStyle attributes.
        // So even though macOS 12 supports TextKit 2 we do not use it there.
        // My development machines are currently on macOS 26 so I know TextKit 2 works well there.
        // macOS 13 - 15 requires more testing if we care to make the switch there.
        if (@available(macOS 16, *)) {
            // Create NSTextView using TextKit 2
            // https://developer.apple.com/documentation/appkit/nstextview/1449347-initwithframe
            
            NSTextContainer *textContainer = [[NSTextContainer alloc] initWithContainerSize:NSMakeSize(0, (CGFloat)FLT_MAX)];
            textContainer.widthTracksTextView = YES;
            
            NSTextLayoutManager *textLayoutManager = [[NSTextLayoutManager alloc] init];
            textLayoutManager.textContainer = textContainer;
            
            NSTextContentStorage *textContentStorage = [[NSTextContentStorage alloc] init];
            [textContentStorage addTextLayoutManager:textLayoutManager];
            
            _textView = [[NSTextView alloc] initWithFrame:NSZeroRect textContainer:textLayoutManager.textContainer];
            
#if DEBUG
            _textViewSwitchedToTextKit1Observer = [NSNotificationCenter.defaultCenter addObserverForName:NSTextViewDidSwitchToNSLayoutManagerNotification object:_textView queue:nil usingBlock:^(NSNotification * _Nonnull __unused notification) {
                SULog(SULogLevelError, @"Error: Plain text release notes text view switched to TextKit 1. This should not happen. Was some TextKit 1 API called that is causing this?");
            }];
#endif
        } else {
            _textView = [[NSTextView alloc] initWithFrame:NSZeroRect];
        }
        
        _textView.delegate = self;
        _scrollView.documentView = _textView;
    }
    return self;
}

#if DEBUG
- (void)dealloc
{
    [NSNotificationCenter.defaultCenter removeObserver:_textViewSwitchedToTextKit1Observer];
}
#endif

- (NSView *)view
{
    return _scrollView;
}

static void processMarkdownFragmentAttributedString(NSAttributedString *fragmentAttributedString, NSMutableAttributedString *outputAttributedSubString, NSMutableParagraphStyle *paragraphStyle, BOOL canProcessListItem, NSMutableSet<NSNumber *> *previousVisitedListItemIntents, NSPresentationIntent *intent, NSFont *inputParagraphFont, NSFont *monospacedParagraphFont, NSAttributedString *tabAttributedString, NSAttributedString *newlineAttributedString, NSAttributedString *listBulletAttributedString) API_AVAILABLE(macos(12.0))
{
    // Pre-pass processing of intent
    // This info must be computed before processing parent intent
    BOOL isListItem = NO;
    NSFont *font = inputParagraphFont;
    switch (intent.intentKind) {
        case NSPresentationIntentKindHeader:
            switch (intent.headerLevel) {
                case 1:
                    font = [NSFont boldSystemFontOfSize:(CGFloat)inputParagraphFont.pointSize * 1.5];
                    break;
                case 2:
                    font = [NSFont boldSystemFontOfSize:(CGFloat)inputParagraphFont.pointSize * 1.3];
                    break;
                case 3:
                    font = [NSFont boldSystemFontOfSize:(CGFloat)inputParagraphFont.pointSize * 1.2];
                    break;
                default:
                    font = [NSFont boldSystemFontOfSize:(CGFloat)inputParagraphFont.pointSize * 1.1];
                    break;
            }
            break;
        case NSPresentationIntentKindListItem:
            isListItem = YES;
            break;
        case NSPresentationIntentKindParagraph:
        case NSPresentationIntentKindThematicBreak:
        case NSPresentationIntentKindBlockQuote:
        case NSPresentationIntentKindCodeBlock:
        case NSPresentationIntentKindOrderedList:
        case NSPresentationIntentKindUnorderedList:
        case NSPresentationIntentKindTable:
        case NSPresentationIntentKindTableHeaderRow:
        case NSPresentationIntentKindTableRow:
        case NSPresentationIntentKindTableCell:
            break;
    }
    
    // Process parent intent if available
    // A paragraph's intent may be a list item, or a block quote for example. A header's parent intent could be a block quote.
    // In these cases, we may pre-append attributed string to the output before processing current intent.
    NSPresentationIntent *parentIntent = intent.parentIntent;
    if (parentIntent != nil) {
        processMarkdownFragmentAttributedString(fragmentAttributedString, outputAttributedSubString, paragraphStyle, canProcessListItem && !isListItem, previousVisitedListItemIntents, parentIntent, font, monospacedParagraphFont, tabAttributedString, newlineAttributedString, listBulletAttributedString);
    }
    
    // Process the current intent
    switch (intent.intentKind) {
        case NSPresentationIntentKindHeader: {
            CGFloat paragraphSpacing = font.pointSize * 0.8;
            paragraphStyle.paragraphSpacingBefore += paragraphSpacing;
            paragraphStyle.paragraphSpacing += paragraphSpacing;
            
            NSMutableAttributedString *headerAttributedString = [fragmentAttributedString mutableCopy];
            
            [headerAttributedString addAttributes:@{NSFontAttributeName: font} range:NSMakeRange(0, headerAttributedString.length)];
            
            [outputAttributedSubString appendAttributedString:headerAttributedString];
            
            break;
        }
        case NSPresentationIntentKindParagraph: {
            if (parentIntent != nil && parentIntent.intentKind == NSPresentationIntentKindListItem) {
                // If the parent intent is a list item we don't want to apply paragraphSpacingBefore,
                // and we'll apply less spacing
                paragraphStyle.paragraphSpacing += font.pointSize * 0.3;
            } else {
                CGFloat paragraphSpacing = font.pointSize * 0.5;
                paragraphStyle.paragraphSpacing += paragraphSpacing;
                paragraphStyle.paragraphSpacingBefore += paragraphSpacing;
            }
            
            NSMutableAttributedString *contentAttributedString = [fragmentAttributedString mutableCopy];
            [contentAttributedString addAttributes:@{NSFontAttributeName: font} range:NSMakeRange(0, contentAttributedString.length)];
            
            [outputAttributedSubString appendAttributedString:contentAttributedString];
            
            break;
        }
        case NSPresentationIntentKindListItem: {
            // We only process (the innermost first) list item once when we encounter nested lists,
            // to avoid outputting multiple list bullets
            // Also avoid processing list items that were processed from previous passes / fragments
            if (canProcessListItem) {
                CGFloat firstLineIdentation = (CGFloat)intent.indentationLevel * (font.pointSize * 1.5);
                paragraphStyle.firstLineHeadIndent += firstLineIdentation;
                
                // Advance subsequent lines and text that wraps to next line by next tab interval past the firstLineIdentation
                CGFloat defaultTabInterval = paragraphStyle.defaultTabInterval;
                paragraphStyle.headIndent += ceil(firstLineIdentation / defaultTabInterval) * defaultTabInterval;
                
                NSNumber *intentIdentity = @(intent.identity);
                BOOL didVisitListItemFromPreviousPass = [previousVisitedListItemIntents containsObject:intentIdentity];
                BOOL insertUnorderedBullet = (parentIntent == nil || parentIntent.intentKind == NSPresentationIntentKindUnorderedList);
                
                if (!didVisitListItemFromPreviousPass) {
                    if (insertUnorderedBullet) {
                        [outputAttributedSubString appendAttributedString:listBulletAttributedString];
                    } else {
                        NSString *ordinalStringWithSpacing = [NSString stringWithFormat:@"%ld.", intent.ordinal];
                        NSAttributedString *listItemAttributedString = [[NSAttributedString alloc] initWithString:ordinalStringWithSpacing attributes:@{NSFontAttributeName: font}];
                        
                        [outputAttributedSubString appendAttributedString:listItemAttributedString];
                    }
                    
                    [previousVisitedListItemIntents addObject:intentIdentity];
                }
                
                [outputAttributedSubString appendAttributedString:tabAttributedString];
            }
            
            break;
        }
        case NSPresentationIntentKindBlockQuote: {
            // Advance text that wraps to next line by this divider width
            // Multiple levels of block quotes will be advanced mulitiple times
            // Special rendering via text attachments or decorations is not done because
            // it's complex and may have tradeoffs
            
            paragraphStyle.firstLineHeadIndent += paragraphStyle.defaultTabInterval;
            paragraphStyle.headIndent += paragraphStyle.defaultTabInterval;

            break;
        }
        case NSPresentationIntentKindCodeBlock: {
            paragraphStyle.paragraphSpacing += font.pointSize * 0.25;
            
            // A parent of a code block could be a block quote or list item
            // It's more correct to use tab rather than leading paragraph indentation in this case
            [outputAttributedSubString appendAttributedString:tabAttributedString];
            // Advance text that wraps to next line by next tab interval
            paragraphStyle.headIndent += paragraphStyle.defaultTabInterval;
            
            NSMutableAttributedString *blockquoteAttributedString = [fragmentAttributedString mutableCopy];
            [blockquoteAttributedString addAttributes:@{NSFontAttributeName: monospacedParagraphFont, NSForegroundColorAttributeName: NSColor.labelColor} range:NSMakeRange(0, blockquoteAttributedString.length)];
            
            [outputAttributedSubString appendAttributedString:blockquoteAttributedString];
            
            break;
        }
        
        case NSPresentationIntentKindOrderedList:
        case NSPresentationIntentKindUnorderedList:
        // Nothing special is rendered for thematic breaks
        // Rendering them via text attachments or decorations is complex and has tradeoffs
        case NSPresentationIntentKindThematicBreak:
        // Note: TextKit 2 doesn't support NSTextTable
        // Tables don't show up in release notes often, so they're not that worthwhile supporting
        case NSPresentationIntentKindTable:
        case NSPresentationIntentKindTableHeaderRow:
        case NSPresentationIntentKindTableRow:
        case NSPresentationIntentKindTableCell:
            break;
    }
}

// Note: this function can be called from a background thread and shouldn't use main-thread only APIs
// More decorative rendering for blockquotes and line breaks (i.e. rendering dividers) was tried out,
// using a. NSTextAttachmentCell based subclass, or b. NSTextAttachmentViewProvider, or c. adopting custom NSTextViewportLayoutControllerDelegate.
// This was ultimatily given up on and they all have various tradeoffs. NSCell based text attachments don't work in Catalyst,
// view based attachments take up additional space, and TextKit2 CALayer decorations are hard to (re)size/position correctly.
// Also each increases code complexity and risk. In the end, changelogs can can live without these.
// Furthermore we currently support TextKit 1 (on older systems) and TextKit 2 so this function needs to handle both paths.
static NSAttributedString *formatMarkdownAttributedString(NSAttributedString *originalAttributedString, CGFloat defaultFontPointSize) API_AVAILABLE(macos(12.0))
{
    // Create our fonts and cache some common attributed strings up front (list bullets, newline)
    
    NSFont *paragraphFont = [NSFont systemFontOfSize:defaultFontPointSize];
    NSFont *monospacedParagraphFont = [NSFont monospacedSystemFontOfSize:defaultFontPointSize weight:NSFontWeightRegular];
    
    NSMutableAttributedString *outputAttributedString = [[NSMutableAttributedString alloc] init];
    
    NSAttributedString *newlineAttributedString = [[NSAttributedString alloc] initWithString:@"\n"];
    
    NSAttributedString *listBulletAttributedString;
    {
        // The bullet character looks too small in the system font, so switch to another font where it's bigger at same point size
        NSFont *listBulletPreferredFont = [NSFont fontWithName:@"Menlo Regular" size:defaultFontPointSize];
        NSFont *listBulletFont = (listBulletPreferredFont != nil) ? listBulletPreferredFont : paragraphFont;
        
        listBulletAttributedString = [[NSAttributedString alloc] initWithString:@"•" attributes:@{NSFontAttributeName : listBulletFont}];
    }
    
    NSAttributedString *tabAttributedString = [[NSAttributedString alloc] initWithString:@"\t" attributes:@{NSFontAttributeName: paragraphFont}];
    
    NSMutableSet<NSNumber *> *previousVisitedListItemIntents = [[NSMutableSet alloc] init];
    
    // Enumerate through every presentation intent fragment and create a new attributed string that we append to the output
    // Foundation handles formatting some things for us already in the attributed string such as bold/itatlics and hyperlinks,
    // but we need to handle formatting paragraphs, headers, lists, block quotes, etc in the attributed string.
    [originalAttributedString enumerateAttribute:NSPresentationIntentAttributeName inRange:NSMakeRange(0, originalAttributedString.length) options:(NSAttributedStringEnumerationOptions)0 usingBlock:^(NSPresentationIntent *intent, NSRange presentationIntentRange, BOOL * _Nonnull __unused stopPresentationIntentEnumeration) {
        
        // Split the presentation intent by lines so we treat every line as a separate paragraph so we present them properly (with correct indentation / tabs)
        // Normally multiple lines aren't in the same paragraph, but this can happen in some cases like code blocks
        [originalAttributedString.string enumerateSubstringsInRange:presentationIntentRange options:NSStringEnumerationByLines usingBlock:^(NSString * _Nullable __unused substring, NSRange substringRange, NSRange __unused enclosingRange, BOOL * _Nonnull __unused stopLineEnumeration) {
            // Insert newline after outputting previous paragraph
            // This check ensures an extra newline is not inserted after the last outputted paragraph
            if (outputAttributedString.length > 0) {
                [outputAttributedString appendAttributedString:newlineAttributedString];
            }
            
            NSAttributedString *fragmentAttributedString = [originalAttributedString attributedSubstringFromRange:substringRange];
            
            // Properties of the paragraph start as 0 and later get incremented based on what is processed
            NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
            paragraphStyle.paragraphSpacingBefore = 0;
            paragraphStyle.paragraphSpacing = 0;
            paragraphStyle.headIndent = 0;
            paragraphStyle.firstLineHeadIndent = 0;
            
            // Assume tabs won't be used in headers so we'll just use regular paragraph font size
            paragraphStyle.tabStops = @[];
            paragraphStyle.defaultTabInterval = paragraphFont.pointSize * 1.38;
            
            NSUInteger previousOutputLength = outputAttributedString.length;
            
            BOOL canProcessListItem = YES;
            processMarkdownFragmentAttributedString(fragmentAttributedString, outputAttributedString, paragraphStyle, canProcessListItem, previousVisitedListItemIntents, intent, paragraphFont, monospacedParagraphFont, tabAttributedString, newlineAttributedString, listBulletAttributedString);
            
            [outputAttributedString addAttributes:@{NSParagraphStyleAttributeName: paragraphStyle} range:NSMakeRange(previousOutputLength, outputAttributedString.length - previousOutputLength)];
        }];
    }];
    
    return outputAttributedString;
}

- (void)_loadAttributedString:(NSAttributedString * _Nullable)attributedString completionHandler:(void (^)(NSError * _Nullable))completionHandler SPU_OBJC_DIRECT
{
    if (attributedString == nil) {
        completionHandler([NSError errorWithDomain:SUSparkleErrorDomain code:SUReleaseNotesError userInfo:@{NSLocalizedDescriptionKey: @"Failed to create attributed string of contents to load"}]);
        return;
    }
    
    // Give delegate a chance to process and modify the attributed string
    NSAttributedString *finalAttributedString;
    id<SPUStandardUserDriverDelegate> delegate = _delegate;
    if ([(NSObject *)delegate respondsToSelector:@selector(standardUserDriverWillShowReleaseNotesText:forUpdate:withBundleDisplayVersion:bundleVersion:)]) {
        NSAttributedString *attributedStringFromDelegate = [delegate standardUserDriverWillShowReleaseNotesText:(NSAttributedString * _Nonnull)attributedString forUpdate:_updateItem withBundleDisplayVersion:_host.displayVersion bundleVersion:_host.version];
        if (attributedStringFromDelegate != nil) {
            finalAttributedString = attributedStringFromDelegate;
        } else {
            finalAttributedString = attributedString;
        }
    } else {
        finalAttributedString = attributedString;
    }
    
    [_textView.textStorage setAttributedString:finalAttributedString];
    
    completionHandler(nil);
}

- (void)_loadString:(NSString *)contents baseURL:(nullable NSURL *)baseURL completionHandler:(void (^)(NSError * _Nullable))completionHandler SPU_OBJC_DIRECT
{
    NSSize contentSize = [_scrollView contentSize];
    [_textView setFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
    [_textView setMinSize:NSMakeSize(0.0, contentSize.height)];
    [_textView setMaxSize:NSMakeSize(DBL_MAX, DBL_MAX)];
    [_textView setVerticallyResizable:YES];
    [_textView setHorizontallyResizable:NO];
    [_textView setAutoresizingMask:NSViewWidthSizable];
    [_textView setTextContainerInset:NSMakeSize(4, 8)];
    [_textView setContinuousSpellCheckingEnabled:NO];
    _textView.usesFontPanel = NO;
    _textView.editable = NO;
    
    if (@available(macOS 10.14, *)) {
        _textView.usesAdaptiveColorMappingForDarkAppearance = YES;
    }
    
    [_scrollView setHasVerticalScroller:YES];
    [_scrollView setHasHorizontalScroller:NO];
    
    if (_prefersMarkdown) {
        if (@available(macOS 12, *)) {
            dispatch_queue_attr_t queuePriority = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
            
            dispatch_queue_t markdownDispatchQueue = dispatch_queue_create("org.sparkle-project.markdown-loader", queuePriority);
            
            dispatch_async(markdownDispatchQueue, ^{
                NSError *loadMarkdownError = nil;
                NSAttributedString *originalMarkdownAttributedString = [[NSAttributedString alloc] initWithMarkdownString:contents options:nil baseURL:baseURL error:&loadMarkdownError];
                
                if (originalMarkdownAttributedString == nil) {
                    // Fallback to plain-text
                    
                    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:contents attributes:@{ NSFontAttributeName : [NSFont systemFontOfSize:(CGFloat)self->_fontPointSize] }];
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self _loadAttributedString:attributedString completionHandler:completionHandler];
                    });
                } else {
                    NSAttributedString *formattedAttributedString = formatMarkdownAttributedString(originalMarkdownAttributedString, (CGFloat)self->_fontPointSize);
                    
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self _loadAttributedString:formattedAttributedString completionHandler:completionHandler];
                    });
                }
            });
            
            return;
        } else {
            SULog(SULogLevelDefault, @"Warning: falling back to plain text because markdown support requires macOS 12 or newer");
        }
    }
    
    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:contents attributes:@{ NSFontAttributeName : [NSFont systemFontOfSize:(CGFloat)_fontPointSize] }];
    
    [self _loadAttributedString:attributedString completionHandler:completionHandler];
}

- (void)loadString:(NSString *)contents baseURL:(NSURL * _Nullable)baseURL completionHandler:(void (^)(NSError * _Nullable))completionHandler
{
    [self _loadString:contents baseURL:baseURL completionHandler:completionHandler];
}

- (void)loadData:(NSData *)data MIMEType:(NSString *)MIMEType textEncodingName:(NSString *)textEncodingName baseURL:(NSURL *)baseURL completionHandler:(void (^)(NSError * _Nullable))completionHandler
{
    CFStringEncoding cfEncoding = CFStringConvertIANACharSetNameToEncoding((CFStringRef)textEncodingName);

    NSStringEncoding encoding;
    if (cfEncoding != kCFStringEncodingInvalidId) {
        encoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding);
    } else {
        encoding = NSUTF8StringEncoding;
    }
    
    NSString *contents = [[NSString alloc] initWithData:data encoding:encoding];
    
    if (contents == nil) {
        completionHandler([NSError errorWithDomain:SUSparkleErrorDomain code:SUReleaseNotesError userInfo:@{NSLocalizedDescriptionKey: @"Failed to convert data contents to string"}]);
        return;
    }
    
    [self _loadString:contents baseURL:baseURL completionHandler:completionHandler];
}

- (void)stopLoading
{
}

- (void)setDrawsBackground:(BOOL)drawsBackground
{
}

- (BOOL)textView:(NSTextView *)textView clickedOnLink:(id)link atIndex:(NSUInteger)charIndex
{
    NSURL *linkURL;
    if ([(NSObject *)link isKindOfClass:[NSURL class]]) {
        linkURL = link;
    } else if ([(NSObject *)link isKindOfClass:[NSString class]]) {
        linkURL = [NSURL URLWithString:link];
    } else {
        SULog(SULogLevelDefault, @"Blocked display of %@ link of unknown type", link);
        return YES;
    }
    
    BOOL isAboutBlankURL;
    if (!SUReleaseNotesIsSafeURL(linkURL, _customAllowedURLSchemes, &isAboutBlankURL)) {
        SULog(SULogLevelDefault, @"Blocked display of %@ URL which may be dangerous", linkURL.scheme);
        return YES;
    }
    
    return NO;
}

@end

#endif
