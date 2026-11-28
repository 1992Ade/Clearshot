// ============================================================================
// TFMachO — Mach-O load-command patching for the Tweaks section.
//
// Ported minimally from Lessica's TrollFools InjectorEngine.swift. This
// module only cares about one operation: add (or remove) an LC_LOAD_DYLIB
// command pointing to a sidecar dylib so dyld loads it alongside the main
// binary when the target app launches.
//
// The implementation is pure C/Objective-C. No dependency on insert_dylib /
// optool / lipo — we walk the Mach-O header ourselves. Fat binaries are
// supported: each slice is patched in place.
//
// What we handle:
//   • 32-bit & 64-bit Mach-O (MH_MAGIC / MH_MAGIC_64, with and without
//     byte-swap in a fat_arch, both host and swapped forms)
//   • Fat binaries (FAT_MAGIC / FAT_CIGAM / FAT_MAGIC_64 / FAT_CIGAM_64)
//   • Preserving existing load commands' order and padding
//   • LC_CODE_SIGNATURE at the end of the load-command region, which must
//     stay the last command AND stay at its file offset — we insert new
//     commands BEFORE it and bump its offset / cmdsize accordingly
//   • Enough free space in the __PAGEZERO region or between load commands
//     and the first segment's file contents for the new command's bytes.
//     Most binaries have 100+ bytes of padding here; we refuse politely if
//     they don't and advise the user to use a smaller dylib name.
// ============================================================================

#import <Foundation/Foundation.h>

@interface TFMachO : NSObject

// Add LC_LOAD_DYLIB pointing to `dylibPath` to every slice of the Mach-O at
// `machOPath`. `dylibPath` is the string that will be embedded verbatim —
// typically `@executable_path/Frameworks/libTweak.dylib` or
// `@rpath/libTweak.dylib`.
+ (BOOL)addDylibReference:(NSString *)dylibPath
             toMachOAtPath:(NSString *)machOPath
                     error:(NSError **)err;

// Remove LC_LOAD_DYLIB / LC_LOAD_WEAK_DYLIB commands whose path matches
// `dylibPath`. Returns the number of commands actually removed.
+ (NSUInteger)removeDylibReference:(NSString *)dylibPath
                     fromMachOAtPath:(NSString *)machOPath
                               error:(NSError **)err;

// List every LC_LOAD_DYLIB / LC_LOAD_WEAK_DYLIB path currently referenced
// by the binary. Useful for the "already injected" display in the Tweaks UI.
+ (NSArray<NSString *> *)dylibReferencesInMachOAtPath:(NSString *)machOPath
                                                  error:(NSError **)err;

@end
