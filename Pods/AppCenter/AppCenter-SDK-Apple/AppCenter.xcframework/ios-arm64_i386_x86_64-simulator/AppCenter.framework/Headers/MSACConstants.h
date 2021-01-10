// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

/**
 *  Log Levels
 */
typedef NS_ENUM(NSUInteger, MSACLogLevel) {

  /**
   *  Logging will be very chatty
   */
  MSACLogLevelVerbose = 2,

  /**
   *  Debug information will be logged
   */
  MSACLogLevelDebug = 3,

  /**
   *  Information will be logged
   */
  MSACLogLevelInfo = 4,

  /**
   *  Errors and warnings will be logged
   */
  MSACLogLevelWarning = 5,

  /**
   *  Errors will be logged
   */
  MSACLogLevelError = 6,

  /**
   * Only critical errors will be logged
   */
  MSACLogLevelAssert = 7,

  /**
   *  Logging is disabled
   */
  MSACLogLevelNone = 99
} NS_SWIFT_NAME(LogLevel);

typedef NSString * (^MSACLogMessageProvider)(void)NS_SWIFT_NAME(LogMessageProvider);
typedef void (^MSACLogHandler)(MSACLogMessageProvider messageProvider, MSACLogLevel logLevel, NSString *tag, const char *file,
                               const char *function, uint line) NS_SWIFT_NAME(LogHandler);

/**
 * Channel priorities, check the kMSACPriorityCount if you add a new value.
 * The order matters here! Values NEED to range from low priority to high priority.
 */
typedef NS_ENUM(NSInteger, MSACPriority) { MSACPriorityBackground, MSACPriorityDefault, MSACPriorityHigh } NS_SWIFT_NAME(Priority);
static short const kMSACPriorityCount = MSACPriorityHigh + 1;

/**
 * The priority by which the modules are initialized.
 * MSACPriorityMax is reserved for only 1 module and this needs to be Crashes.
 * Crashes needs to be initialized first to catch crashes in our other SDK Modules (which will hopefully never happen) and to avoid losing
 * any log at crash time.
 */
typedef NS_ENUM(NSInteger, MSACInitializationPriority) {
  MSACInitializationPriorityDefault = 500,
  MSACInitializationPriorityHigh = 750,
  MSACInitializationPriorityMax = 999
} NS_SWIFT_NAME(InitializationPriority);

/**
 * Enum with the different HTTP status codes.
 */
typedef NS_ENUM(NSInteger, MSACHTTPCodesNo) {

  // Invalid
  MSACHTTPCodesNo0XXInvalidUnknown = 0,

  // Informational
  MSACHTTPCodesNo1XXInformationalUnknown = 1,
  MSACHTTPCodesNo100Continue = 100,
  MSACHTTPCodesNo101SwitchingProtocols = 101,
  MSACHTTPCodesNo102Processing = 102,

  // Success
  MSACHTTPCodesNo2XXSuccessUnknown = 2,
  MSACHTTPCodesNo200OK = 200,
  MSACHTTPCodesNo201Created = 201,
  MSACHTTPCodesNo202Accepted = 202,
  MSACHTTPCodesNo203NonAuthoritativeInformation = 203,
  MSACHTTPCodesNo204NoContent = 204,
  MSACHTTPCodesNo205ResetContent = 205,
  MSACHTTPCodesNo206PartialContent = 206,
  MSACHTTPCodesNo207MultiStatus = 207,
  MSACHTTPCodesNo208AlreadyReported = 208,
  MSACHTTPCodesNo209IMUsed = 209,

  // Redirection
  MSACHTTPCodesNo3XXSuccessUnknown = 3,
  MSACHTTPCodesNo300MultipleChoices = 300,
  MSACHTTPCodesNo301MovedPermanently = 301,
  MSACHTTPCodesNo302Found = 302,
  MSACHTTPCodesNo303SeeOther = 303,
  MSACHTTPCodesNo304NotModified = 304,
  MSACHTTPCodesNo305UseProxy = 305,
  MSACHTTPCodesNo306SwitchProxy = 306,
  MSACHTTPCodesNo307TemporaryRedirect = 307,
  MSACHTTPCodesNo308PermanentRedirect = 308,

  // Client error
  MSACHTTPCodesNo4XXSuccessUnknown = 4,
  MSACHTTPCodesNo400BadRequest = 400,
  MSACHTTPCodesNo401Unauthorised = 401,
  MSACHTTPCodesNo402PaymentRequired = 402,
  MSACHTTPCodesNo403Forbidden = 403,
  MSACHTTPCodesNo404NotFound = 404,
  MSACHTTPCodesNo405MethodNotAllowed = 405,
  MSACHTTPCodesNo406NotAcceptable = 406,
  MSACHTTPCodesNo407ProxyAuthenticationRequired = 407,
  MSACHTTPCodesNo408RequestTimeout = 408,
  MSACHTTPCodesNo409Conflict = 409,
  MSACHTTPCodesNo410Gone = 410,
  MSACHTTPCodesNo411LengthRequired = 411,
  MSACHTTPCodesNo412PreconditionFailed = 412,
  MSACHTTPCodesNo413RequestEntityTooLarge = 413,
  MSACHTTPCodesNo414RequestURITooLong = 414,
  MSACHTTPCodesNo415UnsupportedMediaType = 415,
  MSACHTTPCodesNo416RequestedRangeNotSatisfiable = 416,
  MSACHTTPCodesNo417ExpectationFailed = 417,
  MSACHTTPCodesNo418IamATeapot = 418,
  MSACHTTPCodesNo419AuthenticationTimeout = 419,
  MSACHTTPCodesNo420MethodFailureSpringFramework = 420,
  MSACHTTPCodesNo420EnhanceYourCalmTwitter = 4200,
  MSACHTTPCodesNo422UnprocessableEntity = 422,
  MSACHTTPCodesNo423Locked = 423,
  MSACHTTPCodesNo424FailedDependency = 424,
  MSACHTTPCodesNo424MethodFailureWebDaw = 4240,
  MSACHTTPCodesNo425UnorderedCollection = 425,
  MSACHTTPCodesNo426UpgradeRequired = 426,
  MSACHTTPCodesNo428PreconditionRequired = 428,
  MSACHTTPCodesNo429TooManyRequests = 429,
  MSACHTTPCodesNo431RequestHeaderFieldsTooLarge = 431,
  MSACHTTPCodesNo444NoResponseNginx = 444,
  MSACHTTPCodesNo449RetryWithMicrosoft = 449,
  MSACHTTPCodesNo450BlockedByWindowsParentalControls = 450,
  MSACHTTPCodesNo451RedirectMicrosoft = 451,
  MSACHTTPCodesNo451UnavailableForLegalReasons = 4510,
  MSACHTTPCodesNo494RequestHeaderTooLargeNginx = 494,
  MSACHTTPCodesNo495CertErrorNginx = 495,
  MSACHTTPCodesNo496NoCertNginx = 496,
  MSACHTTPCodesNo497HTTPToHTTPSNginx = 497,
  MSACHTTPCodesNo499ClientClosedRequestNginx = 499,

  // Server error
  MSACHTTPCodesNo5XXSuccessUnknown = 5,
  MSACHTTPCodesNo500InternalServerError = 500,
  MSACHTTPCodesNo501NotImplemented = 501,
  MSACHTTPCodesNo502BadGateway = 502,
  MSACHTTPCodesNo503ServiceUnavailable = 503,
  MSACHTTPCodesNo504GatewayTimeout = 504,
  MSACHTTPCodesNo505HTTPVersionNotSupported = 505,
  MSACHTTPCodesNo506VariantAlsoNegotiates = 506,
  MSACHTTPCodesNo507InsufficientStorage = 507,
  MSACHTTPCodesNo508LoopDetected = 508,
  MSACHTTPCodesNo509BandwidthLimitExceeded = 509,
  MSACHTTPCodesNo510NotExtended = 510,
  MSACHTTPCodesNo511NetworkAuthenticationRequired = 511,
  MSACHTTPCodesNo522ConnectionTimedOut = 522,
  MSACHTTPCodesNo598NetworkReadTimeoutErrorUnknown = 598,
  MSACHTTPCodesNo599NetworkConnectTimeoutErrorUnknown = 599
} NS_SWIFT_NAME(HTTPCodesNo);
