// The slider opens to the left of a circled close button placed exactly where
// the Moonkey button sits in the Control Strip, as the volume control does.
//
// macOS has no public API for Control Strip items, so this uses the same
// private DFRFoundation/AppKit calls as other Touch Bar customisers. They are
// resolved at runtime and +isSupported reports whether they exist.
#import "MKTouchBarController.h"
#import "MKBacklight.h"
#import <AppKit/AppKit.h>
#import <IOKit/hid/IOHIDManager.h>
#include <dlfcn.h>

// Private AppKit class methods for system-wide ("system modal") Touch Bars.
@interface NSTouchBarItem (ControlStrip)
+ (void)addSystemTrayItem:(NSTouchBarItem *)item;
+ (void)removeSystemTrayItem:(NSTouchBarItem *)item;
@end

@interface NSTouchBar (ControlStrip)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar
                         placement:(long long)placement
          systemTrayItemIdentifier:(NSTouchBarItemIdentifier)identifier;
+ (void)minimizeSystemModalTouchBar:(NSTouchBar *)touchBar;
@end

// Private DFRFoundation functions, resolved with dlsym.
static void (*DFRElementSetControlStripPresenceForIdentifier)(NSTouchBarItemIdentifier, BOOL);
static CGRect (*DFRGetScreenRectForPlacement)(long placement);

// Placement 1 covers the whole Touch Bar and leaves layout to us, which lets
// the panel line up with our Control Strip button.
static const long long kFullWidthPlacement = 1;

static NSTouchBarItemIdentifier const kStripItemID   = @"moonkey.strip";
static NSTouchBarItemIdentifier const kSliderItemID  = @"moonkey.slider";
static NSTouchBarItemIdentifier const kCloseItemID   = @"moonkey.close";
static NSTouchBarItemIdentifier const kTrailerItemID = @"moonkey.trailer";

static const CGFloat kSliderWidth      = 216;  // matches the system volume slider
static const CGFloat kCloseButtonWidth = 44;
static const CGFloat kCloseSymbolSize  = 18;
static const CGFloat kItemSpacing      = 8;    // gap the Touch Bar puts between items

static const uint32_t kSliderFadeMs = 64;      // short, so the slider feels immediate

static NSImage *Symbol(NSString *name, NSString *description) {
    return [NSImage imageWithSystemSymbolName:name accessibilityDescription:description];
}

// Light grey circle with a dark cross, like the system's Touch Bar close box.
static NSImage *CloseBoxImage(void) {
    NSImageSymbolConfiguration *config =
        [[NSImageSymbolConfiguration configurationWithPointSize:kCloseSymbolSize weight:NSFontWeightBold]
            configurationByApplyingConfiguration:
                [NSImageSymbolConfiguration configurationWithPaletteColors:@[
                    NSColor.blackColor, [NSColor colorWithWhite:0.72 alpha:1]]]];
    return [Symbol(@"xmark.circle.fill", @"Close") imageWithSymbolConfiguration:config];
}

// The Touch Bar's display is a T2 USB device, 05ac:8302 ("Touch Bar Display").
static BOOL HasTouchBarHardware(void) {
    int vendor = 0x05ac, product = 0x8302;
    NSDictionary *match = @{@kIOHIDVendorIDKey: @(vendor), @kIOHIDProductIDKey: @(product)};
    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    IOHIDManagerSetDeviceMatching(manager, (__bridge CFDictionaryRef)match);
    CFSetRef devices = IOHIDManagerCopyDevices(manager);
    BOOL found = devices && CFSetGetCount(devices) > 0;
    if (devices) CFRelease(devices);
    CFRelease(manager);
    return found;
}

@interface MKTouchBarController () <NSTouchBarDelegate>
@end

@implementation MKTouchBarController {
    MKBacklight *_backlight;
    NSCustomTouchBarItem *_stripItem;
    NSButton *_stripButton;
    NSTouchBar *_panel;
    NSSliderTouchBarItem *_sliderItem;
    NSLayoutConstraint *_trailerWidth;
}

+ (BOOL)isSupported {
    static BOOL supported;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *dfr = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY);
        DFRElementSetControlStripPresenceForIdentifier = dlsym(dfr, "DFRElementSetControlStripPresenceForIdentifier");
        DFRGetScreenRectForPlacement = dlsym(dfr, "DFRGetScreenRectForPlacement");
        supported = DFRElementSetControlStripPresenceForIdentifier &&
            [NSTouchBarItem respondsToSelector:@selector(addSystemTrayItem:)] &&
            [NSTouchBarItem respondsToSelector:@selector(removeSystemTrayItem:)] &&
            [NSTouchBar respondsToSelector:@selector(presentSystemModalTouchBar:placement:systemTrayItemIdentifier:)] &&
            [NSTouchBar respondsToSelector:@selector(minimizeSystemModalTouchBar:)] &&
            HasTouchBarHardware();
    });
    return supported;
}

- (instancetype)initWithBacklight:(MKBacklight *)backlight {
    if ((self = [super init])) {
        _backlight = backlight;

        _stripButton = [NSButton buttonWithImage:[self stripImage] target:self action:@selector(openPanel:)];
        _stripItem = [[NSCustomTouchBarItem alloc] initWithIdentifier:kStripItemID];
        _stripItem.view = _stripButton;

        _panel = [NSTouchBar new];
        _panel.delegate = self;
        _panel.defaultItemIdentifiers = @[NSTouchBarItemIdentifierFlexibleSpace,
                                          kSliderItemID, kCloseItemID, kTrailerItemID];

        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateViews)
                                                   name:MKBacklightDidChangeNotification object:backlight];

        // The Control Strip can forget our item across sleep and user switching.
        NSNotificationCenter *workspace = NSWorkspace.sharedWorkspace.notificationCenter;
        [workspace addObserver:self selector:@selector(reassertPresence)
                          name:NSWorkspaceDidWakeNotification object:nil];
        [workspace addObserver:self selector:@selector(reassertPresence)
                          name:NSWorkspaceSessionDidBecomeActiveNotification object:nil];
    }
    return self;
}

- (void)setVisible:(BOOL)visible {
    if (visible == _visible || ![MKTouchBarController isSupported]) return;
    _visible = visible;
    if (visible) {
        [NSTouchBarItem addSystemTrayItem:_stripItem];
        DFRElementSetControlStripPresenceForIdentifier(kStripItemID, YES);
    } else {
        [NSTouchBar minimizeSystemModalTouchBar:_panel];
        DFRElementSetControlStripPresenceForIdentifier(kStripItemID, NO);
        [NSTouchBarItem removeSystemTrayItem:_stripItem];
    }
}

- (void)reassertPresence {
    if (_visible) DFRElementSetControlStripPresenceForIdentifier(kStripItemID, YES);
}

#pragma mark - UI

- (NSImage *)stripImage {
    return _backlight.on ? Symbol(@"light.max", @"Keyboard backlight on")
                         : Symbol(@"light.min", @"Keyboard backlight off");
}

- (void)updateViews {
    _stripButton.image = [self stripImage];
    _sliderItem.slider.integerValue = _backlight.on ? _backlight.level : 0;
}

// Width of the empty space right of the close button, chosen so the close
// button is centred where the Moonkey button sits in the Control Strip.
- (CGFloat)trailerWidth {
    NSWindow *window = _stripButton.window;
    if (!window || !DFRGetScreenRectForPlacement) return 0;
    CGRect touchBar = DFRGetScreenRectForPlacement(kFullWidthPlacement);
    CGFloat buttonCenter = NSMinX(window.frame) + NSMidX([_stripButton convertRect:_stripButton.bounds toView:nil]);
    return MAX(0, CGRectGetMaxX(touchBar) - buttonCenter - kCloseButtonWidth / 2 - kItemSpacing);
}

#pragma mark - Actions

- (void)openPanel:(id)sender {
    CGFloat trailer = [self trailerWidth];        // measure before the strip is covered
    [_panel itemForIdentifier:kTrailerItemID];   // make sure the items exist
    _trailerWidth.constant = trailer;
    [self updateViews];
    [NSTouchBar presentSystemModalTouchBar:_panel placement:kFullWidthPlacement
                  systemTrayItemIdentifier:kStripItemID];
}

// "Minimize" returns to the Control Strip and keeps our button there; the
// "dismiss" call would remove the button as well.
- (void)closePanel:(id)sender {
    [NSTouchBar minimizeSystemModalTouchBar:_panel];
    [self reassertPresence];
}

- (void)sliderMoved:(NSSliderTouchBarItem *)item {
    [_backlight setLevel:(int)item.slider.integerValue fade:kSliderFadeMs];
}

#pragma mark - NSTouchBarDelegate

- (NSTouchBarItem *)touchBar:(NSTouchBar *)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier {
    if ([identifier isEqualToString:kSliderItemID]) {
        _sliderItem = [[NSSliderTouchBarItem alloc] initWithIdentifier:identifier];
        _sliderItem.slider.minValue = 0;               // 0 = off
        _sliderItem.slider.maxValue = 100;
        _sliderItem.slider.altIncrementValue = 10;     // step used by the end icons
        _sliderItem.slider.continuous = YES;
        _sliderItem.minimumValueAccessory = [NSSliderAccessory accessoryWithImage:Symbol(@"light.min", @"Dimmer")];
        _sliderItem.maximumValueAccessory = [NSSliderAccessory accessoryWithImage:Symbol(@"light.max", @"Brighter")];
        _sliderItem.minimumValueAccessory.behavior = NSSliderAccessoryBehavior.valueStepBehavior;
        _sliderItem.maximumValueAccessory.behavior = NSSliderAccessoryBehavior.valueStepBehavior;
        _sliderItem.valueAccessoryWidth = NSSliderAccessoryWidthWide;
        _sliderItem.minimumSliderWidth = kSliderWidth;
        _sliderItem.maximumSliderWidth = kSliderWidth;
        _sliderItem.target = self;
        _sliderItem.action = @selector(sliderMoved:);
        [self updateViews];
        return _sliderItem;
    }
    if ([identifier isEqualToString:kCloseItemID]) {
        NSButton *button = [NSButton buttonWithImage:CloseBoxImage() target:self action:@selector(closePanel:)];
        button.bordered = NO;
        [button.widthAnchor constraintEqualToConstant:kCloseButtonWidth].active = YES;
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        item.view = button;
        return item;
    }
    if ([identifier isEqualToString:kTrailerItemID]) {
        NSView *spacer = [NSView new];
        _trailerWidth = [spacer.widthAnchor constraintEqualToConstant:0];
        _trailerWidth.active = YES;
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        item.view = spacer;
        return item;
    }
    return nil;
}

@end
