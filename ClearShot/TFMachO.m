#import "TFMachO.h"
#import <mach-o/loader.h>
#import <mach-o/fat.h>
#import <mach-o/swap.h>

// ============================================================================
// Error helper
// ============================================================================
static NSError *TFErr(NSString *msg) {
    return [NSError errorWithDomain:@"TFMachO" code:1
                            userInfo:@{NSLocalizedDescriptionKey: msg ?: @"error"}];
}

@implementation TFMachO

// ============================================================================
// Byte-swap-aware Mach-O walker.
// ============================================================================

// Returns whether the magic at `base` indicates host-endian or swapped.
static BOOL tfIsSwapped(uint32_t magic) {
    return magic == MH_CIGAM || magic == MH_CIGAM_64;
}

static uint32_t tfU32(uint32_t v, BOOL swap) { return swap ? OSSwapInt32(v) : v; }

// Returns an array of (sliceOffset, sliceSize) for a buffer. For a thin
// binary this is a single entry at offset 0.
static NSArray<NSDictionary *> *tfSlicesIn(NSData *data) {
    if (data.length < sizeof(uint32_t)) return @[];
    const uint8_t *bytes = data.bytes;
    uint32_t magic = *(const uint32_t *)bytes;

    if (magic == FAT_MAGIC || magic == FAT_CIGAM) {
        BOOL swap = (magic == FAT_CIGAM);
        const struct fat_header *fh = (const struct fat_header *)bytes;
        uint32_t nfat = tfU32(fh->nfat_arch, swap);
        const struct fat_arch *archs = (const struct fat_arch *)(bytes + sizeof(*fh));
        NSMutableArray *out = [NSMutableArray array];
        for (uint32_t i = 0; i < nfat; i++) {
            [out addObject:@{
                @"offset": @(tfU32(archs[i].offset, swap)),
                @"size":   @(tfU32(archs[i].size,   swap)),
            }];
        }
        return out;
    }
    if (magic == FAT_MAGIC_64 || magic == FAT_CIGAM_64) {
        BOOL swap = (magic == FAT_CIGAM_64);
        const struct fat_header *fh = (const struct fat_header *)bytes;
        uint32_t nfat = tfU32(fh->nfat_arch, swap);
        const struct fat_arch_64 *archs =
            (const struct fat_arch_64 *)(bytes + sizeof(*fh));
        NSMutableArray *out = [NSMutableArray array];
        for (uint32_t i = 0; i < nfat; i++) {
            uint64_t off = swap ? OSSwapInt64(archs[i].offset) : archs[i].offset;
            uint64_t sz  = swap ? OSSwapInt64(archs[i].size)   : archs[i].size;
            [out addObject:@{ @"offset": @(off), @"size": @(sz) }];
        }
        return out;
    }
    // Thin binary.
    return @[ @{ @"offset": @(0), @"size": @(data.length) } ];
}

// ============================================================================
// Per-slice patchers
// ============================================================================

// Returns the (ncmds, sizeofcmds, cmdsOffset) tuple for the slice.
static BOOL tfReadMachHeader(const uint8_t *slice,
                              uint32_t *outNcmds,
                              uint32_t *outSizeOfCmds,
                              uint32_t *outCmdsOffset,
                              BOOL *outIs64) {
    uint32_t magic = *(const uint32_t *)slice;
    if (magic == MH_MAGIC_64 || magic == MH_CIGAM_64) {
        const struct mach_header_64 *mh = (const struct mach_header_64 *)slice;
        BOOL swap = tfIsSwapped(magic);
        *outNcmds       = tfU32(mh->ncmds, swap);
        *outSizeOfCmds  = tfU32(mh->sizeofcmds, swap);
        *outCmdsOffset  = sizeof(struct mach_header_64);
        *outIs64        = YES;
        return YES;
    }
    if (magic == MH_MAGIC || magic == MH_CIGAM) {
        const struct mach_header *mh = (const struct mach_header *)slice;
        BOOL swap = tfIsSwapped(magic);
        *outNcmds       = tfU32(mh->ncmds, swap);
        *outSizeOfCmds  = tfU32(mh->sizeofcmds, swap);
        *outCmdsOffset  = sizeof(struct mach_header);
        *outIs64        = NO;
        return YES;
    }
    return NO;
}

// Return the file offset where the FIRST segment's file content begins.
// New load commands must stay BELOW this value, otherwise they'd overwrite
// code or data.
static uint64_t tfFirstSegmentFileOffset(const uint8_t *slice,
                                          uint32_t cmdsOffset,
                                          uint32_t ncmds,
                                          BOOL is64) {
    uint64_t low = UINT64_MAX;
    uint32_t magic = *(const uint32_t *)slice;
    BOOL swap = tfIsSwapped(magic);
    const uint8_t *cmd = slice + cmdsOffset;
    for (uint32_t i = 0; i < ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)cmd;
        uint32_t cmdType = tfU32(lc->cmd, swap);
        uint32_t cmdSize = tfU32(lc->cmdsize, swap);
        if (cmdType == LC_SEGMENT_64) {
            const struct segment_command_64 *sc =
                (const struct segment_command_64 *)cmd;
            uint64_t off = swap ? OSSwapInt64(sc->fileoff) : sc->fileoff;
            uint64_t fs  = swap ? OSSwapInt64(sc->filesize) : sc->filesize;
            if (fs > 0 && off > 0 && off < low) low = off;
        } else if (cmdType == LC_SEGMENT) {
            const struct segment_command *sc =
                (const struct segment_command *)cmd;
            uint32_t off = tfU32(sc->fileoff, swap);
            uint32_t fs  = tfU32(sc->filesize, swap);
            if (fs > 0 && off > 0 && off < low) low = off;
        }
        cmd += cmdSize;
    }
    return low;
}

// Round to the next multiple of n (power-of-two-safe for n in {4, 8}).
static uint32_t tfAlignUp(uint32_t v, uint32_t n) {
    return (v + (n - 1)) & ~(n - 1);
}

// Build a fresh LC_LOAD_DYLIB payload in a buffer. Returns the command's
// total size (== cmdsize). If `buf` is NULL we only compute the size.
static uint32_t tfBuildLoadDylib(uint8_t *buf, const char *name) {
    uint32_t nameLen  = (uint32_t)strlen(name) + 1;   // include NUL
    uint32_t cmdSize  = tfAlignUp((uint32_t)sizeof(struct dylib_command) + nameLen, 8);
    if (buf) {
        memset(buf, 0, cmdSize);
        struct dylib_command *dc = (struct dylib_command *)buf;
        dc->cmd                    = LC_LOAD_DYLIB;
        dc->cmdsize                = cmdSize;
        dc->dylib.name.offset      = sizeof(struct dylib_command);
        dc->dylib.timestamp        = 2;
        dc->dylib.current_version      = 0x00010000;
        dc->dylib.compatibility_version = 0x00010000;
        memcpy(buf + sizeof(struct dylib_command), name, nameLen);
    }
    return cmdSize;
}

// Patch one slice in-place. The slice's bytes are at `data.bytes + sliceOff`.
// Returns NO + sets `err` if we can't fit the new command.
+ (BOOL)patchSliceInData:(NSMutableData *)data
                  offset:(uint64_t)sliceOff
                dylibStr:(const char *)dylibC
                   error:(NSError **)err {
    uint8_t *slice = (uint8_t *)data.mutableBytes + sliceOff;
    uint32_t magic = *(uint32_t *)slice;
    BOOL swap = tfIsSwapped(magic);

    uint32_t ncmds = 0, sizeOfCmds = 0, cmdsOffset = 0;
    BOOL is64 = NO;
    if (!tfReadMachHeader(slice, &ncmds, &sizeOfCmds, &cmdsOffset, &is64)) {
        if (err) *err = TFErr(@"Not a Mach-O slice.");
        return NO;
    }

    uint32_t newCmdSize = tfBuildLoadDylib(NULL, dylibC);
    uint64_t firstSeg   = tfFirstSegmentFileOffset(slice, cmdsOffset, ncmds, is64);
    uint64_t headerEnd  = cmdsOffset + sizeOfCmds;
    uint64_t freeSpace  = firstSeg > headerEnd ? firstSeg - headerEnd : 0;
    if (freeSpace < newCmdSize) {
        if (err) *err = TFErr([NSString stringWithFormat:
            @"Not enough header padding (%llu < %u). Use a shorter dylib path "
            @"or a stub that re-dlopen()s your real dylib.",
            freeSpace, newCmdSize]);
        return NO;
    }

    // Write the new command just after the existing ones, update ncmds and
    // sizeofcmds in the Mach header. LC_CODE_SIGNATURE's load command stays
    // at its spot in the command list; its payload (at __LINKEDIT offset) is
    // untouched. The signature will be regenerated by TFCodesign afterwards.
    uint8_t *writePtr = slice + headerEnd;
    tfBuildLoadDylib(writePtr, dylibC);

    if (is64) {
        struct mach_header_64 *mh = (struct mach_header_64 *)slice;
        uint32_t n = tfU32(mh->ncmds, swap);
        uint32_t s = tfU32(mh->sizeofcmds, swap);
        mh->ncmds      = tfU32(n + 1, swap);
        mh->sizeofcmds = tfU32(s + newCmdSize, swap);
    } else {
        struct mach_header *mh = (struct mach_header *)slice;
        uint32_t n = tfU32(mh->ncmds, swap);
        uint32_t s = tfU32(mh->sizeofcmds, swap);
        mh->ncmds      = tfU32(n + 1, swap);
        mh->sizeofcmds = tfU32(s + newCmdSize, swap);
    }
    return YES;
}

+ (NSUInteger)removeFromSliceInData:(NSMutableData *)data
                              offset:(uint64_t)sliceOff
                            dylibStr:(const char *)dylibC {
    uint8_t *slice = (uint8_t *)data.mutableBytes + sliceOff;
    uint32_t magic = *(uint32_t *)slice;
    BOOL swap = tfIsSwapped(magic);
    uint32_t ncmds = 0, sizeOfCmds = 0, cmdsOffset = 0;
    BOOL is64 = NO;
    if (!tfReadMachHeader(slice, &ncmds, &sizeOfCmds, &cmdsOffset, &is64)) return 0;

    uint8_t *cmdStart = slice + cmdsOffset;
    uint8_t *cmd = cmdStart;
    uint8_t *cmdEnd = cmdStart + sizeOfCmds;
    NSUInteger removed = 0;
    uint32_t newTotalSize = sizeOfCmds;

    while (cmd < cmdEnd) {
        struct load_command *lc = (struct load_command *)cmd;
        uint32_t cmdType = tfU32(lc->cmd, swap);
        uint32_t cmdSize = tfU32(lc->cmdsize, swap);
        if (cmdSize == 0) break;
        if (cmdType == LC_LOAD_DYLIB || cmdType == LC_LOAD_WEAK_DYLIB) {
            struct dylib_command *dc = (struct dylib_command *)cmd;
            uint32_t nameOff = tfU32(dc->dylib.name.offset, swap);
            const char *name = (const char *)cmd + nameOff;
            if (strcmp(name, dylibC) == 0) {
                // Slide subsequent commands up to overwrite this one.
                size_t bytesAfter = cmdEnd - (cmd + cmdSize);
                memmove(cmd, cmd + cmdSize, bytesAfter);
                memset(cmdEnd - cmdSize, 0, cmdSize);
                cmdEnd -= cmdSize;
                newTotalSize -= cmdSize;
                removed++;
                // Do not advance cmd — the next command is now at `cmd`.
                continue;
            }
        }
        cmd += cmdSize;
    }

    if (removed > 0) {
        if (is64) {
            struct mach_header_64 *mh = (struct mach_header_64 *)slice;
            uint32_t n = tfU32(mh->ncmds, swap);
            mh->ncmds      = tfU32(n - (uint32_t)removed, swap);
            mh->sizeofcmds = tfU32(newTotalSize, swap);
        } else {
            struct mach_header *mh = (struct mach_header *)slice;
            uint32_t n = tfU32(mh->ncmds, swap);
            mh->ncmds      = tfU32(n - (uint32_t)removed, swap);
            mh->sizeofcmds = tfU32(newTotalSize, swap);
        }
    }
    return removed;
}

+ (NSArray<NSString *> *)listInSliceInData:(NSData *)data
                                      offset:(uint64_t)sliceOff {
    const uint8_t *slice = (const uint8_t *)data.bytes + sliceOff;
    uint32_t magic = *(const uint32_t *)slice;
    BOOL swap = tfIsSwapped(magic);
    uint32_t ncmds = 0, sizeOfCmds = 0, cmdsOffset = 0;
    BOOL is64 = NO;
    if (!tfReadMachHeader(slice, &ncmds, &sizeOfCmds, &cmdsOffset, &is64)) {
        return @[];
    }

    NSMutableArray *out = [NSMutableArray array];
    const uint8_t *cmd = slice + cmdsOffset;
    for (uint32_t i = 0; i < ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)cmd;
        uint32_t cmdType = tfU32(lc->cmd, swap);
        uint32_t cmdSize = tfU32(lc->cmdsize, swap);
        if (cmdSize == 0) break;
        if (cmdType == LC_LOAD_DYLIB || cmdType == LC_LOAD_WEAK_DYLIB) {
            const struct dylib_command *dc = (const struct dylib_command *)cmd;
            uint32_t nameOff = tfU32(dc->dylib.name.offset, swap);
            const char *name = (const char *)cmd + nameOff;
            [out addObject:[NSString stringWithUTF8String:name]];
        }
        cmd += cmdSize;
    }
    return out;
}

// ============================================================================
// Public API — orchestrate across slices
// ============================================================================

+ (BOOL)addDylibReference:(NSString *)dylibPath
             toMachOAtPath:(NSString *)machOPath
                     error:(NSError **)err {
    NSMutableData *data = [NSMutableData dataWithContentsOfFile:machOPath];
    if (!data) {
        if (err) *err = TFErr([NSString stringWithFormat:@"Unreadable: %@", machOPath]);
        return NO;
    }
    NSArray *slices = tfSlicesIn(data);
    const char *dylibC = [dylibPath UTF8String];
    for (NSDictionary *s in slices) {
        uint64_t off = [s[@"offset"] unsignedLongLongValue];
        if (![self patchSliceInData:data offset:off dylibStr:dylibC error:err]) {
            return NO;
        }
    }
    if (![data writeToFile:machOPath atomically:YES]) {
        if (err) *err = TFErr(@"Couldn't write patched Mach-O back.");
        return NO;
    }
    return YES;
}

+ (NSUInteger)removeDylibReference:(NSString *)dylibPath
                     fromMachOAtPath:(NSString *)machOPath
                               error:(NSError **)err {
    NSMutableData *data = [NSMutableData dataWithContentsOfFile:machOPath];
    if (!data) {
        if (err) *err = TFErr([NSString stringWithFormat:@"Unreadable: %@", machOPath]);
        return 0;
    }
    NSArray *slices = tfSlicesIn(data);
    const char *dylibC = [dylibPath UTF8String];
    NSUInteger total = 0;
    for (NSDictionary *s in slices) {
        uint64_t off = [s[@"offset"] unsignedLongLongValue];
        total += [self removeFromSliceInData:data offset:off dylibStr:dylibC];
    }
    if (total > 0) {
        if (![data writeToFile:machOPath atomically:YES]) {
            if (err) *err = TFErr(@"Couldn't write stripped Mach-O back.");
            return 0;
        }
    }
    return total;
}

+ (NSArray<NSString *> *)dylibReferencesInMachOAtPath:(NSString *)machOPath
                                                  error:(NSError **)err {
    NSData *data = [NSData dataWithContentsOfFile:machOPath];
    if (!data) {
        if (err) *err = TFErr([NSString stringWithFormat:@"Unreadable: %@", machOPath]);
        return @[];
    }
    NSArray *slices = tfSlicesIn(data);
    NSMutableSet *seen = [NSMutableSet set];
    for (NSDictionary *s in slices) {
        uint64_t off = [s[@"offset"] unsignedLongLongValue];
        [seen addObjectsFromArray:[self listInSliceInData:data offset:off]];
    }
    return [seen allObjects];
}

@end
