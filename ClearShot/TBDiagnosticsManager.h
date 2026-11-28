// ============================================================================
// TBDiagnosticsManager — global diagnostic aggregator.
//
// Replaces the per-section diagnostic buttons that used to live inside each
// VC (ClearShot had one, nobody else did) with a single report accessible
// from About Device → Diagnostics. Every section optionally exports a
// `+ diagnosticInfo` class method (TBDiagnosticProvider protocol) that
// TBDiagnosticsManager stitches into one textual report, bracketed by:
//
//   - Process identity (uid/euid/pid, iOS version, device, bundle path)
//   - Writability checks for every root-owned path TrollBox writes to
//   - A dated footer
//
// The report is intended to be copy-pasted or screenshotted back to the dev
// when something misbehaves. It is NEVER uploaded automatically.
// ============================================================================

#import <Foundation/Foundation.h>

@protocol TBDiagnosticProvider <NSObject>
+ (NSString *)diagnosticInfo;   // short, 1-10 lines, section-header style
@end

@interface TBDiagnosticsManager : NSObject

// Build a complete textual report. Safe to call off the main thread but
// does hit disk for writability probes — keep off the touch-up path.
+ (NSString *)fullReport;

// A list of section classes that conform to TBDiagnosticProvider. New
// sections just add themselves to the array literal in the .m file.
+ (NSArray<Class> *)diagnosticProviders;

@end
