// MKTouchBarController — Control Strip button that opens a brightness slider
// laid out like the system volume control.
#import <Foundation/Foundation.h>

@class MKBacklight;

NS_ASSUME_NONNULL_BEGIN

@interface MKTouchBarController : NSObject

// YES if this Mac has a Touch Bar and the private Control Strip APIs exist.
+ (BOOL)isSupported;

- (instancetype)initWithBacklight:(MKBacklight *)backlight NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, getter=isVisible) BOOL visible;

@end

NS_ASSUME_NONNULL_END
