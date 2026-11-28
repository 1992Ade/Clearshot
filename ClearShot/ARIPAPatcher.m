#import "ARIPAPatcher.h"
#import "CSProcessUtils.h"
#import <mach-o/loader.h>
#import <mach-o/fat.h>

// ============================================================================
// ARIPAPatcher — MinimumOSVersion patcher for IPAs.
//
// Workflow:
//   1. Unzip the source IPA into a temporary work directory via /usr/bin/zip
//      (invoked through rootSpawn with no persona override since we already
//      run at euid=0 after setuid(0)).
//   2. Locate Payload/<App>.app/Info.plist, edit the MinimumOSVersion key.
//   3. Locate the Mach-O executable (its CFBundleExecutable path) and patch
//      the minos field of LC_BUILD_VERSION / LC_VERSION_MIN_IPHONEOS.
//   4. Re-zip Payload/ back into a new .ipa.
//   5. Return the new .ipa path.
//
// Minos is encoded as nibbled u32: 0xMMMMmm00 in LC_VERSION_MIN_IPHONEOS, or
// as an xxxxyy packed format (xxxx.yy.00) in LC_BUILD_VERSION. We rewrite
// both forms if present. The binary's codesign signature is NOT re-generated
// here — TrollStore accepts an ad-hoc modified binary when installing a
// side-loaded IPA (the FairPlay fairplay-encrypted __TEXT isn't touched),
// but if you want extra safety call ldid -S on the result from the shell.
// ============================================================================

@implementation ARIPAPatcher

#pragma mark - Public

+ (NSString *)minimumOSVersionOfIPAAtPath:(NSString *)sourceIPA
                                     error:(NSError **)err {
    NSString *work = [self makeWorkDirForIPA:sourceIPA];
    if (!work) {
        if (err) *err = [self errorWithMessage:@"Couldn't create a work directory."];
        return nil;
    }
    if (![self unzipIPA:sourceIPA toDirectory:work error:err]) return nil;
    NSString *plistPath = [self infoPlistInsideWorkDir:work];
    if (!plistPath) {
        if (err) *err = [self errorWithMessage:@"No Payload/*.app/Info.plist in IPA."];
        return nil;
    }
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plistPath];
    NSString *ver = info[@"MinimumOSVersion"];
    [[NSFileManager defaultManager] removeItemAtPath:work error:nil];
    return ver;
}

+ (NSString *)patchedIPAFromIPAAtPath:(NSString *)sourceIPA
                 newMinimumOSVersion:(NSString *)newVersion
                               error:(NSError **)err {
    if (!sourceIPA.length || !newVersion.length) {
        if (err) *err = [self errorWithMessage:@"Source IPA path or new version empty."];
        return nil;
    }

    NSString *work = [self makeWorkDirForIPA:sourceIPA];
    if (!work) {
        if (err) *err = [self errorWithMessage:@"Couldn't create a work directory."];
        return nil;
    }
    if (![self unzipIPA:sourceIPA toDirectory:work error:err]) return nil;

    NSString *plistPath = [self infoPlistInsideWorkDir:work];
    if (!plistPath) {
        if (err) *err = [self errorWithMessage:@"No Payload/*.app/Info.plist in IPA."];
        [[NSFileManager defaultManager] removeItemAtPath:work error:nil];
        return nil;
    }

    // 1) Patch Info.plist
    NSMutableDictionary *info = [[NSMutableDictionary alloc]
                                  initWithContentsOfFile:plistPath];
    if (!info) {
        if (err) *err = [self errorWithMessage:@"Info.plist unreadable."];
        [[NSFileManager defaultManager] removeItemAtPath:work error:nil];
        return nil;
    }
    info[@"MinimumOSVersion"] = newVersion;
    if (![info writeToFile:plistPath atomically:YES]) {
        if (err) *err = [self errorWithMessage:@"Couldn't write patched Info.plist."];
        [[NSFileManager defaultManager] removeItemAtPath:work error:nil];
        return nil;
    }

    // 2) Patch the Mach-O executable
    NSString *appDir = [plistPath stringByDeletingLastPathComponent];
    NSString *execName = info[@"CFBundleExecutable"];
    if (execName.length) {
        NSString *execPath = [appDir stringByAppendingPathComponent:execName];
        if ([[NSFileManager defaultManager] fileExistsAtPath:execPath]) {
            [self patchMachOExecutableAtPath:execPath
                                   toVersion:newVersion];
        }
    }

    // 3) Re-zip. Place output in NSTemporaryDirectory with a readable name.
    NSString *base = [[sourceIPA lastPathComponent] stringByDeletingPathExtension];
    NSString *outIPA = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"%@-patched-%@.ipa",
                          base, newVersion]];
    [[NSFileManager defaultManager] removeItemAtPath:outIPA error:nil];
    if (![self zipDirectory:work toIPA:outIPA error:err]) {
        [[NSFileManager defaultManager] removeItemAtPath:work error:nil];
        return nil;
    }
    [[NSFileManager defaultManager] removeItemAtPath:work error:nil];
    return outIPA;
}

#pragma mark - Work directory + (un)zip

+ (NSString *)makeWorkDirForIPA:(NSString *)sourceIPA {
    NSString *base = [[sourceIPA lastPathComponent] stringByDeletingPathExtension];
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      [NSString stringWithFormat:@"ARWork-%@-%u",
                       base, arc4random()]];
    NSError *err = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:dir
                                   withIntermediateDirectories:YES
                                                    attributes:nil error:&err]) {
        NSLog(@"[ARPatcher] mkdir %@ err=%@", dir, err);
        return nil;
    }
    return dir;
}

+ (BOOL)unzipIPA:(NSString *)ipa toDirectory:(NSString *)dir
           error:(NSError **)err {
    NSString *out = nil, *errStr = nil;
    int rc = [CSProcessUtils rootSpawn:@"/usr/bin/unzip"
                                  args:@[@"-q", @"-o", ipa, @"-d", dir]
                                stdOut:&out stdErr:&errStr];
    if (rc != 0) {
        if (err) *err = [self errorWithMessage:
                          [NSString stringWithFormat:@"unzip failed (rc=%d). %@",
                           rc, errStr.length ? errStr : @""]];
        return NO;
    }
    return YES;
}

+ (BOOL)zipDirectory:(NSString *)dir toIPA:(NSString *)outIPA
               error:(NSError **)err {
    // zip -r <out> Payload (run from `dir` so paths are relative)
    NSString *shellCmd = [NSString stringWithFormat:
        @"cd %@ && /usr/bin/zip -qry %@ Payload",
        [self shellQuote:dir], [self shellQuote:outIPA]];
    NSString *out = nil, *errStr = nil;
    int rc = [CSProcessUtils rootSpawn:@"/bin/sh"
                                  args:@[@"-c", shellCmd]
                                stdOut:&out stdErr:&errStr];
    if (rc != 0) {
        if (err) *err = [self errorWithMessage:
                          [NSString stringWithFormat:@"zip failed (rc=%d). %@",
                           rc, errStr.length ? errStr : @""]];
        return NO;
    }
    return YES;
}

+ (NSString *)shellQuote:(NSString *)s {
    return [NSString stringWithFormat:@"'%@'",
            [s stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
}

#pragma mark - Payload inspection

+ (NSString *)infoPlistInsideWorkDir:(NSString *)workDir {
    NSString *payload = [workDir stringByAppendingPathComponent:@"Payload"];
    NSArray *entries = [[NSFileManager defaultManager]
                         contentsOfDirectoryAtPath:payload error:nil];
    for (NSString *name in entries) {
        if (![name hasSuffix:@".app"]) continue;
        NSString *plist = [NSString stringWithFormat:@"%@/%@/Info.plist",
                           payload, name];
        if ([[NSFileManager defaultManager] fileExistsAtPath:plist]) {
            return plist;
        }
    }
    return nil;
}

#pragma mark - Mach-O patch

// Pack "MM.mm.pp" into the 32-bit encoding used by both LC_VERSION_MIN_* and
// LC_BUILD_VERSION: xxxxxx yy zz → (MM << 16) | (mm << 8) | pp.
+ (uint32_t)packVersion:(NSString *)v {
    NSArray *parts = [v componentsSeparatedByString:@"."];
    uint32_t M = parts.count > 0 ? [parts[0] intValue] : 0;
    uint32_t m = parts.count > 1 ? [parts[1] intValue] : 0;
    uint32_t p = parts.count > 2 ? [parts[2] intValue] : 0;
    return (M << 16) | (m << 8) | p;
}

+ (void)patchMachOExecutableAtPath:(NSString *)path toVersion:(NSString *)ver {
    NSMutableData *data = [NSMutableData dataWithContentsOfFile:path];
    if (!data.length) return;
    uint32_t packed = [self packVersion:ver];

    const uint8_t *bytes = data.bytes;
    uint32_t magic = *(const uint32_t *)bytes;

    // Multi-arch: walk each slice at its offset.
    if (magic == FAT_MAGIC || magic == FAT_CIGAM ||
        magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64) {
        BOOL swap = (magic == FAT_CIGAM || magic == FAT_CIGAM_64);
        const struct fat_header *fh = (const struct fat_header *)bytes;
        uint32_t nfat = swap ? CFSwapInt32(fh->nfat_arch) : fh->nfat_arch;
        const struct fat_arch *arch = (const struct fat_arch *)(bytes + sizeof(*fh));
        for (uint32_t i = 0; i < nfat; i++) {
            uint32_t off = swap ? CFSwapInt32(arch[i].offset) : arch[i].offset;
            [self patchSliceAtOffset:off inData:data toPackedVersion:packed];
        }
    } else {
        [self patchSliceAtOffset:0 inData:data toPackedVersion:packed];
    }

    [data writeToFile:path atomically:YES];
}

+ (void)patchSliceAtOffset:(uint32_t)offset
                    inData:(NSMutableData *)data
           toPackedVersion:(uint32_t)packed {
    uint8_t *base = data.mutableBytes + offset;
    uint32_t magic = *(uint32_t *)base;
    BOOL is64 = (magic == MH_MAGIC_64 || magic == MH_CIGAM_64);
    uint32_t ncmds = 0;
    uint32_t cmdsOff = 0;
    if (is64) {
        struct mach_header_64 *mh = (struct mach_header_64 *)base;
        ncmds = mh->ncmds;
        cmdsOff = sizeof(struct mach_header_64);
    } else if (magic == MH_MAGIC || magic == MH_CIGAM) {
        struct mach_header *mh = (struct mach_header *)base;
        ncmds = mh->ncmds;
        cmdsOff = sizeof(struct mach_header);
    } else {
        return; // not a Mach-O at this offset
    }

    uint8_t *cmd = base + cmdsOff;
    for (uint32_t i = 0; i < ncmds; i++) {
        struct load_command *lc = (struct load_command *)cmd;
        if (lc->cmd == LC_VERSION_MIN_IPHONEOS) {
            // struct version_min_command: cmd, cmdsize, version, sdk
            // Patch version only; leave sdk alone to avoid breaking other
            // runtime checks.
            uint32_t *verSlot = (uint32_t *)(cmd + 8);  // skip cmd + cmdsize
            *verSlot = packed;
        } else if (lc->cmd == LC_BUILD_VERSION) {
            // struct build_version_command: cmd, cmdsize, platform, minos,
            //                                sdk, ntools.
            uint32_t *minosSlot = (uint32_t *)(cmd + 12);  // cmd + cmdsize + platform
            *minosSlot = packed;
        }
        cmd += lc->cmdsize;
    }
}

#pragma mark - Error helper

+ (NSError *)errorWithMessage:(NSString *)msg {
    return [NSError errorWithDomain:@"ARIPAPatcher" code:1
                            userInfo:@{NSLocalizedDescriptionKey: msg ?: @"error"}];
}

@end
