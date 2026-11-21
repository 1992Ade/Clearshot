#import "FBAppDelegate.h"
#import "FBMainViewController.h"
#import <AVFoundation/AVFoundation.h>

@implementation FBAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // AVAudioSession in playback mode is a prerequisite for PiP to even be allowed.
    NSError *err = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback
                                            mode:AVAudioSessionModeMoviePlayback
                                         options:AVAudioSessionCategoryOptionMixWithOthers
                                           error:&err];
    [[AVAudioSession sharedInstance] setActive:YES error:&err];

    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.window.rootViewController = [FBMainViewController new];
    [self.window makeKeyAndVisible];
    return YES;
}

@end
