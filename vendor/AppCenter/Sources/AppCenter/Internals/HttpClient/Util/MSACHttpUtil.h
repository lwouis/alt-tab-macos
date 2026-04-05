// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.

#import <Foundation/Foundation.h>

static short const kMSACMaxCharactersDisplayedForAppSecret = 8;
static NSString *const kMSACHidingStringForAppSecret = @"*";

@interface MSACHttpUtil : NSObject

/**
 * Indicate if the http response is recoverable.
 *
 * @param statusCode Http status code.
 *
 * @return YES if it is recoverable.
 */
+ (BOOL)isRecoverableError:(NSInteger)statusCode;

/**
 * Indicate if the http response is a success response.
 *
 * @param statusCode Http status code.
 *
 * @return YES if it is a success code.
 */
+ (BOOL)isSuccessStatusCode:(NSInteger)statusCode;

/**
 * Indicate if error is due to no internet connection.
 *
 * @param error http error.
 *
 * @return YES if it is a no network connection error, NO otherwise.
 */
+ (BOOL)isNoInternetConnectionError:(NSError *)error;

/**
 * Indicate if error is because a secure connection could not be established, e.g. when using a public network that * is open but requires
 * accepting terms and conditions, and the user hasn't done that, yet.
 *
 * @param error http error.
 *
 * @return YES if it is an SSL connection error, NO otherwise.
 */
+ (BOOL)isSSLConnectionError:(NSError *)error;

/**
 * Hide a secret replacing the first N characters by a hiding character.
 *
 * @param secret the secret string.
 *
 * @return secret by hiding some characters.
 */
+ (NSString *)hideSecret:(NSString *)secret;

/**
 * Hide a secret in the string.
 *
 * @param string the string with secret part.
 * @param secret the secret string.
 *
 * @return string with the hiding secret.
 */
+ (NSString *)hideSecretInString:(NSString *)string secret:(NSString *)secret;

@end
