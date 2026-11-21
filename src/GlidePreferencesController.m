#import "GlidePreferencesController.h"
#import "GlideSettings.h"
#import <math.h>

@interface GlideHoverSlider : NSSlider {
    id _hoverTarget;
    SEL _hoverAction;
    NSTrackingArea *_hoverArea;
}
- (void)setHoverTarget:(id)target action:(SEL)action;
@end

@implementation GlideHoverSlider
- (void)setHoverTarget:(id)target action:(SEL)action {
    _hoverTarget = target;
    _hoverAction = action;
}
- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_hoverArea) {
        [self removeTrackingArea:_hoverArea];
        [_hoverArea release];
    }
    _hoverArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
        options:(NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingInVisibleRect)
        owner:self userInfo:nil];
    [self addTrackingArea:_hoverArea];
}
- (void)mouseEntered:(NSEvent *)event {
    (void)event;
    if (_hoverTarget && _hoverAction) [_hoverTarget performSelector:_hoverAction withObject:self];
}
- (void)dealloc {
    if (_hoverArea) { [self removeTrackingArea:_hoverArea]; [_hoverArea release]; }
    [super dealloc];
}
@end

@interface GlidePreferencesController ()
- (void)addSettingIndex:(NSUInteger)index toView:(NSView *)view columnX:(CGFloat)x rowY:(CGFloat)y;
- (NSTextField *)newDescriptionLabelInView:(NSView *)view;
- (NSTextField *)newExplanatoryLabelInView:(NSView *)view frame:(NSRect)frame message:(NSString *)message;
- (void)closePreferences:(id)sender;
- (void)restorePreferencesWindow:(id)sender;
- (void)resetSettings:(id)sender;
- (void)settingHovered:(id)sender;
- (void)settingChanged:(id)sender;
- (void)enabledChanged:(id)sender;
- (void)loginChanged:(id)sender;
- (void)dockIconChanged:(id)sender;
@end

@implementation GlidePreferencesController

- (id)initWithDelegate:(id<GlidePreferencesControllerDelegate>)delegate
               enabled:(BOOL)enabled
         startsAtLogin:(BOOL)startsAtLogin
          showsDockIcon:(BOOL)showsDockIcon
     scrollAccessAvailable:(BOOL)scrollAccessAvailable {
    self = [super init];
    if (!self) return nil;
    _delegate = delegate;
    _scrollAccessAvailable = scrollAccessAvailable;
    _enabledCheckbox = nil;
    _loginCheckbox = nil;
    _dockCheckbox = nil;
    _initialEnabled = enabled;
    _initialStartsAtLogin = startsAtLogin;
    _initialShowsDockIcon = showsDockIcon;
    return self;
}

- (void)dealloc {
    [_window release];
    [_tabs release];
    [_enabledCheckbox release];
    [_loginCheckbox release];
    [_dockCheckbox release];
    [_statusLabel release];
    for (NSUInteger i = 0; i < 2; i++) [_settingDescriptionLabels[i] release];
    for (NSUInteger i = 0; i < kGlideSettingCount; i++) {
        [_settingSliders[i] release];
        [_settingValueLabels[i] release];
    }
    [super dealloc];
}

- (void)showPreferences {
    if (!_window) {
        NSRect frame = NSMakeRect(0, 0, 620, 390);
        _window = [[NSWindow alloc] initWithContentRect:frame
            styleMask:(NSTitledWindowMask | NSClosableWindowMask)
              backing:NSBackingStoreBuffered defer:NO];
        [_window setTitle:@"Glide Preferences"];
        [_window setReleasedWhenClosed:NO];
        [[_window standardWindowButton:NSWindowCloseButton] setHidden:YES];
        [[_window standardWindowButton:NSWindowMiniaturizeButton] setHidden:YES];
        [[_window standardWindowButton:NSWindowZoomButton] setHidden:YES];
        NSView *content = [_window contentView];

        _tabs = [[NSTabView alloc] initWithFrame:NSMakeRect(12, 12, 596, 366)];
        [_tabs setTabViewType:NSTopTabsBezelBorder];
        [content addSubview:_tabs];

        NSView *generalView = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 330)] autorelease];
        NSTabViewItem *generalItem = [[[NSTabViewItem alloc] initWithIdentifier:@"general"] autorelease];
        [generalItem setLabel:@"General"];
        [generalItem setView:generalView];
        [_tabs addTabViewItem:generalItem];

        NSTextField *overviewLabel = [self newExplanatoryLabelInView:generalView
            frame:NSMakeRect(20, 268, 540, 38)
            message:@"Glide brings the smooth inertial scrolling of modern macOS to older Mac OS X trackpads."];
        [overviewLabel setTextColor:[NSColor controlTextColor]];

        _enabledCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(20, 238, 540, 24)];
        [_enabledCheckbox setButtonType:NSSwitchButton];
        [_enabledCheckbox setTitle:@"Enable inertial scrolling"];
        [_enabledCheckbox setState:_initialEnabled ? NSOnState : NSOffState];
        [_enabledCheckbox setTarget:self]; [_enabledCheckbox setAction:@selector(enabledChanged:)];
        [generalView addSubview:_enabledCheckbox];
        [self newExplanatoryLabelInView:generalView frame:NSMakeRect(20, 190, 540, 40)
            message:@"You can close this window and Glide will keep running. Choose Quit Glide to stop inertial scrolling; open Glide again to resume."];

        _loginCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(20, 143, 540, 24)];
        [_loginCheckbox setButtonType:NSSwitchButton];
        [_loginCheckbox setTitle:@"Launch Glide at login"];
        [_loginCheckbox setState:_initialStartsAtLogin ? NSOnState : NSOffState];
        [_loginCheckbox setTarget:self]; [_loginCheckbox setAction:@selector(loginChanged:)];
        [generalView addSubview:_loginCheckbox];
        [self newExplanatoryLabelInView:generalView frame:NSMakeRect(20, 95, 540, 40)
            message:@"When enabled, Glide starts automatically at login, so you do not need to launch it manually."];

        _dockCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(20, 59, 540, 24)];
        [_dockCheckbox setButtonType:NSSwitchButton];
        [_dockCheckbox setTitle:@"Show Glide in the Dock"];
        [_dockCheckbox setState:_initialShowsDockIcon ? NSOnState : NSOffState];
        [_dockCheckbox setTarget:self]; [_dockCheckbox setAction:@selector(dockIconChanged:)];
        [generalView addSubview:_dockCheckbox];

        _statusLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 17, 280, 20)];
        [_statusLabel setBezeled:NO]; [_statusLabel setDrawsBackground:NO];
        [_statusLabel setEditable:NO]; [_statusLabel setSelectable:NO];
        [_statusLabel setFont:[NSFont systemFontOfSize:11.0]];
        [generalView addSubview:_statusLabel];

        NSButton *quitButton = [[[NSButton alloc] initWithFrame:NSMakeRect(350, 12, 90, 26)] autorelease];
        [quitButton setTitle:@"Quit Glide"];
        [quitButton setBezelStyle:NSRoundedBezelStyle];
        [quitButton setTarget:NSApp]; [quitButton setAction:@selector(terminate:)];
        [generalView addSubview:quitButton];
        NSButton *closeButton = [[[NSButton alloc] initWithFrame:NSMakeRect(450, 12, 110, 26)] autorelease];
        [closeButton setTitle:@"Close Prefs"];
        [closeButton setBezelStyle:NSRoundedBezelStyle];
        [closeButton setKeyEquivalent:@"\r"];
        [closeButton setTarget:self]; [closeButton setAction:@selector(closePreferences:)];
        [generalView addSubview:closeButton];

        NSView *motionView = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 330)] autorelease];
        NSTabViewItem *motionItem = [[[NSTabViewItem alloc] initWithIdentifier:@"motion"] autorelease];
        [motionItem setLabel:@"Motion"];
        [motionItem setView:motionView];
        [_tabs addTabViewItem:motionItem];
        NSUInteger motionColumns[2][2] = {{5, 7}, {6, 8}};
        for (NSUInteger column = 0; column < 2; column++) {
            for (NSUInteger row = 0; row < 2; row++) {
                CGFloat y = 120 + (1 - row) * 100;
                [self addSettingIndex:motionColumns[column][row] toView:motionView
                    columnX:(column == 0 ? 20 : 325) rowY:y];
            }
        }
        _settingDescriptionLabels[0] = [self newDescriptionLabelInView:motionView];
        NSButton *motionReset = [[[NSButton alloc] initWithFrame:NSMakeRect(420, 5, 140, 26)] autorelease];
        [motionReset setTitle:@"Reset to Defaults"];
        [motionReset setBezelStyle:NSRoundedBezelStyle];
        [motionReset setTag:0];
        [motionReset setTarget:self]; [motionReset setAction:@selector(resetSettings:)];
        [motionView addSubview:motionReset];

        NSView *coastingView = [[[NSView alloc] initWithFrame:NSMakeRect(0, 0, 580, 330)] autorelease];
        NSTabViewItem *coastingItem = [[[NSTabViewItem alloc] initWithIdentifier:@"coasting"] autorelease];
        [coastingItem setLabel:@"Coasting"];
        [coastingItem setView:coastingView];
        [_tabs addTabViewItem:coastingItem];
        NSUInteger coastColumns[2][5] = {{2, 3, 0, 1, 4}, {9, 10, 11, 12, NSNotFound}};
        for (NSUInteger column = 0; column < 2; column++) {
            for (NSUInteger row = 0; row < 5; row++) {
                NSUInteger index = coastColumns[column][row];
                if (index == NSNotFound) continue;
                CGFloat y = 58 + (4 - row) * 51;
                [self addSettingIndex:index toView:coastingView
                    columnX:(column == 0 ? 20 : 325) rowY:y];
            }
        }
        _settingDescriptionLabels[1] = [self newDescriptionLabelInView:coastingView];
        NSButton *coastingReset = [[[NSButton alloc] initWithFrame:NSMakeRect(420, 5, 140, 26)] autorelease];
        [coastingReset setTitle:@"Reset to Defaults"];
        [coastingReset setBezelStyle:NSRoundedBezelStyle];
        [coastingReset setTag:1];
        [coastingReset setTarget:self]; [coastingReset setAction:@selector(resetSettings:)];
        [coastingView addSubview:coastingReset];
    }
    if (!_scrollAccessAvailable) {
        [self setStatus:@"Scroll access unavailable. Enable access for assistive devices in Universal Access, then reopen Glide."];
    } else {
        [self setStatus:[[NSUserDefaults standardUserDefaults] boolForKey:@"Enabled"]
            ? @"Glide is currently active." : @"Glide is currently inactive."];
    }
    [_window center];
    [_window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)addSettingIndex:(NSUInteger)index toView:(NSView *)view columnX:(CGFloat)x rowY:(CGFloat)y {
    NSTextField *title = [[[NSTextField alloc] initWithFrame:NSMakeRect(x, y + 22, 155, 17)] autorelease];
    [title setStringValue:kGlideSettingSpecs[index].title];
    [title setFont:[NSFont systemFontOfSize:11.0]];
    [title setBezeled:NO]; [title setDrawsBackground:NO]; [title setEditable:NO]; [title setSelectable:NO];
    [view addSubview:title];

    _settingValueLabels[index] = [[NSTextField alloc] initWithFrame:NSMakeRect(x + 160, y + 22, 75, 17)];
    [_settingValueLabels[index] setAlignment:NSRightTextAlignment];
    [_settingValueLabels[index] setFont:[NSFont systemFontOfSize:11.0]];
    [_settingValueLabels[index] setBezeled:NO]; [_settingValueLabels[index] setDrawsBackground:NO];
    [_settingValueLabels[index] setEditable:NO]; [_settingValueLabels[index] setSelectable:NO];
    [view addSubview:_settingValueLabels[index]];

    _settingSliders[index] = [[GlideHoverSlider alloc] initWithFrame:NSMakeRect(x, y, 235, 18)];
    [_settingSliders[index] setMinValue:kGlideSettingSpecs[index].minimumValue];
    [_settingSliders[index] setMaxValue:kGlideSettingSpecs[index].maximumValue];
    [_settingSliders[index] setDoubleValue:[[NSUserDefaults standardUserDefaults]
        doubleForKey:kGlideSettingSpecs[index].key]];
    [_settingSliders[index] setTag:(NSInteger)index];
    [(GlideHoverSlider *)_settingSliders[index] setHoverTarget:self action:@selector(settingHovered:)];
    [_settingSliders[index] setTarget:self]; [_settingSliders[index] setAction:@selector(settingChanged:)];
    [view addSubview:_settingSliders[index]];
    [self settingChanged:_settingSliders[index]];
}

- (NSTextField *)newDescriptionLabelInView:(NSView *)view {
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 5, 390, 40)];
    [[label cell] setWraps:YES];
    [[label cell] setLineBreakMode:NSLineBreakByWordWrapping];
    [label setStringValue:@"Hover over a slider to see what it controls."];
    [label setFont:[NSFont systemFontOfSize:11.0]];
    [label setTextColor:[NSColor darkGrayColor]];
    [label setBezeled:NO]; [label setDrawsBackground:NO];
    [label setEditable:NO]; [label setSelectable:NO];
    [view addSubview:label];
    return label;
}

- (NSTextField *)newExplanatoryLabelInView:(NSView *)view frame:(NSRect)frame message:(NSString *)message {
    NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [[label cell] setWraps:YES];
    [[label cell] setLineBreakMode:NSLineBreakByWordWrapping];
    [label setStringValue:message];
    [label setFont:[NSFont systemFontOfSize:11.0]];
    [label setTextColor:[NSColor darkGrayColor]];
    [label setBezeled:NO]; [label setDrawsBackground:NO];
    [label setEditable:NO]; [label setSelectable:NO];
    [view addSubview:label];
    return label;
}

- (void)setStatus:(NSString *)status {
    if (_statusLabel) [_statusLabel setStringValue:status];
}

- (void)closePreferences:(id)sender {
    (void)sender;
    [NSObject cancelPreviousPerformRequestsWithTarget:self
        selector:@selector(restorePreferencesWindow:) object:nil];
    [_window close];
}

- (void)resetSettings:(id)sender {
    NSUInteger group = (NSUInteger)[sender tag];
    for (NSUInteger i = 0; i < kGlideSettingCount; i++) {
        BOOL motionSetting = i == 5 || i == 6 || i == 7 || i == 8;
        if (motionSetting != (group == 0)) continue;
        [_settingSliders[i] setDoubleValue:kGlideSettingSpecs[i].defaultValue];
        [self settingChanged:_settingSliders[i]];
    }
    [_settingDescriptionLabels[group] setStringValue:
        group == 0 ? @"Motion settings were reset to their defaults." :
                     @"Coasting settings were reset to their defaults."];
}

- (void)settingHovered:(id)sender {
    NSUInteger index = (NSUInteger)[sender tag];
    static NSString *descriptions[] = {
        @"Delay after the final scroll event before coasting begins. A shorter delay hands off sooner.",
        @"Time between animation updates. Smaller values update the coast more often.",
        @"Coasting stops when the estimated speed falls below this value.",
        @"Caps the estimated launch speed so a very strong flick cannot produce an extreme coast.",
        @"Time span used to estimate flick speed. Recent events receive more weight than older ones.",
        @"Gain applied at the slow end of the flick curve. A value of 1 preserves the measured speed.",
        @"Gain applied at the fast end of the flick curve. A value of 1 preserves the measured speed.",
        @"Measured flick speed at which the curve reaches the fast-flick gain.",
        @"Controls how quickly gain rises between the slow- and fast-flick settings.",
        @"Baseline resistance during coasting. Higher values shorten the coast.",
        @"Additional resistance for faster coasts. Higher values shorten fast-flick travel.",
        @"Briefly ignores trackpad reports after coasting starts, avoiding cancellation from finger-release reports.",
        @"Maximum number of recent scroll events kept for estimating flick speed."
    };
    if (index < kGlideSettingCount) {
        BOOL motionSetting = index == 5 || index == 6 || index == 7 || index == 8;
        [_settingDescriptionLabels[motionSetting ? 0 : 1] setStringValue:descriptions[index]];
    }
}

- (void)settingChanged:(id)sender {
    NSUInteger index = (NSUInteger)[sender tag];
    if (index >= kGlideSettingCount) return;
    double value = [sender doubleValue];
    if (kGlideSettingSpecs[index].integerValue) value = floor(value + 0.5);
    [[NSUserDefaults standardUserDefaults] setDouble:value forKey:kGlideSettingSpecs[index].key];
    [sender setDoubleValue:value];
    double displayValue = value * kGlideSettingSpecs[index].displayScale;
    NSString *displayText = [NSString stringWithFormat:
        (kGlideSettingSpecs[index].integerValue ? @"%.0f" : @"%.3g"), displayValue];
    if ([kGlideSettingSpecs[index].unit length] > 0) {
        displayText = [displayText stringByAppendingFormat:@" %@", kGlideSettingSpecs[index].unit];
    }
    [_settingValueLabels[index] setStringValue:displayText];
    if (index == 1) [_delegate glidePreferencesDidChangeAnimationInterval];
}

- (void)enabledChanged:(id)sender {
    BOOL enabled = ([sender state] == NSOnState);
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:@"Enabled"];
    [_delegate glidePreferencesDidChangeEnabled:enabled];
    [self setStatus:enabled ? @"Glide is currently active." : @"Glide is currently inactive."];
}

- (void)loginChanged:(id)sender {
    [_delegate glidePreferencesDidChangeLoginItem:([sender state] == NSOnState)];
}

- (void)dockIconChanged:(id)sender {
    BOOL showDockIcon = ([sender state] == NSOnState);
    if ([_delegate glidePreferencesShouldShowDockIcon:showDockIcon]) {
        [[NSUserDefaults standardUserDefaults] setBool:showDockIcon forKey:@"ShowDockIcon"];
        [self performSelector:@selector(restorePreferencesWindow:) withObject:nil afterDelay:0.25];
    } else {
        NSLog(@"Glide could not change Dock visibility");
        [sender setState:showDockIcon ? NSOffState : NSOnState];
    }
}

- (void)restorePreferencesWindow:(id)sender {
    (void)sender;
    if (!_window) return;
    ProcessSerialNumber process = { 0, kCurrentProcess };
    SetFrontProcess(&process);
    [NSApp activateIgnoringOtherApps:YES];
    [_window makeKeyAndOrderFront:nil];
}

@end
