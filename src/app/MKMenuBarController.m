#import "MKMenuBarController.h"
#import "MKBacklight.h"
#import <AppKit/AppKit.h>

static const CGFloat kMenuWidth     = 300;
static const CGFloat kSideInset     = 14;   // matches standard menu item text inset
static const uint32_t kSliderFadeMs = 64;
static const uint32_t kToggleFadeMs = 500;

static NSImage *Symbol(NSString *name, NSString *description) {
    return [NSImage imageWithSystemSymbolName:name accessibilityDescription:description];
}

static NSImageView *IconView(NSString *symbol, NSString *description) {
    NSImageView *view = [NSImageView imageViewWithImage:Symbol(symbol, description)];
    view.contentTintColor = NSColor.secondaryLabelColor;
    [view setContentHuggingPriority:NSLayoutPriorityRequired forOrientation:NSLayoutConstraintOrientationHorizontal];
    return view;
}

@interface MKMenuBarController () <NSMenuDelegate>
@end

@implementation MKMenuBarController {
    MKBacklight *_backlight;
    NSStatusItem *_statusItem;
    NSMenu *_menu;
    NSView *_sectionContainer;
    NSStackView *_section;
    NSSlider *_slider;
    NSTextField *_unavailableLabel;
    NSMenuItem *_toggleItem;
}

- (instancetype)initWithBacklight:(MKBacklight *)backlight {
    if ((self = [super init])) {
        _backlight = backlight;
        _menu = [self buildMenu];
        _menu.delegate = self;
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateViews)
                                                   name:MKBacklightDidChangeNotification object:backlight];
    }
    return self;
}

- (void)setVisible:(BOOL)visible {
    if (visible == _visible) return;
    _visible = visible;
    if (visible) {
        _statusItem = [NSStatusBar.systemStatusBar statusItemWithLength:NSSquareStatusItemLength];
        _statusItem.menu = _menu;
        _statusItem.button.toolTip = @"Keyboard Brightness";
        [self updateViews];
    } else {
        [NSStatusBar.systemStatusBar removeStatusItem:_statusItem];
        _statusItem = nil;
    }
}

#pragma mark - Menu

- (NSMenu *)buildMenu {
    NSMenu *menu = [NSMenu new];
    menu.autoenablesItems = NO;   // updateViews sets enabled state itself

    NSMenuItem *sliderItem = [NSMenuItem new];
    sliderItem.view = [self buildSliderSection];
    [menu addItem:sliderItem];

    [menu addItem:NSMenuItem.separatorItem];

    _toggleItem = [[NSMenuItem alloc] initWithTitle:@"Backlight On" action:@selector(toggle:) keyEquivalent:@""];
    _toggleItem.target = self;
    [menu addItem:_toggleItem];

    return menu;
}

// "Keyboard Brightness" title over a dim-icon / slider / bright-icon row.
- (NSView *)buildSliderSection {
    NSTextField *title = [NSTextField labelWithString:@"Keyboard Brightness"];
    title.font = [NSFont systemFontOfSize:NSFont.systemFontSize weight:NSFontWeightSemibold];

    _slider = [NSSlider sliderWithValue:0 minValue:0 maxValue:100 target:self action:@selector(sliderMoved:)];
    _slider.continuous = YES;

    NSStackView *row = [NSStackView stackViewWithViews:@[IconView(@"light.min", @"Dimmer"), _slider,
                                                          IconView(@"light.max", @"Brighter")]];
    row.spacing = 8;

    _unavailableLabel = [NSTextField wrappingLabelWithString:
        @"Keyboard backlight not found. This Mac model isn't supported yet."];
    _unavailableLabel.textColor = NSColor.secondaryLabelColor;
    _unavailableLabel.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];

    _section = [NSStackView stackViewWithViews:@[title, row, _unavailableLabel]];
    _section.orientation = NSUserInterfaceLayoutOrientationVertical;
    _section.alignment = NSLayoutAttributeLeading;
    _section.spacing = 8;
    _section.edgeInsets = NSEdgeInsetsMake(8, kSideInset, 8, kSideInset);
    _section.translatesAutoresizingMaskIntoConstraints = NO;
    [row.widthAnchor constraintEqualToConstant:kMenuWidth - 2 * kSideInset].active = YES;
    [_unavailableLabel.widthAnchor constraintEqualToConstant:kMenuWidth - 2 * kSideInset].active = YES;

    // Menus size item views by their frame, not Auto Layout, so the container
    // keeps a plain frame that -sizeSectionToFit sets from the content.
    _sectionContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kMenuWidth, 0)];
    [_sectionContainer addSubview:_section];
    [NSLayoutConstraint activateConstraints:@[
        [_section.leadingAnchor constraintEqualToAnchor:_sectionContainer.leadingAnchor],
        [_section.trailingAnchor constraintEqualToAnchor:_sectionContainer.trailingAnchor],
        [_section.topAnchor constraintEqualToAnchor:_sectionContainer.topAnchor],
    ]];
    return _sectionContainer;
}

- (void)sizeSectionToFit {
    [_sectionContainer setFrameSize:NSMakeSize(kMenuWidth, _section.fittingSize.height)];
}

- (void)menuWillOpen:(NSMenu *)menu {
    [self updateViews];
}

- (void)updateViews {
    BOOL available = _backlight.available;
    _statusItem.button.image = _backlight.on ? Symbol(@"light.max", @"Keyboard backlight on")
                                             : Symbol(@"light.min", @"Keyboard backlight off");
    _slider.integerValue = _backlight.on ? _backlight.level : 0;
    _slider.enabled = available;
    _unavailableLabel.hidden = available;
    [self sizeSectionToFit];
    _toggleItem.state = _backlight.on ? NSControlStateValueOn : NSControlStateValueOff;
    _toggleItem.enabled = available;
}

#pragma mark - Actions

- (void)sliderMoved:(NSSlider *)slider {
    [_backlight setLevel:(int)slider.integerValue fade:kSliderFadeMs];
}

- (void)toggle:(id)sender {
    [_backlight setOn:!_backlight.on fade:kToggleFadeMs];
}

@end
