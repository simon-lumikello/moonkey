// MKMenuBarController — menu bar icon whose dropdown holds a brightness
// slider styled like a Control Center section, plus an on/off item.
#import <Foundation/Foundation.h>

@class MKBacklight;

NS_ASSUME_NONNULL_BEGIN

@interface MKMenuBarController : NSObject

- (instancetype)initWithBacklight:(MKBacklight *)backlight NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, getter=isVisible) BOOL visible;

@end

NS_ASSUME_NONNULL_END
