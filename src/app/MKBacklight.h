// MKBacklight — the app's single source of truth for the keyboard backlight.
//
// Wraps backlight.h: owns the HID device, keeps the state in sync with the
// shared state file (so changes from the CLI or other users show up), and
// posts MKBacklightDidChangeNotification whenever the state changes.
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const MKBacklightDidChangeNotification;

@interface MKBacklight : NSObject

@property (nonatomic, readonly, getter=isOn) BOOL on;
@property (nonatomic, readonly) int level;                         // 1-100, kept while off
@property (nonatomic, readonly, getter=isAvailable) BOOL available;  // backlight device found

// Turns the light on at `level` (1-100), or off when `level` is 0.
- (void)setLevel:(int)level fade:(uint32_t)fadeMs;
- (void)setOn:(BOOL)on fade:(uint32_t)fadeMs;

@end

NS_ASSUME_NONNULL_END
