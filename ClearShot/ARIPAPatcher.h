// ============================================================================
// ARIPAPatcher — patch an IPA's MinimumOSVersion so it can be installed on
// an older iOS than the one it was built for.
//
// The patcher touches two spots:
//   1. Payload/<App>.app/Info.plist → MinimumOSVersion key
//   2. Payload/<App>.app/<Executable> → Mach-O LC_BUILD_VERSION or
//      LC_VERSION_MIN_IPHONEOS minos field
//
// Neither spot is inside the FairPlay-encrypted region (that's the __TEXT
// __text section, not touched here), so decryption is NOT required. The
// re-signed binary stays encrypted — iOS still decrypts at launch using
// the Apple ID key that fetched the .ipa.
//
// Returns the path to the patched .ipa on success, nil on failure. The
// patched file lives in NSTemporaryDirectory() so the caller can share-
// sheet it to TrollStore.
// ============================================================================

#import <Foundation/Foundation.h>

@interface ARIPAPatcher : NSObject

+ (NSString *)patchedIPAFromIPAAtPath:(NSString *)sourceIPA
                 newMinimumOSVersion:(NSString *)newVersion
                               error:(NSError **)err;

// Reads the embedded MinimumOSVersion from an IPA without patching. Useful
// for the "verdict" card in the version picker.
+ (NSString *)minimumOSVersionOfIPAAtPath:(NSString *)sourceIPA
                                     error:(NSError **)err;

@end
