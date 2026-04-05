// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACAbstractLogInternal.h"
#import "MSACAppCenterErrors.h"
#import "MSACAppCenterInternal.h"
#import "MSACCSExtensions.h"
#import "MSACConstants+Internal.h"
#import "MSACHttpIngestionPrivate.h"
#import "MSACLoggerInternal.h"
#import "MSACOneCollectorIngestionPrivate.h"
#import "MSACProtocolExtension.h"
#import "MSACTicketCache.h"
#import "MSACUtility+StringFormatting.h"

@implementation MSACOneCollectorIngestion

- (id)initWithHttpClient:(id<MSACHttpClientProtocol>)httpClient baseUrl:(NSString *)baseUrl {
  self = [super initWithHttpClient:httpClient
                           baseUrl:baseUrl
                           apiPath:[NSString stringWithFormat:@"%@/%@", kMSACOneCollectorApiPath, kMSACOneCollectorApiVersion]
                           headers:@{
                             kMSACHeaderContentTypeKey : kMSACOneCollectorContentType,
                             kMSACOneCollectorClientVersionKey :
                                 [NSString stringWithFormat:kMSACOneCollectorClientVersionFormat, [MSACUtility sdkVersion]]
                           }
                      queryStrings:nil
                    retryIntervals:@[ @(10), @(5 * 60), @(20 * 60) ]
            maxNumberOfConnections:2];
  return self;
}

- (void)sendAsync:(NSObject *)data completionHandler:(MSACSendAsyncCompletionHandler)handler {
  MSACLogContainer *container = (MSACLogContainer *)data;
  NSString *batchId = container.batchId;

  /*
   * FIXME: All logs are already validated at the time the logs are enqueued to Channel. It is not necessary but it can still protect
   * against invalid logs being sent to server that are messed up somehow in Storage. If we see performance issues due to this validation,
   * we will remove `[container isValid]` call below.
   */

  // Verify container.
  if (!container || ![container isValid]) {
    NSDictionary *userInfo = @{NSLocalizedDescriptionKey : kMSACACLogInvalidContainerErrorDesc};
    NSError *error = [NSError errorWithDomain:kMSACACErrorDomain code:MSACACLogInvalidContainerErrorCode userInfo:userInfo];
    MSACLogError([MSACAppCenter logTag], @"%@", [error localizedDescription]);
    handler(batchId, 0, nil, error);
    return;
  }
  [super sendAsync:container
      completionHandler:^(NSString *_Nonnull __unused callId, NSHTTPURLResponse *_Nullable response, NSData *_Nullable responseBody,
                          NSError *_Nullable error) {
        // Ignore the given call ID so that the container's batch ID can be used instead.
        handler(batchId, response, responseBody, error);
      }];
}

- (NSDictionary *)getHeadersWithData:(nullable NSObject *)data eTag:(nullable NSString *__unused)eTag {
  MSACLogContainer *container = (MSACLogContainer *)data;
  NSMutableDictionary *headers = [self.httpHeaders mutableCopy];
  NSMutableSet<NSString *> *apiKeys = [NSMutableSet new];
  for (id<MSACLog> log in container.logs) {
    [apiKeys addObjectsFromArray:[log.transmissionTargetTokens allObjects]];
  }
  headers[kMSACOneCollectorApiKey] = [[apiKeys allObjects] componentsJoinedByString:@","];
  headers[kMSACOneCollectorUploadTimeKey] = [NSString stringWithFormat:@"%lld", (long long)[MSACUtility nowInMilliseconds]];

  // Gather tokens from logs.
  NSMutableDictionary<NSString *, NSString *> *ticketsAndKeys = [NSMutableDictionary<NSString *, NSString *> new];
  for (id<MSACLog> log in container.logs) {
    MSACCommonSchemaLog *csLog = (MSACCommonSchemaLog *)log;
    if (csLog.ext.protocolExt) {
      NSArray<NSString *> *ticketKeys = [[[csLog ext] protocolExt] ticketKeys];
      for (NSString *ticketKey in ticketKeys) {
        NSString *authenticationToken = [[MSACTicketCache sharedInstance] ticketFor:ticketKey];
        if (authenticationToken) {
          [ticketsAndKeys setValue:authenticationToken forKey:ticketKey];
        }
      }
    }
  }
  if (ticketsAndKeys.count > 0) {
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:ticketsAndKeys options:0 error:nil];
    NSString *jsonString = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    [headers setValue:jsonString forKey:kMSACOneCollectorTicketsKey];
  }

  return headers;
}

- (NSData *)getPayloadWithData:(nullable NSObject *)data {
  MSACLogContainer *container = (MSACLogContainer *)data;
  NSMutableString *jsonString = [NSMutableString new];
  for (id<MSACLog> log in container.logs) {
    MSACAbstractLog *abstractLog = (MSACAbstractLog *)log;
    [jsonString appendString:[abstractLog serializeLogWithPrettyPrinting:NO]];

    // Separator for one collector logs.
    [jsonString appendString:kMSACOneCollectorLogSeparator];
  }
  NSData *httpBody = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
  return httpBody;
}

- (NSString *)obfuscateResponsePayload:(NSString *)payload {
  return [MSACUtility obfuscateString:payload
                  searchingForPattern:kMSACTokenKeyValuePattern
                toReplaceWithTemplate:kMSACTokenKeyValueObfuscatedTemplate];
}

- (NSString *)obfuscateTargetTokens:(NSString *)tokenString {
  NSArray *tokens = [tokenString componentsSeparatedByString:@","];
  NSMutableArray *obfuscatedTokens = [NSMutableArray new];
  for (NSString *token in tokens) {
    [obfuscatedTokens addObject:[MSACHttpUtil hideSecret:token]];
  }
  return [obfuscatedTokens componentsJoinedByString:@","];
}

- (NSString *)obfuscateTickets:(NSString *)ticketString {
  NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@":[^\"]+" options:0 error:nil];
  return [regex stringByReplacingMatchesInString:ticketString options:0 range:NSMakeRange(0, ticketString.length) withTemplate:@":***"];
}

- (void)willSendHTTPRequestToURL:(NSURL *)url withHeaders:(nullable NSDictionary<NSString *, NSString *> *)headers {

  // Don't lose time pretty printing headers if not going to be printed.
  if ([MSACLogger currentLogLevel] <= MSACLogLevelVerbose) {

    // Obfuscate secrets.
    NSMutableArray<NSString *> *flattenedHeaders = [NSMutableArray<NSString *> new];
    [headers enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop __unused) {
      if ([key isEqualToString:kMSACOneCollectorApiKey]) {
        value = [self obfuscateTargetTokens:value];
      } else if ([key isEqualToString:kMSACOneCollectorTicketsKey]) {
        value = [self obfuscateTickets:value];
      }
      [flattenedHeaders addObject:[NSString stringWithFormat:@"%@ = %@", key, value]];
    }];

    // Log URL and headers.
    MSACLogVerbose([MSACAppCenter logTag], @"URL: %@", url);
    MSACLogVerbose([MSACAppCenter logTag], @"Headers: %@", [flattenedHeaders componentsJoinedByString:@", "]);
  }
}

@end
