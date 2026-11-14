// Moonkey.app — keyboard backlight controls for the Touch Bar and menu bar.
//
// Which controls appear is decided per user:
//   ShowTouchBarButton  default: YES on Macs with a Touch Bar
//   ShowMenuBarIcon     default: YES on Macs without one
// Override with e.g.
//   defaults write io.github.simon-lumikello.moonkey ShowMenuBarIcon -bool YES
// Changes apply immediately; `defaults delete …` returns to the default.
#import <AppKit/AppKit.h>
#import "MKBacklight.h"
#import "MKMenuBarController.h"
#import "MKTouchBarController.h"

static NSString *const kShowTouchBarButtonKey = @"ShowTouchBarButton";
static NSString *const kShowMenuBarIconKey    = @"ShowMenuBarIcon";

@interface MKAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation MKAppDelegate {
    MKBacklight *_backlight;
    MKTouchBarController *_touchBar;
    MKMenuBarController *_menuBar;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    BOOL hasTouchBar = MKTouchBarController.isSupported;
    [NSUserDefaults.standardUserDefaults registerDefaults:@{
        kShowTouchBarButtonKey: @(hasTouchBar),
        kShowMenuBarIconKey:    @(!hasTouchBar),
    }];

    _backlight = [MKBacklight new];
    if (hasTouchBar) _touchBar = [[MKTouchBarController alloc] initWithBacklight:_backlight];
    _menuBar = [[MKMenuBarController alloc] initWithBacklight:_backlight];

    // Picks up `defaults write` from Terminal while running.
    for (NSString *key in @[kShowTouchBarButtonKey, kShowMenuBarIconKey])
        [NSUserDefaults.standardUserDefaults addObserver:self forKeyPath:key options:0 context:NULL];
    [self updateVisibility];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    dispatch_async(dispatch_get_main_queue(), ^{ [self updateVisibility]; });
}

- (void)updateVisibility {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    _touchBar.visible = [defaults boolForKey:kShowTouchBarButtonKey];
    _menuBar.visible  = [defaults boolForKey:kShowMenuBarIconKey];
}

@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        app.activationPolicy = NSApplicationActivationPolicyAccessory;   // no Dock icon, no app menu
        MKAppDelegate *delegate = [MKAppDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
