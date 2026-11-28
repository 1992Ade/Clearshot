#import "CSRecordModule.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <Photos/Photos.h>
#import <QuartzCore/QuartzCore.h>
#import <IOSurface/IOSurfaceRef.h>
#import <mach/mach.h>
#import <dlfcn.h>

// ============================================================================
// ClearShot Record — the video twin of the Capture CC module.
//
// Runs inside SpringBoard. Tapping the tile STARTS recording the actual
// composited framebuffer at NSUserDefaults-configured FPS (default 30) via
// a CADisplayLink-driven CARenderServerRenderDisplay loop. Each frame goes
// through an IOSurface → CVPixelBuffer zero-copy, into an AVAssetWriter
// H.264 encoder. Tapping again stops, closes the writer and saves to
// Photos.
//
// Because we're in SpringBoard, we bypass FLAG_SECURE for the entire
// session, so whatever is on-screen (banking, auth, secure messaging) ends
// up in the video.
// ============================================================================

// ----------------------------------------------------------------------------
// CARenderServerRenderDisplay — resolved at runtime via QuartzCore dlsym.
// ----------------------------------------------------------------------------
typedef kern_return_t (*RenderDisplayFn)(mach_port_t, CFStringRef,
                                         IOSurfaceRef, int32_t, int32_t);

static RenderDisplayFn csr_resolve_render(void) {
    static RenderDisplayFn fn = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *qc = dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore",
                          RTLD_LAZY);
        if (qc) fn = (RenderDisplayFn)dlsym(qc, "CARenderServerRenderDisplay");
    });
    return fn;
}
static CFStringRef csr_display_id(void) {
    static CFStringRef did = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *qc = dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore",
                          RTLD_LAZY);
        if (qc) {
            CFStringRef *p = dlsym(qc, "kCARenderServerDisplayIDMain");
            if (p) did = *p;
        }
        if (!did) did = CFSTR("LCD");
    });
    return did;
}

// ----------------------------------------------------------------------------
// Settings keys shared with the main app's Record settings screen.
// ----------------------------------------------------------------------------
static NSString * const kFPSKey        = @"TBCSRecordFPS";          // int, default 30
static NSString * const kResModeKey    = @"TBCSRecordResMode";      // @"native" / @"720" / @"480"
static NSString * const kAudioSysKey   = @"TBCSRecordAudioSystem";  // BOOL
static NSString * const kAudioMicKey   = @"TBCSRecordAudioMic";     // BOOL
static NSString * const kFormatKey     = @"TBCSRecordFormat";       // @"h264" / @"hevc"

@interface CCUIToggleModule (Private)
- (void)setLatching:(BOOL)latching;
@end

// ----------------------------------------------------------------------------

@interface CSRecordModule ()
@property (nonatomic, assign) BOOL recording;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, strong) AVAssetWriter *writer;
@property (nonatomic, strong) AVAssetWriterInput *videoInput;
@property (nonatomic, strong) AVAssetWriterInputPixelBufferAdaptor *adaptor;
@property (nonatomic, assign) CMTime nextPresentationTime;
@property (nonatomic, strong) NSString *outputPath;
@property (nonatomic, assign) CGSize outputSize;
@property (nonatomic, assign) int fps;
@end

@implementation CSRecordModule

- (instancetype)init {
    if ((self = [super init])) {
        if ([self respondsToSelector:@selector(setLatching:)]) {
            // Unlike Capture, Record IS latching — the tile stays lit while
            // we're actively recording, so the user has a visual cue.
            [self setLatching:YES];
        }
    }
    return self;
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    if (selected && !self.recording) {
        [self startRecording];
    } else if (!selected && self.recording) {
        [self stopRecordingAndSave];
    }
}

#pragma mark - Settings

- (void)loadSettings {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    int fps = (int)[d integerForKey:kFPSKey];
    self.fps = (fps >= 5 && fps <= 60) ? fps : 30;

    NSString *resMode = [d stringForKey:kResModeKey] ?: @"native";
    CGSize native;
    UIScreen *s = [UIScreen mainScreen];
    CGRect nb = [s respondsToSelector:@selector(nativeBounds)] ? s.nativeBounds : s.bounds;
    native = CGSizeMake(nb.size.width, nb.size.height);

    if ([resMode isEqualToString:@"720"]) {
        double scale = 720.0 / MIN(native.width, native.height);
        self.outputSize = CGSizeMake(round(native.width * scale),
                                     round(native.height * scale));
    } else if ([resMode isEqualToString:@"480"]) {
        double scale = 480.0 / MIN(native.width, native.height);
        self.outputSize = CGSizeMake(round(native.width * scale),
                                     round(native.height * scale));
    } else {
        self.outputSize = native;
    }
}

#pragma mark - Start

- (void)startRecording {
    [self loadSettings];

    NSString *tmp = NSTemporaryDirectory();
    NSString *filename = [NSString stringWithFormat:@"clearshot-%.0f.mp4",
                           [NSDate date].timeIntervalSince1970];
    self.outputPath = [tmp stringByAppendingPathComponent:filename];
    NSURL *outURL = [NSURL fileURLWithPath:self.outputPath];

    NSError *err = nil;
    self.writer = [[AVAssetWriter alloc] initWithURL:outURL
                                             fileType:AVFileTypeMPEG4
                                                error:&err];
    if (!self.writer) {
        NSLog(@"[ClearShot/Rec] writer init err=%@", err);
        [self cancelRecording];
        return;
    }

    NSString *fmt = [[NSUserDefaults standardUserDefaults] stringForKey:kFormatKey] ?: @"h264";
    NSString *codec = [fmt isEqualToString:@"hevc"] ? AVVideoCodecTypeHEVC
                                                    : AVVideoCodecTypeH264;
    NSDictionary *vSettings = @{
        AVVideoCodecKey: codec,
        AVVideoWidthKey:  @(self.outputSize.width),
        AVVideoHeightKey: @(self.outputSize.height),
    };
    self.videoInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo
                                                       outputSettings:vSettings];
    self.videoInput.expectsMediaDataInRealTime = YES;

    NSDictionary *pbAttrs = @{
        (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (__bridge NSString *)kCVPixelBufferWidthKey:  @(self.outputSize.width),
        (__bridge NSString *)kCVPixelBufferHeightKey: @(self.outputSize.height),
        (__bridge NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
    };
    self.adaptor = [[AVAssetWriterInputPixelBufferAdaptor alloc]
                      initWithAssetWriterInput:self.videoInput
                      sourcePixelBufferAttributes:pbAttrs];

    if ([self.writer canAddInput:self.videoInput]) {
        [self.writer addInput:self.videoInput];
    }
    [self.writer startWriting];
    [self.writer startSessionAtSourceTime:kCMTimeZero];

    self.nextPresentationTime = kCMTimeZero;
    self.recording = YES;

    self.displayLink = [CADisplayLink displayLinkWithTarget:self
                                                     selector:@selector(onDisplayLink:)];
    if (@available(iOS 15.0, *)) {
        self.displayLink.preferredFrameRateRange =
            CAFrameRateRangeMake(self.fps, self.fps, self.fps);
    } else {
        self.displayLink.preferredFramesPerSecond = self.fps;
    }
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop]
                            forMode:NSRunLoopCommonModes];

    NSLog(@"[ClearShot/Rec] started → %@ (%.0fx%.0f @ %dfps %@)",
          self.outputPath, self.outputSize.width, self.outputSize.height,
          self.fps, codec);
}

#pragma mark - Frame grab

- (void)onDisplayLink:(CADisplayLink *)link {
    if (!self.recording) return;
    RenderDisplayFn render = csr_resolve_render();
    if (!render) return;
    if (!self.videoInput.readyForMoreMediaData) return;

    // Build a fresh IOSurface at the output resolution. We rely on the
    // pixel-buffer adaptor's pool for recycling rather than bare IOSurface
    // allocation — simpler and still zero-copy once primed.
    CVPixelBufferRef pb = NULL;
    CVReturn cr = CVPixelBufferPoolCreatePixelBuffer(NULL,
                                                      self.adaptor.pixelBufferPool,
                                                      &pb);
    if (cr != kCVReturnSuccess || !pb) return;

    IOSurfaceRef surface = CVPixelBufferGetIOSurface(pb);
    if (!surface) { CVPixelBufferRelease(pb); return; }

    kern_return_t kr = render(MACH_PORT_NULL, csr_display_id(), surface, 0, 0);
    if (kr != KERN_SUCCESS) { CVPixelBufferRelease(pb); return; }

    [self.adaptor appendPixelBuffer:pb withPresentationTime:self.nextPresentationTime];
    CVPixelBufferRelease(pb);

    self.nextPresentationTime =
        CMTimeAdd(self.nextPresentationTime, CMTimeMake(1, self.fps));
}

#pragma mark - Stop / save

- (void)stopRecordingAndSave {
    if (!self.recording) return;
    self.recording = NO;
    [self.displayLink invalidate];
    self.displayLink = nil;

    [self.videoInput markAsFinished];
    __weak typeof(self) weakSelf = self;
    [self.writer finishWritingWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf saveToPhotos];
        });
    }];
}

- (void)cancelRecording {
    self.recording = NO;
    [self.displayLink invalidate];
    self.displayLink = nil;
    self.writer = nil;
    self.videoInput = nil;
    self.adaptor = nil;
    [self flashIcon:[UIColor systemRedColor]];
}

- (void)saveToPhotos {
    NSString *path = self.outputPath;
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly
                                                handler:^(PHAuthorizationStatus st) {
        if (st != PHAuthorizationStatusAuthorized &&
            st != PHAuthorizationStatusLimited) {
            NSLog(@"[ClearShot/Rec] Photos denied (status=%ld)", (long)st);
            [self flashIcon:[UIColor systemOrangeColor]];
            return;
        }
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:
             [NSURL fileURLWithPath:path]];
        } completionHandler:^(BOOL success, NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self flashIcon:success ? [UIColor systemGreenColor]
                                        : [UIColor systemRedColor]];
            });
            NSLog(@"[ClearShot/Rec] saved success=%d err=%@", success, err);
        }];
    }];
}

#pragma mark - Visual feedback

- (void)flashIcon:(UIColor *)color {
    UIView *v = self.view;
    if (!v) return;
    UIColor *orig = v.backgroundColor;
    [UIView animateWithDuration:0.12 animations:^{
        v.backgroundColor = color;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.3 delay:0.15 options:0 animations:^{
            v.backgroundColor = orig;
        } completion:nil];
    }];
}

@end
