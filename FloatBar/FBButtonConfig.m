#import "FBButtonConfig.h"

static NSString * const kConfigKey = @"FBEnabledOrderedButtons";

@implementation FBButtonConfig

+ (NSString *)labelForType:(FBButtonType)type {
    switch (type) {
        case FBButtonTypeHome:        return @"Home";
        case FBButtonTypeBack:        return @"Retour";
        case FBButtonTypeAppSwitcher: return @"App Switcher";
        case FBButtonTypeCapture:     return @"Capture";
    }
    return @"?";
}

+ (NSString *)iconForType:(FBButtonType)type {
    // Minimal glyphs that render on any iOS version without needing SF Symbols runtime.
    switch (type) {
        case FBButtonTypeHome:        return @"⏺";
        case FBButtonTypeBack:        return @"◀";
        case FBButtonTypeAppSwitcher: return @"☰";
        case FBButtonTypeCapture:     return @"◉";
    }
    return @"?";
}

+ (NSArray<NSNumber *> *)allButtons {
    return @[
        @(FBButtonTypeHome),
        @(FBButtonTypeBack),
        @(FBButtonTypeAppSwitcher),
        @(FBButtonTypeCapture),
    ];
}

+ (NSArray<NSNumber *> *)enabledOrderedButtons {
    NSArray *stored = [[NSUserDefaults standardUserDefaults] arrayForKey:kConfigKey];
    if (stored) return stored;
    // Default order matches the app icon: camera, home, app switcher, back.
    return @[
        @(FBButtonTypeCapture),
        @(FBButtonTypeHome),
        @(FBButtonTypeAppSwitcher),
        @(FBButtonTypeBack),
    ];
}

+ (void)setEnabledOrderedButtons:(NSArray<NSNumber *> *)buttons {
    [[NSUserDefaults standardUserDefaults] setObject:buttons forKey:kConfigKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end
