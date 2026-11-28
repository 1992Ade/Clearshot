#import "CSRecordSettingsViewController.h"

static NSString * const kFPSKey      = @"TBCSRecordFPS";
static NSString * const kResModeKey  = @"TBCSRecordResMode";
static NSString * const kAudioSysKey = @"TBCSRecordAudioSystem";
static NSString * const kAudioMicKey = @"TBCSRecordAudioMic";
static NSString * const kFormatKey   = @"TBCSRecordFormat";

@interface CSRecordSettingsViewController ()
@property (strong, nonatomic) UISwitch *audioSysSwitch;
@property (strong, nonatomic) UISwitch *audioMicSwitch;
@end

@implementation CSRecordSettingsViewController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {}
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    self.tableView.backgroundColor = self.view.backgroundColor;
    self.title = @"Record settings";
}

#pragma mark - Model helpers

- (int)currentFPS {
    int v = (int)[[NSUserDefaults standardUserDefaults] integerForKey:kFPSKey];
    return (v >= 5 && v <= 60) ? v : 30;
}
- (void)setCurrentFPS:(int)v {
    [[NSUserDefaults standardUserDefaults] setInteger:v forKey:kFPSKey];
}

- (NSString *)currentResMode {
    NSString *m = [[NSUserDefaults standardUserDefaults] stringForKey:kResModeKey];
    return m.length ? m : @"native";
}
- (void)setCurrentResMode:(NSString *)m {
    [[NSUserDefaults standardUserDefaults] setObject:m forKey:kResModeKey];
}

- (NSString *)currentFormat {
    NSString *f = [[NSUserDefaults standardUserDefaults] stringForKey:kFormatKey];
    return f.length ? f : @"h264";
}
- (void)setCurrentFormat:(NSString *)f {
    [[NSUserDefaults standardUserDefaults] setObject:f forKey:kFormatKey];
}

#pragma mark - Table layout
// 0: FPS (15/24/30/60)
// 1: Resolution (native/720/480)
// 2: Audio (system + mic toggles)
// 3: Format (h264/hevc)

static NSArray *kFPSChoices(void)    { return @[ @15, @24, @30, @60 ]; }
static NSArray *kResChoices(void)    { return @[ @"native", @"720", @"480" ]; }
static NSArray *kFormatChoices(void) { return @[ @"h264", @"hevc" ]; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return kFPSChoices().count;
    if (s == 1) return kResChoices().count;
    if (s == 2) return 2;
    return kFormatChoices().count;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == 0) return @"Frame rate";
    if (s == 1) return @"Resolution";
    if (s == 2) return @"Audio";
    return @"Format";
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) return @"60 FPS on A9 may drop frames — the CARenderServer "
                        @"source runs at ~45 Hz effective on iPhone SE 1st-gen.";
    if (s == 1) return @"Smaller resolution = lighter file size, slightly "
                        @"faster encoding.";
    if (s == 3) return @"HEVC files are smaller but need H.265-capable hardware "
                        @"on the target device (A10+). H.264 is universal.";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc]
                              initWithStyle:UITableViewCellStyleSubtitle
                             reuseIdentifier:nil];
    cell.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.detailTextLabel.textColor = [UIColor lightGrayColor];
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (ip.section == 0) {
        NSNumber *n = kFPSChoices()[ip.row];
        cell.textLabel.text = [NSString stringWithFormat:@"%@ FPS", n];
        if ([n intValue] == 60) {
            cell.detailTextLabel.text = @"⚠ A9 may drop frames";
        } else if ([n intValue] == 24) {
            cell.detailTextLabel.text = @"Cinematic";
        } else if ([n intValue] == 30) {
            cell.detailTextLabel.text = @"Default";
        } else {
            cell.detailTextLabel.text = @"Small files";
        }
        if ([n intValue] == [self currentFPS]) {
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
        }

    } else if (ip.section == 1) {
        NSString *m = kResChoices()[ip.row];
        cell.textLabel.text = [m isEqualToString:@"native"] ? @"Native (hardware)"
                               : [NSString stringWithFormat:@"%@p", m];
        if ([m isEqualToString:[self currentResMode]]) {
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
        }

    } else if (ip.section == 2) {
        if (ip.row == 0) {
            cell.textLabel.text = @"Record system audio";
            if (!self.audioSysSwitch) {
                self.audioSysSwitch = [[UISwitch alloc] init];
                self.audioSysSwitch.on =
                    [[NSUserDefaults standardUserDefaults] boolForKey:kAudioSysKey];
                [self.audioSysSwitch addTarget:self action:@selector(didToggleAudioSys:)
                                forControlEvents:UIControlEventValueChanged];
            }
            cell.accessoryView = self.audioSysSwitch;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            cell.textLabel.text = @"Record microphone";
            if (!self.audioMicSwitch) {
                self.audioMicSwitch = [[UISwitch alloc] init];
                self.audioMicSwitch.on =
                    [[NSUserDefaults standardUserDefaults] boolForKey:kAudioMicKey];
                [self.audioMicSwitch addTarget:self action:@selector(didToggleAudioMic:)
                                forControlEvents:UIControlEventValueChanged];
            }
            cell.accessoryView = self.audioMicSwitch;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }

    } else {
        NSString *f = kFormatChoices()[ip.row];
        cell.textLabel.text = [f isEqualToString:@"hevc"] ? @"HEVC (H.265)" : @"H.264";
        cell.detailTextLabel.text = [f isEqualToString:@"hevc"] ? @"Smaller files, A10+ playback"
                                                                  : @"Universal playback";
        if ([f isEqualToString:[self currentFormat]]) {
            cell.accessoryType = UITableViewCellAccessoryCheckmark;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 2) return;
    if (ip.section == 0) [self setCurrentFPS:[kFPSChoices()[ip.row] intValue]];
    if (ip.section == 1) [self setCurrentResMode:kResChoices()[ip.row]];
    if (ip.section == 3) [self setCurrentFormat:kFormatChoices()[ip.row]];
    [tv reloadData];
}

- (void)didToggleAudioSys:(UISwitch *)sw {
    [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:kAudioSysKey];
}
- (void)didToggleAudioMic:(UISwitch *)sw {
    [[NSUserDefaults standardUserDefaults] setBool:sw.on forKey:kAudioMicKey];
}

@end
