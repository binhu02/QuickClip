#import "QCStatusImages.h"

@implementation QCStatusImages

+ (NSImage *)symbolNamed:(NSString *)name accessibilityDescription:(NSString *)description {
    NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:description];
    if (image == nil) {
        image = [NSImage imageWithSystemSymbolName:@"questionmark.square" accessibilityDescription:description];
    }
    NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:13.0 weight:NSFontWeightMedium];
    NSImage *configured = [image imageWithSymbolConfiguration:config];
    if (configured != nil) {
        image = configured;
    }
    image.template = YES;
    return image;
}

+ (NSImage *)clipboardImage {
    NSImage *image = [self symbolNamed:@"doc.on.clipboard" accessibilityDescription:@"QuickClip"];
    if (image == nil) {
        image = [self symbolNamed:@"clipboard" accessibilityDescription:@"QuickClip"];
    }
    return image;
}

+ (NSImage *)lockImage {
    return [self symbolNamed:@"lock.fill" accessibilityDescription:@"QuickClip Locked"];
}

+ (NSImage *)checkmarkImage {
    return [self symbolNamed:@"checkmark" accessibilityDescription:@"Copied"];
}

+ (NSImage *)secureSnippetImage {
    return [self symbolNamed:@"lock.fill" accessibilityDescription:@"Secure snippet"];
}

+ (NSImage *)groupImage {
    return [self symbolNamed:@"folder" accessibilityDescription:@"Group"];
}

+ (NSImage *)itemImage {
    return [self symbolNamed:@"doc" accessibilityDescription:@"Snippet"];
}

+ (NSImage *)separatorImage {
    return [self symbolNamed:@"minus" accessibilityDescription:@"Separator"];
}

@end
