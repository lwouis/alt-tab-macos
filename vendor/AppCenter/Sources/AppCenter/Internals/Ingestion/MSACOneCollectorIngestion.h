// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import "MSACHttpIngestion.h"

static NSString *const kMSACOneCollectorApiKey = @"apikey";
static NSString *const kMSACOneCollectorApiPath = @"/OneCollector";
static NSString *const kMSACOneCollectorApiVersion = @"1.0";

/**
 * Assign value in header to avoid "format is not a string literal" warning.
 * The convention for this format string is <sdktype>-<platform>-<language>-<projection>-<version>-<tag>.
 */
static NSString *const kMSACOneCollectorClientVersionFormat = @"ACS-iOS-ObjectiveC-no-%@-no";
static NSString *const kMSACOneCollectorClientVersionKey = @"Client-Version";
static NSString *const kMSACOneCollectorContentType = @"application/x-json-stream; charset=utf-8";
static NSString *const kMSACOneCollectorLogSeparator = @"\n";
static NSString *const kMSACOneCollectorTicketsKey = @"Tickets";
static NSString *const kMSACOneCollectorUploadTimeKey = @"Upload-Time";

@interface MSACOneCollectorIngestion : MSACHttpIngestion

/**
 * Initialize the ingestion.
 *
 * @param baseUrl Base url.
 *
 * @return An ingestion instance.
 */
- (id)initWithHttpClient:(id<MSACHttpClientProtocol>)httpClient baseUrl:(NSString *)baseUrl;

@end
