#import "ADMainViewController.h"
#import <sys/sysctl.h>
#import <sys/mount.h>
#import <sys/utsname.h>
#import <mach/mach.h>
#import <mach/mach_host.h>
#import <ifaddrs.h>
#import <arpa/inet.h>
#import <net/if.h>

// Private IOKit power source bits used by NiceBattery / BatteryBuddy /
// coconutBattery iOS. Only usable because our entitlements bring
// IOSurface + IOKit user-client access.
typedef struct __IOPSPowerSource *IOPSPowerSourceRef;
extern CFTypeRef IOPSCopyPowerSourcesInfo(void);
extern CFArrayRef IOPSCopyPowerSourcesList(CFTypeRef blob);
extern CFDictionaryRef IOPSGetPowerSourceDescription(CFTypeRef blob, CFTypeRef ps);
// Private keys — strings, not symbols.
#define kIOPMPSAppleRawMaxCapacityKey  @"AppleRawMaxCapacity"
#define kIOPMPSDesignCapacityKey       @"DesignCapacity"
#define kIOPMPSCycleCountKey           @"CycleCount"
#define kIOPMPSVoltageKey              @"Voltage"
#define kIOPMPSTemperatureKey          @"Temperature"
#define kIOPMPSTimeRemainingKey        @"TimeRemaining"

@interface ADSection : NSObject
@property (copy) NSString *title;
@property (copy) NSArray<NSArray<NSString *> *> *rows; // @[@[label, value], ...]
@end
@implementation ADSection
@end

@interface ADMainViewController ()
@property (strong, nonatomic) NSArray<ADSection *> *sections;
@end

@implementation ADMainViewController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"About Device";
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    self.tableView.backgroundColor = self.view.backgroundColor;

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                       target:self
                                                       action:@selector(reload)];

    [[UIDevice currentDevice] setBatteryMonitoringEnabled:YES];
    [self reload];
}

- (void)reload {
    NSMutableArray *s = [NSMutableArray array];
    [s addObject:[self batterySection]];
    [s addObject:[self deviceSection]];
    [s addObject:[self cpuSection]];
    [s addObject:[self memorySection]];
    [s addObject:[self storageSection]];
    [s addObject:[self networkSection]];
    self.sections = s;
    [self.tableView reloadData];
}

#pragma mark - Battery

- (ADSection *)batterySection {
    ADSection *sec = [ADSection new];
    sec.title = @"Battery";
    NSMutableArray *rows = [NSMutableArray array];

    UIDevice *dev = [UIDevice currentDevice];
    float level = dev.batteryLevel;  // -1 when unknown
    UIDeviceBatteryState state = dev.batteryState;
    NSString *stateStr = @"Unknown";
    switch (state) {
        case UIDeviceBatteryStateUnknown:   stateStr = @"Unknown"; break;
        case UIDeviceBatteryStateUnplugged: stateStr = @"On battery"; break;
        case UIDeviceBatteryStateCharging:  stateStr = @"Charging"; break;
        case UIDeviceBatteryStateFull:      stateStr = @"Full"; break;
    }
    if (level >= 0) {
        [rows addObject:@[@"Current charge",
                          [NSString stringWithFormat:@"%.0f%%", level * 100]]];
    }
    [rows addObject:@[@"State", stateStr]];

    // Private IOKit path — only works with our entitlements.
    CFTypeRef blob = IOPSCopyPowerSourcesInfo();
    if (blob) {
        CFArrayRef list = IOPSCopyPowerSourcesList(blob);
        if (list && CFArrayGetCount(list) > 0) {
            CFDictionaryRef desc = IOPSGetPowerSourceDescription(blob, CFArrayGetValueAtIndex(list, 0));
            NSDictionary *d = (__bridge NSDictionary *)desc;
            NSNumber *designMAh = d[kIOPMPSDesignCapacityKey];
            NSNumber *rawMAh    = d[kIOPMPSAppleRawMaxCapacityKey];
            NSNumber *cycles    = d[kIOPMPSCycleCountKey];
            NSNumber *voltageMV = d[kIOPMPSVoltageKey];
            NSNumber *temp      = d[kIOPMPSTemperatureKey];
            NSNumber *remaining = d[kIOPMPSTimeRemainingKey];

            if (designMAh) [rows addObject:@[@"Design capacity",
                                             [NSString stringWithFormat:@"%@ mAh", designMAh]]];
            if (rawMAh)    [rows addObject:@[@"Current max",
                                             [NSString stringWithFormat:@"%@ mAh", rawMAh]]];
            if (designMAh.doubleValue > 0 && rawMAh.doubleValue > 0) {
                double pct = rawMAh.doubleValue / designMAh.doubleValue * 100.0;
                [rows addObject:@[@"Battery health",
                                  [NSString stringWithFormat:@"%.1f %%", pct]]];
            }
            if (cycles)    [rows addObject:@[@"Cycle count", cycles.stringValue]];
            if (voltageMV) [rows addObject:@[@"Voltage",
                                             [NSString stringWithFormat:@"%.3f V",
                                              voltageMV.doubleValue / 1000.0]]];
            if (temp) [rows addObject:@[@"Temperature",
                                        [NSString stringWithFormat:@"%.1f °C",
                                         temp.doubleValue / 100.0]]];
            if (remaining && remaining.intValue > 0) {
                int mins = remaining.intValue;
                [rows addObject:@[@"Time remaining",
                                  [NSString stringWithFormat:@"%d h %02d min",
                                   mins / 60, mins % 60]]];
            }
        }
        if (list) CFRelease(list);
        CFRelease(blob);
    }

    sec.rows = rows;
    return sec;
}

#pragma mark - Device

- (ADSection *)deviceSection {
    ADSection *sec = [ADSection new];
    sec.title = @"Device";
    NSMutableArray *rows = [NSMutableArray array];
    UIDevice *dev = [UIDevice currentDevice];

    [rows addObject:@[@"Name", dev.name]];
    [rows addObject:@[@"Model", dev.model]];

    struct utsname sys;
    uname(&sys);
    [rows addObject:@[@"Identifier",
                      [NSString stringWithUTF8String:sys.machine]]];
    [rows addObject:@[@"iOS", [NSString stringWithFormat:@"%@", dev.systemVersion]]];

    char build[64] = {0};
    size_t bs = sizeof(build);
    if (sysctlbyname("kern.osversion", build, &bs, NULL, 0) == 0) {
        [rows addObject:@[@"Build", [NSString stringWithUTF8String:build]]];
    }

    // Uptime
    struct timeval boot;
    size_t bsz = sizeof(boot);
    int mib[] = { CTL_KERN, KERN_BOOTTIME };
    if (sysctl(mib, 2, &boot, &bsz, NULL, 0) == 0) {
        NSTimeInterval up = [[NSDate date] timeIntervalSince1970] - boot.tv_sec;
        int days  = (int)(up / 86400);
        int hours = (int)((up - days * 86400) / 3600);
        int mins  = (int)((up - days * 86400 - hours * 3600) / 60);
        [rows addObject:@[@"Uptime",
                          [NSString stringWithFormat:@"%dd %dh %dm", days, hours, mins]]];
    }

    sec.rows = rows;
    return sec;
}

#pragma mark - CPU

- (ADSection *)cpuSection {
    ADSection *sec = [ADSection new];
    sec.title = @"CPU";
    NSMutableArray *rows = [NSMutableArray array];

    int ncpu = 0, nactive = 0;
    size_t sz = sizeof(int);
    sysctlbyname("hw.physicalcpu", &ncpu, &sz, NULL, 0);
    sysctlbyname("hw.activecpu", &nactive, &sz, NULL, 0);
    [rows addObject:@[@"Physical cores", [NSString stringWithFormat:@"%d", ncpu]]];
    [rows addObject:@[@"Active cores",   [NSString stringWithFormat:@"%d", nactive]]];

    char brand[128] = {0}; size_t bs = sizeof(brand);
    if (sysctlbyname("machdep.cpu.brand_string", brand, &bs, NULL, 0) == 0 && brand[0]) {
        [rows addObject:@[@"CPU", [NSString stringWithUTF8String:brand]]];
    }

    sec.rows = rows;
    return sec;
}

#pragma mark - Memory

- (ADSection *)memorySection {
    ADSection *sec = [ADSection new];
    sec.title = @"Memory";
    NSMutableArray *rows = [NSMutableArray array];

    int64_t total = [NSProcessInfo processInfo].physicalMemory;
    [rows addObject:@[@"Total RAM", [self humanBytes:total]]];

    vm_size_t pageSize;
    vm_statistics64_data_t vm;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    host_page_size(mach_host_self(), &pageSize);
    if (host_statistics64(mach_host_self(), HOST_VM_INFO64,
                          (host_info64_t)&vm, &count) == KERN_SUCCESS) {
        uint64_t used = ((uint64_t)vm.active_count + vm.inactive_count +
                          vm.wire_count + vm.compressor_page_count) * pageSize;
        [rows addObject:@[@"Used", [self humanBytes:used]]];
        uint64_t free = (uint64_t)vm.free_count * pageSize;
        [rows addObject:@[@"Free", [self humanBytes:free]]];
    }

    sec.rows = rows;
    return sec;
}

#pragma mark - Storage

- (ADSection *)storageSection {
    ADSection *sec = [ADSection new];
    sec.title = @"Storage";
    NSMutableArray *rows = [NSMutableArray array];

    struct statfs sfs;
    if (statfs("/var", &sfs) == 0) {
        uint64_t totalBytes = (uint64_t)sfs.f_blocks * sfs.f_bsize;
        uint64_t freeBytes  = (uint64_t)sfs.f_bavail * sfs.f_bsize;
        uint64_t usedBytes  = totalBytes - freeBytes;
        [rows addObject:@[@"Total", [self humanBytes:totalBytes]]];
        [rows addObject:@[@"Used",  [self humanBytes:usedBytes]]];
        [rows addObject:@[@"Free",  [self humanBytes:freeBytes]]];
    }

    sec.rows = rows;
    return sec;
}

#pragma mark - Network

- (ADSection *)networkSection {
    ADSection *sec = [ADSection new];
    sec.title = @"Network";
    NSMutableArray *rows = [NSMutableArray array];

    struct ifaddrs *ifa_list = NULL;
    if (getifaddrs(&ifa_list) == 0) {
        for (struct ifaddrs *ifa = ifa_list; ifa; ifa = ifa->ifa_next) {
            if (!ifa->ifa_addr) continue;
            if (ifa->ifa_addr->sa_family != AF_INET) continue;
            if (!(ifa->ifa_flags & IFF_UP)) continue;
            NSString *name = [NSString stringWithUTF8String:ifa->ifa_name];
            if ([name isEqualToString:@"lo0"]) continue;
            char ip[INET_ADDRSTRLEN] = {0};
            inet_ntop(AF_INET,
                      &((struct sockaddr_in *)ifa->ifa_addr)->sin_addr,
                      ip, sizeof(ip));
            NSString *label = [name hasPrefix:@"en"]  ? @"Wi-Fi"
                            : [name hasPrefix:@"pdp"] ? @"Cellular"
                                                     : name;
            [rows addObject:@[label, [NSString stringWithUTF8String:ip]]];
        }
        freeifaddrs(ifa_list);
    }
    if (rows.count == 0) [rows addObject:@[@"Status", @"Not connected"]];

    sec.rows = rows;
    return sec;
}

#pragma mark - Format helper

- (NSString *)humanBytes:(int64_t)bytes {
    NSByteCountFormatter *f = [[NSByteCountFormatter alloc] init];
    f.countStyle = NSByteCountFormatterCountStyleBinary;
    return [f stringFromByteCount:bytes];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return self.sections.count; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return self.sections[s].rows.count;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return self.sections[s].title;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *kId = @"c";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:kId];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                             reuseIdentifier:kId];
    NSArray *r = self.sections[ip.section].rows[ip.row];
    cell.textLabel.text = r[0];
    cell.detailTextLabel.text = r[1];
    cell.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.detailTextLabel.textColor = [UIColor lightGrayColor];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

@end
