//
//  SUAppcast.m
//  Sparkle
//
//  Created by Andy Matuschak on 3/12/06.
//  Copyright 2006 Andy Matuschak. All rights reserved.
//

#import "SUExport.h"
#import "SUAppcast.h"
#import "SUAppcast+Private.h"
#import "SPUAppcastItemState.h"
#import "SUAppcastItem.h"
#import "SUAppcastItem+Private.h"
#import "SUVersionComparisonProtocol.h"
#import "SUConstants.h"
#import "SULog.h"
#import "SUErrors.h"
#import "SULocalizations.h"


#include "AppKitPrevention.h"

@implementation SUAppcast

@synthesize items = _items;
@synthesize signingValidationStatus = _signingValidationStatus;

- (nullable instancetype)initWithXMLData:(NSData *)xmlData relativeToURL:(NSURL * _Nullable)relativeURL stateResolver:(SPUAppcastItemStateResolver *)stateResolver signingValidationStatus:(SPUAppcastSigningValidationStatus)signingValidationStatus error:(NSError * __autoreleasing *)error
{
    self = [super init];
    if (self != nil) {
        _signingValidationStatus = signingValidationStatus;
        _items = [self parseAppcastItemsFromXMLData:xmlData relativeToURL:relativeURL stateResolver:stateResolver signingValidationStatus:signingValidationStatus error:error];
        if (_items == nil) {
            return nil;
        }
    }
    return self;
}

- (NSDictionary *)attributesOfNode:(NSXMLElement *)node SPU_OBJC_DIRECT
{
    NSEnumerator *attributeEnum = [[node attributes] objectEnumerator];
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];

    for (NSXMLNode *attribute in attributeEnum) {
        NSString *attrName = [self sparkleNamespacedNameOfNode:attribute];
        if (!attrName) {
            continue;
        }
        NSString *attributeStringValue = [attribute stringValue];
        if (attributeStringValue != nil) {
            [dictionary setObject:attributeStringValue forKey:attrName];
        }
    }
    return dictionary;
}

-(NSString *)sparkleNamespacedNameOfNode:(NSXMLNode *)node SPU_OBJC_DIRECT
{
    // XML namespace prefix is semantically meaningless, so compare namespace URI
    // NS URI isn't used to fetch anything, and must match exactly, so we look for http:// not https://
    if ([[node URI] isEqualToString:@"http://www.andymatuschak.org/xml-namespaces/sparkle"]) {
        NSString *localName = [node localName];
        assert(localName);
        return [@"sparkle:" stringByAppendingString:localName];
    } else {
        return [node name]; // Backwards compatibility
    }
}

-(NSArray *)parseAppcastItemsFromXMLData:(NSData *)appcastData relativeToURL:(NSURL * _Nullable)appcastURL stateResolver:(SPUAppcastItemStateResolver *)stateResolver signingValidationStatus:(SPUAppcastSigningValidationStatus)signingValidationStatus error:(NSError *__autoreleasing*)errorp SPU_OBJC_DIRECT
{
    if (errorp) {
        *errorp = nil;
    }

    if (!appcastData) {
        return nil;
    }

    NSXMLNodeOptions options = NSXMLNodeLoadExternalEntitiesNever; // Prevent inclusion from file://
    NSXMLDocument *document = [[NSXMLDocument alloc] initWithData:appcastData options:options error:errorp];
    if (nil == document) {
        return nil;
    }

    NSArray *xmlItems = [document nodesForXPath:@"/rss/channel/item" error:errorp];
    if (nil == xmlItems) {
        return nil;
    }

    NSMutableArray *appcastItems = [NSMutableArray array];
    NSEnumerator *nodeEnum = [xmlItems objectEnumerator];
    NSXMLNode *node;

    while((node = [nodeEnum nextObject])) {
        NSMutableDictionary *nodesDict = [NSMutableDictionary dictionary];
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];

        // First, we'll "index" all the first-level children of this appcast item so we can pick them out by language later.
        if ([[node children] count]) {
            node = [node childAtIndex:0];
            while (nil != node) {
                NSString *name = [self sparkleNamespacedNameOfNode:node];
                if (name) {
                    NSMutableArray *nodes = [nodesDict objectForKey:name];
                    if (nodes == nil) {
                        nodes = [NSMutableArray array];
                        [nodesDict setObject:nodes forKey:name];
                    }
                    [nodes addObject:node];
                }
                node = [node nextSibling];
            }
        }

        for (NSString *name in nodesDict) {
            node = [self bestNodeInNodes:[nodesDict objectForKey:name] name:name];
            if ([name isEqualToString:SURSSElementEnclosure] || [name isEqualToString:SUAppcastElementCriticalUpdate]) {
                // These are flattened as a separate dictionary for some reason
                NSDictionary *innerDict = [self attributesOfNode:(NSXMLElement *)node];
                [dict setObject:innerDict forKey:name];
            } else if ([name isEqualToString:SURSSElementPubDate]) {
                // We don't want to parse and create a NSDate instance -
                // that's a risk we can avoid. We don't use the date anywhere other
                // than it being accessible from SUAppcastItem
                NSString *dateString = node.stringValue;
                if (dateString) {
                    [dict setObject:dateString forKey:name];
                }
            } else if ([name isEqualToString:SURSSElementDescription]) {
                NSString *description = node.stringValue;
                if (description != nil) {
                    NSDictionary *attributes = [self attributesOfNode:(NSXMLElement *)node];
                    NSString *descriptionFormat = attributes[SUAppcastAttributeFormat];
                    
                    NSMutableDictionary *descriptionDict = [NSMutableDictionary dictionary];
                    [descriptionDict setObject:description forKey:@"content"];
                    if (descriptionFormat != nil) {
                        [descriptionDict setObject:descriptionFormat forKey:@"format"];
                    }
                    
                    [dict setObject:descriptionDict forKey:SURSSElementDescription];
                }
            } else if ([name isEqualToString:SUAppcastElementReleaseNotesLink]) {
                NSString *releaseNotesLink = node.stringValue;
                if (releaseNotesLink != nil) {
                    NSDictionary *attributes = [self attributesOfNode:(NSXMLElement *)node];
                    
                    NSMutableDictionary *linkDict = [NSMutableDictionary dictionary];
                    [linkDict setObject:releaseNotesLink forKey:@"content"];
                    
                    NSString *edSignature = attributes[SUAppcastAttributeEDSignature];
                    if (edSignature != nil) {
                        [linkDict setObject:edSignature forKey:SUAppcastAttributeEDSignature];
                    }
                    
                    NSString *length = attributes[SUAppcastAttributeLength];
                    if (length != nil) {
                        [linkDict setObject:length forKey:SUAppcastAttributeLength];
                    }
                    
                    [dict setObject:linkDict forKey:SUAppcastElementReleaseNotesLink];
                }
            } else if ([name isEqualToString:SUAppcastElementDeltas]) {
                NSMutableArray *deltas = [NSMutableArray array];
                NSEnumerator *childEnum = [[node children] objectEnumerator];
                for (NSXMLNode *child in childEnum) {
                    if ([[child name] isEqualToString:SURSSElementEnclosure]) {
                        [deltas addObject:[self attributesOfNode:(NSXMLElement *)child]];
                    }
                }
                [dict setObject:deltas forKey:name];
            } else if ([name isEqualToString:SUAppcastElementTags]) {
                NSMutableArray *names = [NSMutableArray array];
                NSEnumerator *childEnum = [[node children] objectEnumerator];
                for (NSXMLNode *child in childEnum) {
                    NSString *childName = child.name;
                    if (childName) {
                        [names addObject:childName];
                    }
                }
                [dict setObject:names forKey:name];
            } else if ([name isEqualToString:SUAppcastElementInformationalUpdate]) {
                NSMutableSet *informationalUpdateVersions = [NSMutableSet set];
                NSEnumerator *childEnum = [[node children] objectEnumerator];
                for (NSXMLNode *child in childEnum) {
                    if ([child.name isEqualToString:SUAppcastElementVersion]) {
                        NSString *version = child.stringValue;
                        if (version != nil) {
                            [informationalUpdateVersions addObject:version];
                        }
                    } else if ([child.name isEqualToString:SUAppcastElementBelowVersion]) {
                        NSString *version = child.stringValue;
                        if (version != nil) {
                            // Denote version is used as an upper bound by using '<'
                            [informationalUpdateVersions addObject:[NSString stringWithFormat:@"<%@", version]];
                        }
                    }
                }
                [dict setObject:[informationalUpdateVersions copy] forKey:name];
            } else if (name != nil) {
                // add all other values as strings
                NSString *theValue = [[node stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (theValue != nil) {
                    [dict setObject:theValue forKey:name];
                }
            }
        }

        NSString *errString;
        SUAppcastItem *anItem = [[SUAppcastItem alloc] initWithDictionary:dict relativeToURL:appcastURL stateResolver:stateResolver signingValidationStatus:signingValidationStatus failureReason:&errString];
        
        if (anItem != nil) {
            [appcastItems addObject:anItem];
        } else {
            // An info-only update item could fail to be created when signing validation fails
            // Let's just resume creating the other appcast items in that case.
            if (signingValidationStatus != SPUAppcastSigningValidationStatusFailed) {
                SULog(SULogLevelError, @"Sparkle Updater: Failed to parse appcast item: %@.\nAppcast dictionary was: %@", errString, dict);
                if (errorp) *errorp = [NSError errorWithDomain:SUSparkleErrorDomain
                                                          code:SUAppcastParseError
                                                      userInfo:@{NSLocalizedDescriptionKey: errString}];
                
                return nil;
            }
        }
    }

    return appcastItems;
}

- (NSXMLNode *)bestNodeInNodes:(NSArray *)nodes name:(NSString *)name SPU_OBJC_DIRECT
{
    // We use this method to pick out the localized version of a node when one's available.
    if ([nodes count] == 1)
        return [nodes objectAtIndex:0];
    else if ([nodes count] == 0)
        return nil;

    // Now that we reached here, we are dealing with multiple nodes
    NSMutableArray<NSString *> *languages = [NSMutableArray array];
    for (NSXMLElement *node in nodes) {
        NSString *nodeLanguage = [[node attributeForName:SUXMLLanguage] stringValue];
        NSString *language;
        if (nodeLanguage.length == 0) {
            language = @"en";
            
            SULog(SULogLevelError, @"Error: Multiple nodes for %@ element are present and one of them does not have %@ attribute specified. Defaulting to %@=\"en\" but not all versions of Sparkle handle an implicit set language. Please specify the %@ attribute explicitly for all %@ elements.", name, SUXMLLanguage, SUXMLLanguage, SUXMLLanguage, name);
        } else {
            language = nodeLanguage;
        }
        
        [languages addObject:language];
    }
    
    NSString *preferredLanguage = [[NSBundle preferredLocalizationsFromArray:languages] objectAtIndex:0];
    if (preferredLanguage == nil) {
        SULog(SULogLevelError, @"Error: Failed to obtain preferred localizations from %@ for node %@.", languages, name);
        
        return [nodes objectAtIndex:0];
    }
    
    NSUInteger preferredLanguageIndex = [languages indexOfObject:preferredLanguage];
    if (preferredLanguageIndex == NSNotFound) {
        SULog(SULogLevelError, @"Error: Failed to find preferred language index for %@ for node %@.", preferredLanguage, name);
        
        return [nodes objectAtIndex:0];
    }
    
    return [nodes objectAtIndex:preferredLanguageIndex];
}

- (SUAppcast *)copyByFilteringItems:(BOOL (^)(SUAppcastItem *))filterBlock
{
    SUAppcast *other = [SUAppcast new];
    NSMutableArray *newItems = [NSMutableArray new];
    
    for (SUAppcastItem *item in _items) {
        if (filterBlock(item)) {
            [newItems addObject:item];
        }
    }
    
    other->_items = newItems;
    other->_signingValidationStatus = _signingValidationStatus;
    return other;
}

@end
