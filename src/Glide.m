#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/hid/IOHIDManager.h>
#import "GlidePreferencesController.h"
#import "GlideSettings.h"
#import "GlideLoginItems.h"
#import <math.h>
#import <string.h>
#import <stdio.h>
#import <sys/stat.h>

static const int64_t kGlideEventTag = 0x474c494445LL;
enum { kScrollSampleCapacity = 64 };
static BOOL GlideUsesModernActivationPolicy(void) {
    SInt32 systemVersion = 0;
    return Gestalt(gestaltSystemVersion, &systemVersion) == noErr && systemVersion >= 0x1090;
}

static BOOL GlideSetDockIconVisible(BOOL visible) {
    if (GlideUsesModernActivationPolicy()) {
        return [NSApp setActivationPolicy:visible
            ? NSApplicationActivationPolicyRegular : NSApplicationActivationPolicyAccessory];
    }

    ProcessSerialNumber process = { 0, kCurrentProcess };
    ProcessApplicationTransformState transform = visible
        ? kProcessTransformToForegroundApplication
        : kProcessTransformToUIElementApplication;
    return TransformProcessType(&process, transform) == noErr;
}

typedef struct {
    double startTime;
    double endTime;
    double deltaX;
    double deltaY;
} GlideScrollSample;

@interface GlideController : NSObject <NSApplicationDelegate, GlidePreferencesControllerDelegate> {
    CFMachPortRef _tap;
    CFRunLoopSourceRef _tapSource;
    IOHIDManagerRef _hidManager;
    FILE *_hidLog;
    CGEventSourceRef _eventSource;
    NSTimer *_timer;
    GlidePreferencesController *_preferencesController;
    BOOL _enabled;
    BOOL _coasting;
    BOOL _backgroundLaunch;
    BOOL _eventTapAvailable;
    BOOL _trackpadMonitorAvailable;
    double _lastInputTime;
    double _lastEventTime;
    double _velocityX;
    double _velocityY;
    double _coastFriction;
    double _coastStartedTime;
    double _fractionX;
    double _fractionY;
    double _lastTickTime;
    GlideScrollSample _scrollSamples[kScrollSampleCapacity];
    NSUInteger _scrollSampleCount;
}
- (id)initWithBackgroundLaunch:(BOOL)backgroundLaunch logHID:(BOOL)logHID;
- (void)handleScrollEvent:(CGEventRef)event;
- (void)eventTapWasDisabled;
- (void)trackpadActivity;
- (void)tick:(NSTimer *)timer;
- (void)animateCoast;
- (double)settingValueForIndex:(NSUInteger)index;
- (void)refreshTimerInterval;
- (void)updateStatus;
- (NSString *)legacyLaunchAgentPath;
- (BOOL)legacyLaunchAgentIsInstalled;
- (BOOL)loginItemIsEnabled;
- (void)setStartAtLogin:(BOOL)enabled;
- (void)recordHIDValue:(IOHIDValueRef)value;
- (void)recordHIDReportType:(IOHIDReportType)type reportID:(uint32_t)reportID
                      bytes:(const uint8_t *)bytes length:(CFIndex)length;
@end

static CGEventRef GlideTapCallback(CGEventTapProxy proxy, CGEventType type,
                                   CGEventRef event, void *refcon) {
    (void)proxy;
    GlideController *controller = (GlideController *)refcon;
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        [controller eventTapWasDisabled];
        return event;
    }
    if (type == kCGEventScrollWheel &&
        CGEventGetIntegerValueField(event, kCGEventSourceUserData) != kGlideEventTag) {
        [controller handleScrollEvent:event];
    }
    return event;
}

static void GlideHIDValueCallback(void *context, IOReturn result, void *sender,
                                  IOHIDValueRef value) {
    (void)sender;
    if (result != kIOReturnSuccess) return;
    GlideController *controller = (GlideController *)context;
    [controller recordHIDValue:value];
    [controller trackpadActivity];
}

static void GlideHIDReportCallback(void *context, IOReturn result, void *sender,
                                   IOHIDReportType type, uint32_t reportID,
                                   uint8_t *report, CFIndex reportLength) {
    (void)sender;
    if (result != kIOReturnSuccess) return;
    [(GlideController *)context recordHIDReportType:type reportID:reportID
                                               bytes:report length:reportLength];
}

@implementation GlideController

- (id)initWithBackgroundLaunch:(BOOL)backgroundLaunch logHID:(BOOL)logHID {
    self = [super init];
    if (!self) return nil;

    _backgroundLaunch = backgroundLaunch;
    if (logHID) {
        NSString *appPath = [[NSBundle mainBundle] bundlePath];
        NSString *logPath = [[appPath stringByDeletingLastPathComponent]
            stringByAppendingPathComponent:@"Glide-HID.log"];
        _hidLog = fopen([logPath fileSystemRepresentation], "wb");
        if (_hidLog) {
            chmod([logPath fileSystemRepresentation], S_IRUSR | S_IWUSR);
            fprintf(_hidLog, "Glide HID diagnostic log\nStart CFAbsoluteTime %.6f\n", CFAbsoluteTimeGetCurrent());
            fflush(_hidLog);
        }
    }
    NSMutableDictionary *registeredDefaults = [NSMutableDictionary dictionary];
    [registeredDefaults setObject:[NSNumber numberWithBool:YES] forKey:@"Enabled"];
    [registeredDefaults setObject:[NSNumber numberWithBool:NO] forKey:@"ShowDockIcon"];
    for (NSUInteger i = 0; i < kGlideSettingCount; i++) {
        [registeredDefaults setObject:[NSNumber numberWithDouble:kGlideSettingSpecs[i].defaultValue]
                               forKey:kGlideSettingSpecs[i].key];
    }
    [[NSUserDefaults standardUserDefaults] registerDefaults:registeredDefaults];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:@"TerminalVelocityHandoffV1"]) {
        if (fabs([defaults doubleForKey:@"SlowFlickGain"] - 0.08) < 0.0001)
            [defaults setDouble:1.0 forKey:@"SlowFlickGain"];
        if (fabs([defaults doubleForKey:@"FastFlickGain"] - 4.0) < 0.0001)
            [defaults setDouble:1.0 forKey:@"FastFlickGain"];
        if (fabs([defaults doubleForKey:@"InputQuietTime"] - 0.085) < 0.0001)
            [defaults setDouble:0.04 forKey:@"InputQuietTime"];
        [defaults setBool:YES forKey:@"TerminalVelocityHandoffV1"];
    }
    _enabled = [defaults boolForKey:@"Enabled"];

    _eventSource = CGEventSourceCreate(kCGEventSourceStateCombinedSessionState);
    CGEventMask mask = CGEventMaskBit(kCGEventScrollWheel);
    _tap = CGEventTapCreate(kCGSessionEventTap, kCGTailAppendEventTap,
                            kCGEventTapOptionListenOnly, mask,
                            GlideTapCallback, self);
    if (_tap) {
        _tapSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, _tap, 0);
        CFRunLoopAddSource(CFRunLoopGetMain(), _tapSource, kCFRunLoopCommonModes);
        CGEventTapEnable(_tap, true);
        _eventTapAvailable = YES;
    }

    _hidManager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    if (_hidManager) {
        int vendorID = 1452;
        int productID = 538; /* MacBook2,1 built-in Geyser 4 trackpad */
        CFNumberRef vendor = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &vendorID);
        CFNumberRef product = CFNumberCreate(kCFAllocatorDefault, kCFNumberIntType, &productID);
        const void *keys[] = { CFSTR(kIOHIDVendorIDKey), CFSTR(kIOHIDProductIDKey) };
        const void *values[] = { vendor, product };
        CFDictionaryRef matching = CFDictionaryCreate(kCFAllocatorDefault, keys, values, 2,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        IOHIDManagerSetDeviceMatching(_hidManager, matching);
        IOHIDManagerRegisterInputValueCallback(_hidManager, GlideHIDValueCallback, self);
        if (_hidLog) IOHIDManagerRegisterInputReportCallback(_hidManager, GlideHIDReportCallback, self);
        IOHIDManagerScheduleWithRunLoop(_hidManager, CFRunLoopGetMain(), kCFRunLoopCommonModes);
        _trackpadMonitorAvailable = (IOHIDManagerOpen(_hidManager, kIOHIDOptionsTypeNone) == kIOReturnSuccess);
        CFRelease(matching);
        CFRelease(vendor);
        CFRelease(product);
    }
    _preferencesController = [[GlidePreferencesController alloc]
        initWithDelegate:self
        enabled:_enabled
        startsAtLogin:[self loginItemIsEnabled]
        showsDockIcon:[defaults boolForKey:@"ShowDockIcon"]
        scrollAccessAvailable:_eventTapAvailable];
    if ([self legacyLaunchAgentIsInstalled]) [self setStartAtLogin:YES];
    [self refreshTimerInterval];
    return self;
}

- (double)settingValueForIndex:(NSUInteger)index {
    if (index >= kGlideSettingCount) return 0.0;
    return [[NSUserDefaults standardUserDefaults]
        doubleForKey:kGlideSettingSpecs[index].key];
}

- (void)refreshTimerInterval {
    if (_timer) { [_timer invalidate]; [_timer release]; }
    _timer = [[NSTimer scheduledTimerWithTimeInterval:[self settingValueForIndex:1]
                                               target:self selector:@selector(tick:)
                                             userInfo:nil repeats:YES] retain];
}

- (void)recordHIDValue:(IOHIDValueRef)value {
    if (!_hidLog || !value) return;
    IOHIDElementRef element = IOHIDValueGetElement(value);
    if (!element) return;
    fprintf(_hidLog, "VALUE t=%.6f page=0x%04x usage=0x%04x type=%u value=%ld length=%ld bytes=",
        CFAbsoluteTimeGetCurrent(), IOHIDElementGetUsagePage(element),
        IOHIDElementGetUsage(element), (unsigned int)IOHIDElementGetType(element),
        (long)IOHIDValueGetIntegerValue(value), (long)IOHIDValueGetLength(value));
    const uint8_t *bytes = IOHIDValueGetBytePtr(value);
    CFIndex length = IOHIDValueGetLength(value);
    for (CFIndex i = 0; bytes && i < length && i < 64; i++) fprintf(_hidLog, "%02x", bytes[i]);
    fputc('\n', _hidLog);
    fflush(_hidLog);
}

- (void)recordHIDReportType:(IOHIDReportType)type reportID:(uint32_t)reportID
                      bytes:(const uint8_t *)bytes length:(CFIndex)length {
    if (!_hidLog) return;
    fprintf(_hidLog, "REPORT t=%.6f type=%u id=%u length=%ld bytes=",
        CFAbsoluteTimeGetCurrent(), (unsigned int)type, reportID, (long)length);
    for (CFIndex i = 0; bytes && i < length && i < 256; i++) fprintf(_hidLog, "%02x", bytes[i]);
    fputc('\n', _hidLog);
    fflush(_hidLog);
}

- (void)dealloc {
    if (_timer) { [_timer invalidate]; [_timer release]; }
    if (_tapSource) { CFRunLoopRemoveSource(CFRunLoopGetMain(), _tapSource, kCFRunLoopCommonModes); CFRelease(_tapSource); }
    if (_tap) { CGEventTapEnable(_tap, false); CFRelease(_tap); }
    if (_hidManager) {
        IOHIDManagerUnscheduleFromRunLoop(_hidManager, CFRunLoopGetMain(), kCFRunLoopCommonModes);
        IOHIDManagerClose(_hidManager, kIOHIDOptionsTypeNone);
        CFRelease(_hidManager);
    }
    if (_eventSource) CFRelease(_eventSource);
    [_preferencesController release];
    if (_hidLog) {
        fprintf(_hidLog, "End CFAbsoluteTime %.6f\n", CFAbsoluteTimeGetCurrent());
        fclose(_hidLog);
    }
    [super dealloc];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    if (!_backgroundLaunch && ![NSApp isHidden]) [_preferencesController showPreferences];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    (void)sender; (void)flag;
    [_preferencesController showPreferences];
    return YES;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return NO;
}

- (NSString *)legacyLaunchAgentPath {
    return [NSHomeDirectory() stringByAppendingPathComponent:
        @"Library/LaunchAgents/org.codex.glide.plist"];
}

- (BOOL)legacyLaunchAgentIsInstalled {
    return [[NSFileManager defaultManager] fileExistsAtPath:[self legacyLaunchAgentPath]];
}

- (BOOL)loginItemIsEnabled {
    return GlideLoginItemIsInstalled() || [self legacyLaunchAgentIsInstalled];
}

- (void)setStartAtLogin:(BOOL)enabled {
    if (!GlideSetLoginItemEnabled(enabled)) {
        [self setStatus:@"Could not update the user's Login Items."];
        return;
    }
    [[NSFileManager defaultManager] removeItemAtPath:[self legacyLaunchAgentPath] error:nil];
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"StartAtLogin"];
    [self updateStatus];
}

- (void)setStatus:(NSString *)status {
    [_preferencesController setStatus:status];
}

- (void)updateStatus {
    [self setStatus:_enabled ? @"Glide is currently active." : @"Glide is currently inactive."];
}

- (void)glidePreferencesDidChangeEnabled:(BOOL)enabled {
    _enabled = enabled;
    _coasting = NO;
    _velocityX = _velocityY = 0.0;
}

- (void)glidePreferencesDidChangeLoginItem:(BOOL)enabled {
    [self setStartAtLogin:enabled];
}

- (BOOL)glidePreferencesShouldShowDockIcon:(BOOL)visible {
    return GlideSetDockIconVisible(visible);
}

- (void)glidePreferencesDidChangeAnimationInterval {
    [self refreshTimerInterval];
}

- (void)handleScrollEvent:(CGEventRef)event {
    if (!_enabled) return;
    double now = CFAbsoluteTimeGetCurrent();
    double x = CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis2);
    double y = CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis1);
    if (x == 0.0 && y == 0.0) {
        x = CGEventGetDoubleValueField(event, kCGScrollWheelEventFixedPtDeltaAxis2);
        y = CGEventGetDoubleValueField(event, kCGScrollWheelEventFixedPtDeltaAxis1);
    }
    if (x == 0.0 && y == 0.0) {
        x = CGEventGetIntegerValueField(event, kCGScrollWheelEventDeltaAxis2) * 10.0;
        y = CGEventGetIntegerValueField(event, kCGScrollWheelEventDeltaAxis1) * 10.0;
    }
    if (x == 0.0 && y == 0.0) return;

    double dt = now - _lastEventTime;
    if (_lastEventTime <= 0.0 || dt > 0.20 || dt <= 0.0) {
        _scrollSampleCount = 0;
    }
    double intervalStart = (_lastEventTime > 0.0 && dt > 0.0 && dt <= 0.20)
        ? _lastEventTime : now - (1.0 / 120.0);

    NSUInteger maximumSamples = (NSUInteger)[self settingValueForIndex:12];
    while (_scrollSampleCount >= maximumSamples) {
        memmove(&_scrollSamples[0], &_scrollSamples[1],
                sizeof(GlideScrollSample) * (_scrollSampleCount - 1));
        _scrollSampleCount--;
    }
    GlideScrollSample *sample = &_scrollSamples[_scrollSampleCount++];
    sample->startTime = intervalStart;
    sample->endTime = now;
    sample->deltaX = x;
    sample->deltaY = y;

    while (_scrollSampleCount > 1 &&
           _scrollSamples[0].endTime < now - [self settingValueForIndex:4]) {
        memmove(&_scrollSamples[0], &_scrollSamples[1],
                sizeof(GlideScrollSample) * (_scrollSampleCount - 1));
        _scrollSampleCount--;
    }

    double weightedVelocityX = 0.0;
    double weightedVelocityY = 0.0;
    double weightTotal = 0.0;
    double velocityWindow = [self settingValueForIndex:4];
    double recencyTimeConstant = fmax(velocityWindow * 0.35, 0.005);
    for (NSUInteger i = 0; i < _scrollSampleCount; i++) {
        double sampleDuration = _scrollSamples[i].endTime - _scrollSamples[i].startTime;
        double sampleAge = now - _scrollSamples[i].endTime;
        if (sampleDuration <= 0.001 || sampleAge < 0.0 || sampleAge > velocityWindow) continue;
        double recencyWeight = exp(-sampleAge / recencyTimeConstant);
        weightedVelocityX += (_scrollSamples[i].deltaX / sampleDuration) * recencyWeight;
        weightedVelocityY += (_scrollSamples[i].deltaY / sampleDuration) * recencyWeight;
        weightTotal += recencyWeight;
    }
    if (weightTotal <= 0.0) return;
    double measuredX = weightedVelocityX / weightTotal;
    double measuredY = weightedVelocityY / weightTotal;
    double measuredSpeed = hypot(measuredX, measuredY);
    double gainProgress = measuredSpeed / [self settingValueForIndex:7];
    if (gainProgress > 1.0) gainProgress = 1.0;
    double slowGain = [self settingValueForIndex:5];
    double fastGain = [self settingValueForIndex:6];
    double gain = slowGain + (fastGain - slowGain) *
        pow(gainProgress, [self settingValueForIndex:8]);
    _velocityX = measuredX * gain;
    _velocityY = measuredY * gain;
    double speed = hypot(_velocityX, _velocityY);
    double maximumVelocity = [self settingValueForIndex:3];
    if (speed > maximumVelocity) {
        double scale = maximumVelocity / speed;
        _velocityX *= scale;
        _velocityY *= scale;
    }
    _lastEventTime = now;
    _lastInputTime = now;
    _coasting = NO;
}

- (void)tick:(NSTimer *)timer {
    (void)timer;
    if (!_enabled) return;
    if (_coasting) {
        [self animateCoast];
        return;
    }
    if (_lastInputTime <= 0.0) return;
    double now = CFAbsoluteTimeGetCurrent();
    if (now - _lastInputTime < [self settingValueForIndex:0]) return;
    if (hypot(_velocityX, _velocityY) < [self settingValueForIndex:2]) return;
    _coasting = YES;
    _lastTickTime = now;
    double startingSpeed = hypot(_velocityX, _velocityY);
    _coastStartedTime = now;
    _coastFriction = [self settingValueForIndex:9] +
        [self settingValueForIndex:10] * fmin(startingSpeed / 2000.0, 1.0);
    _fractionX = _fractionY = 0.0;
    [self animateCoast];
}

- (void)sendCoastDeltaX:(double)x y:(double)y {
    _fractionX += x;
    _fractionY += y;
    int32_t dx = (int32_t)_fractionX;
    int32_t dy = (int32_t)_fractionY;
    _fractionX -= dx;
    _fractionY -= dy;
    if (dx == 0 && dy == 0) return;
    CGEventRef generated = CGEventCreateScrollWheelEvent(_eventSource,
        kCGScrollEventUnitPixel, 2, dy, dx);
    if (!generated) return;
    CGEventSetIntegerValueField(generated, kCGScrollWheelEventIsContinuous, 1);
    CGEventSetIntegerValueField(generated, kCGEventSourceUserData, kGlideEventTag);
    CGEventPost(kCGHIDEventTap, generated);
    CFRelease(generated);
}

- (void)animateCoast {
    if (!_coasting) return;
    double now = CFAbsoluteTimeGetCurrent();
    double dt = now - _lastTickTime;
    if (dt <= 0.0 || dt > 0.10) dt = [self settingValueForIndex:1];
    _lastTickTime = now;
    double speed = hypot(_velocityX, _velocityY);
    double minimumVelocity = [self settingValueForIndex:2];
    if (speed < minimumVelocity) {
        _coasting = NO;
        _velocityX = _velocityY = 0.0;
        return;
    }
    double friction = _coastFriction > 0.0 ? _coastFriction : [self settingValueForIndex:9];
    double decay = exp(-friction * dt);
    double nextSpeed = speed * decay;
    double distance = speed * (1.0 - decay) / friction;
    double dx = (_velocityX / speed) * distance;
    double dy = (_velocityY / speed) * distance;
    double velocityScale = nextSpeed / speed;
    _velocityX *= velocityScale;
    _velocityY *= velocityScale;
    [self sendCoastDeltaX:dx y:dy];
    if (nextSpeed < minimumVelocity) {
        _coasting = NO;
        _velocityX = _velocityY = 0.0;
    }
}

- (void)eventTapWasDisabled {
    if (_tap) CGEventTapEnable(_tap, true);
}

- (void)trackpadActivity {
    if (_coasting && CFAbsoluteTimeGetCurrent() - _coastStartedTime >= [self settingValueForIndex:11]) {
        _coasting = NO;
        _velocityX = _velocityY = 0.0;
        _fractionX = _fractionY = 0.0;
    }
}

@end

int main(int argc, const char *argv[]) {
    BOOL backgroundLaunch = NO;
    BOOL logHID = NO;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--background") == 0) backgroundLaunch = YES;
        if (strcmp(argv[i], "--log-hid") == 0) logHID = YES;
    }
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSApplication *app = [NSApplication sharedApplication];
    GlideController *controller = [[GlideController alloc]
        initWithBackgroundLaunch:backgroundLaunch logHID:logHID];
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"ShowDockIcon"]) {
        if (!GlideSetDockIconVisible(YES)) NSLog(@"Glide could not show its Dock icon");
    }
    [app setDelegate:controller];
    [app run];
    [controller release];
    [pool drain];
    return 0;
}
