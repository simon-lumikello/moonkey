#import "MKBacklight.h"
#include "backlight.h"

NSNotificationName const MKBacklightDidChangeNotification = @"MKBacklightDidChangeNotification";

static const NSTimeInterval kStatePollInterval = 2.0;

@implementation MKBacklight {
    IOHIDDeviceRef _device;
    bl_state _state;
    double _stateMTime;
}

- (instancetype)init {
    if ((self = [super init])) {
        _state = bl_load();
        _stateMTime = bl_state_mtime();
        _device = bl_open();

        // Follow changes made by the CLI or another user's session.
        [NSTimer scheduledTimerWithTimeInterval:kStatePollInterval repeats:YES
                                          block:^(NSTimer *timer) { [self reloadIfChanged]; }];
    }
    return self;
}

- (void)dealloc {
    if (_device) CFRelease(_device);
}

- (BOOL)isOn       { return _state.on; }
- (int)level       { return _state.level; }
- (BOOL)isAvailable { return _device != NULL; }

- (void)setLevel:(int)level fade:(uint32_t)fadeMs {
    bl_state next = _state;
    if (level <= 0) next.on = false;
    else { next.on = true; next.level = bl_clamp_level(level); }
    [self apply:next fade:fadeMs];
}

- (void)setOn:(BOOL)on fade:(uint32_t)fadeMs {
    bl_state next = _state;
    next.on = on;
    [self apply:next fade:fadeMs];
}

#pragma mark - Private

- (void)apply:(bl_state)next fade:(uint32_t)fadeMs {
    if (next.on == _state.on && next.level == _state.level) return;
    _state = next;

    // Reopen the device once if the cached handle went stale (e.g. after wake).
    if (!_device || bl_apply(_device, _state, fadeMs) != kIOReturnSuccess) {
        if (_device) CFRelease(_device);
        _device = bl_open();
        if (_device) bl_apply(_device, _state, fadeMs);
    }
    bl_save(_state);
    _stateMTime = bl_state_mtime();
    [self postChange];
}

- (void)reloadIfChanged {
    double mtime = bl_state_mtime();
    if (mtime == _stateMTime) return;
    _stateMTime = mtime;
    _state = bl_load();
    [self postChange];
}

- (void)postChange {
    [NSNotificationCenter.defaultCenter postNotificationName:MKBacklightDidChangeNotification object:self];
}

@end
