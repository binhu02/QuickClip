#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface QCStatusImages : NSObject

+ (NSImage *)clipboardImage;
+ (NSImage *)lockImage;
+ (NSImage *)checkmarkImage;
+ (NSImage *)secureSnippetImage;
+ (NSImage *)groupImage;
+ (NSImage *)itemImage;
+ (NSImage *)separatorImage;

@end

NS_ASSUME_NONNULL_END
