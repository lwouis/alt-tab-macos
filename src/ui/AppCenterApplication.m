@import Cocoa;
@import AppCenterCrashes;
#import "AppCenterApplication.h"

@implementation AppCenterApplication

- (void)reportException:(NSException*)exception {
  [MSACCrashes applicationDidReportException:exception];
  [super reportException:exception];
}

- (void)sendEvent:(NSEvent*)theEvent {
  @try {
    [super sendEvent:theEvent];
  } @catch (NSException* exception) {
    [self reportException:exception];
  }
}

@end
