#import <AppKit/AppKit.h>

@protocol GlidePreferencesControllerDelegate
- (void)glidePreferencesDidChangeEnabled:(BOOL)enabled;
- (void)glidePreferencesDidChangeLoginItem:(BOOL)enabled;
- (BOOL)glidePreferencesShouldShowDockIcon:(BOOL)visible;
- (void)glidePreferencesDidChangeAnimationInterval;
@end

@interface GlidePreferencesController : NSObject {
    id<GlidePreferencesControllerDelegate> _delegate;
    NSWindow *_window;
    NSTabView *_tabs;
    NSButton *_enabledCheckbox;
    NSButton *_loginCheckbox;
    NSButton *_dockCheckbox;
    NSTextField *_statusLabel;
    NSTextField *_settingDescriptionLabels[2];
    NSSlider *_settingSliders[13];
    NSTextField *_settingValueLabels[13];
    BOOL _scrollAccessAvailable;
    BOOL _initialEnabled;
    BOOL _initialStartsAtLogin;
    BOOL _initialShowsDockIcon;
}
- (id)initWithDelegate:(id<GlidePreferencesControllerDelegate>)delegate
               enabled:(BOOL)enabled
         startsAtLogin:(BOOL)startsAtLogin
          showsDockIcon:(BOOL)showsDockIcon
     scrollAccessAvailable:(BOOL)scrollAccessAvailable;
- (void)showPreferences;
- (void)setStatus:(NSString *)status;
@end
