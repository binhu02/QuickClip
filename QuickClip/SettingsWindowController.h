#import <AppKit/AppKit.h>

@class LoginItemManager;

NS_ASSUME_NONNULL_BEGIN

@interface SettingsWindowController : NSWindowController

- (instancetype)initWithLoginItemManager:(LoginItemManager *)loginItemManager NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithWindow:(nullable NSWindow *)window NS_UNAVAILABLE;
- (instancetype)initWithCoder:(NSCoder *)coder NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

- (void)show;

@end

NS_ASSUME_NONNULL_END
