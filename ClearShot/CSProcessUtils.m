#import "CSProcessUtils.h"

#import <UIKit/UIKit.h>
#import <sys/sysctl.h>
#import <sys/types.h>
#import <sys/wait.h>
#import <signal.h>
#import <spawn.h>
#import <unistd.h>
#import <errno.h>
#import <mach/mach.h>

// ============================================================================
// Private posix_spawn persona helpers — same prototypes Andromeda/TrollFools
// use, resolved dynamically because the headers aren't shipped with the
// public SDK.
// ============================================================================
#define POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE 1
extern int posix_spawnattr_set_persona_np(const posix_spawnattr_t *__restrict,
                                          uid_t, uint32_t);
extern int posix_spawnattr_set_persona_uid_np(const posix_spawnattr_t *__restrict,
                                              uid_t);
extern int posix_spawnattr_set_persona_gid_np(const posix_spawnattr_t *__restrict,
                                              uid_t);

@interface UIApplication (CSPrivate)
- (void)suspend;
@end

@implementation CSProcessUtils

#pragma mark - Direct process enumeration + kill

+ (NSUInteger)killAllProcessesNamed:(NSString *)name {
    if (name.length == 0) return 0;

    NSUInteger killed = 0;

    // Sized sysctl walk over all processes. Same pattern as
    // Geranium/Andromeda's TSUtil.m — works on every iOS version we care about.
    int mib[3] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL };
    size_t length = 0;
    if (sysctl(mib, 3, NULL, &length, NULL, 0) < 0) {
        NSLog(@"[ClearShot/Proc] sysctl probe failed: %s", strerror(errno));
        return 0;
    }
    struct kinfo_proc *info = malloc(length);
    if (!info) return 0;
    if (sysctl(mib, 3, info, &length, NULL, 0) < 0) {
        NSLog(@"[ClearShot/Proc] sysctl read failed: %s", strerror(errno));
        free(info);
        return 0;
    }

    // We also need the executable path for each PID, which lives in
    // KERN_PROCARGS2. The lastPathComponent of that path is what we match
    // against `name` — directly comparing against kp_proc.p_comm would fail
    // for anything longer than 15 characters.
    static int argMax = 0;
    if (argMax == 0) {
        size_t s = sizeof(argMax);
        if (sysctl((int[]){ CTL_KERN, KERN_ARGMAX }, 2, &argMax, &s, NULL, 0) == -1) {
            argMax = 4096;
        }
    }

    int count = (int)(length / sizeof(struct kinfo_proc));
    for (int i = 0; i < count; i++) {
        @autoreleasepool {
            pid_t pid = info[i].kp_proc.p_pid;
            if (pid == 0) continue;

            size_t s = argMax;
            char *buf = malloc(s);
            if (!buf) continue;

            if (sysctl((int[]){ CTL_KERN, KERN_PROCARGS2, pid }, 3,
                       buf, &s, NULL, 0) == 0) {
                // First 4 bytes are argc, then argv[0] starts.
                NSString *execPath = [NSString stringWithCString:(buf + sizeof(int))
                                                        encoding:NSUTF8StringEncoding];
                if ([execPath.lastPathComponent isEqualToString:name]) {
                    if (kill(pid, SIGTERM) == 0) {
                        NSLog(@"[ClearShot/Proc] SIGTERM → %@ (pid=%d) ok", name, pid);
                        killed++;
                    } else {
                        NSLog(@"[ClearShot/Proc] SIGTERM → %@ (pid=%d) failed: %s",
                              name, pid, strerror(errno));
                    }
                }
            }
            free(buf);
        }
    }
    free(info);
    return killed;
}

#pragma mark - Respring

+ (void)forceRespring {
    NSLog(@"[ClearShot/Proc] forceRespring — uid=%d euid=%d", getuid(), geteuid());

    // Fade the UI out so the user sees SOMETHING happen even if our first
    // kill attempt is rejected — mirrors Andromeda's respring() look.
    UIViewPropertyAnimator *animator =
        [[UIViewPropertyAnimator alloc] initWithDuration:0.4
                                            dampingRatio:1.0
                                              animations:^{
            for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
                if (![s isKindOfClass:[UIWindowScene class]]) continue;
                for (UIWindow *w in ((UIWindowScene *)s).windows) {
                    w.alpha = 0;
                    w.transform = CGAffineTransformMakeScale(0.9, 0.9);
                }
            }
        }];

    [animator addCompletion:^(UIViewAnimatingPosition finalPosition) {
        // 1) Stop SpringBoard-family processes directly from in-process.
        NSUInteger n = 0;
        n += [self killAllProcessesNamed:@"SpringBoard"];
        n += [self killAllProcessesNamed:@"FrontBoard"];
        n += [self killAllProcessesNamed:@"BackBoard"];
        n += [self killAllProcessesNamed:@"backboardd"];
        NSLog(@"[ClearShot/Proc] forceRespring killed %lu processes",
              (unsigned long)n);

        // 2) Fallback A: Amy While's snapshot trick (works when we don't
        // actually have kill permission for SpringBoard but can wedge it
        // from our own window). Harmless if (1) already succeeded — the
        // loop just runs until we're torn down.
        if (n == 0) {
            UIApplication *app = UIApplication.sharedApplication;
            for (UIScene *s in app.connectedScenes) {
                if (![s isKindOfClass:[UIWindowScene class]]) continue;
                UIWindow *win = ((UIWindowScene *)s).windows.firstObject;
                if (!win) continue;
                // Bounded "forever" — we rely on being killed by SpringBoard
                // during the respring. If that doesn't happen within 2 s we
                // give up and exit ourselves.
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
                    while ([(NSDate *)[NSDate date] compare:deadline] == NSOrderedAscending) {
                        @autoreleasepool {
                            __unused UIView *v = [win snapshotViewAfterScreenUpdates:NO];
                        }
                    }
                });
                break;
            }
        }

        // 3) Fallback B: suspend ourselves then exit. If SpringBoard did
        // respawn from (1), it'll kill us during the transition and
        // exit(0) never runs. If it didn't, we at least drop back to home
        // so the user sees the state change.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.1 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            UIApplication *app = UIApplication.sharedApplication;
            if ([app respondsToSelector:@selector(suspend)]) {
                [app performSelector:@selector(suspend)];
            }
            // Give iOS a moment to animate home, then bail.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                exit(0);
            });
        });
    }];

    [animator startAnimation];
}

#pragma mark - rootSpawn (TrollFools / Andromeda pattern)

+ (int)rootSpawn:(NSString *)path
              args:(NSArray<NSString *> *)args
            stdOut:(NSString * _Nullable * _Nullable)stdOut
            stdErr:(NSString * _Nullable * _Nullable)stdErr {
    NSMutableArray<NSString *> *argv = args.mutableCopy ?: [NSMutableArray new];
    [argv insertObject:path.lastPathComponent atIndex:0];

    NSUInteger argc = argv.count;
    char **argvC = malloc((argc + 1) * sizeof(char *));
    for (NSUInteger i = 0; i < argc; i++) argvC[i] = strdup([argv[i] UTF8String]);
    argvC[argc] = NULL;

    posix_spawnattr_t attr;
    posix_spawnattr_init(&attr);
    // These three are what makes the spawned child land at uid 0 on
    // iOS 15.7+ TrollStore installs.
    posix_spawnattr_set_persona_np(&attr, 99, POSIX_SPAWN_PERSONA_FLAGS_OVERRIDE);
    posix_spawnattr_set_persona_uid_np(&attr, 0);
    posix_spawnattr_set_persona_gid_np(&attr, 0);

    posix_spawn_file_actions_t action;
    posix_spawn_file_actions_init(&action);

    int outPipe[2] = { -1, -1 };
    int errPipe[2] = { -1, -1 };
    if (stdOut) {
        pipe(outPipe);
        posix_spawn_file_actions_adddup2(&action, outPipe[1], STDOUT_FILENO);
        posix_spawn_file_actions_addclose(&action, outPipe[0]);
    }
    if (stdErr) {
        pipe(errPipe);
        posix_spawn_file_actions_adddup2(&action, errPipe[1], STDERR_FILENO);
        posix_spawn_file_actions_addclose(&action, errPipe[0]);
    }

    pid_t childPid = 0;
    int spawnErr = posix_spawn(&childPid, [path UTF8String], &action, &attr,
                               argvC, NULL);
    posix_spawnattr_destroy(&attr);
    posix_spawn_file_actions_destroy(&action);
    for (NSUInteger i = 0; i < argc; i++) free(argvC[i]);
    free(argvC);

    if (spawnErr != 0) {
        NSLog(@"[ClearShot/Proc] posix_spawn(%@) failed: %s",
              path, strerror(spawnErr));
        if (outPipe[0] != -1) { close(outPipe[0]); close(outPipe[1]); }
        if (errPipe[0] != -1) { close(errPipe[0]); close(errPipe[1]); }
        return -1;
    }

    // Close the write ends in the parent so reads from the pipe return
    // EOF once the child exits.
    if (outPipe[1] != -1) close(outPipe[1]);
    if (errPipe[1] != -1) close(errPipe[1]);

    int status = 0;
    while (waitpid(childPid, &status, 0) == -1) {
        if (errno != EINTR) {
            NSLog(@"[ClearShot/Proc] waitpid: %s", strerror(errno));
            return -1;
        }
    }

    if (stdOut) {
        NSMutableData *buf = [NSMutableData data];
        char chunk[512];
        ssize_t n;
        while ((n = read(outPipe[0], chunk, sizeof(chunk))) > 0) {
            [buf appendBytes:chunk length:(NSUInteger)n];
        }
        close(outPipe[0]);
        *stdOut = [[NSString alloc] initWithData:buf encoding:NSUTF8StringEncoding];
    }
    if (stdErr) {
        NSMutableData *buf = [NSMutableData data];
        char chunk[512];
        ssize_t n;
        while ((n = read(errPipe[0], chunk, sizeof(chunk))) > 0) {
            [buf appendBytes:chunk length:(NSUInteger)n];
        }
        close(errPipe[0]);
        *stdErr = [[NSString alloc] initWithData:buf encoding:NSUTF8StringEncoding];
    }

    return WIFEXITED(status) ? WEXITSTATUS(status) : -1;
}

#pragma mark - Diagnostic

+ (NSString *)currentProcessIdentitySummary {
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"pid=%d  uid=%d  euid=%d  gid=%d  egid=%d\n",
     getpid(), getuid(), geteuid(), getgid(), getegid()];
    NSString *exec = [[NSBundle mainBundle] executablePath];
    [s appendFormat:@"exec: %@\n", exec];
    UIDevice *d = [UIDevice currentDevice];
    [s appendFormat:@"iOS %@ · %@\n", d.systemVersion, d.model];
    return s;
}

@end
