#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SnippetNodeType) {
    SnippetNodeTypeItem = 0,
    SnippetNodeTypeSecureItem,
    SnippetNodeTypeGroup,
    SnippetNodeTypeSeparator
};

@interface SnippetNode : NSObject

@property (nonatomic, assign) SnippetNodeType type;
@property (nonatomic, copy, nullable) NSString *identifier;
@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *text;
@property (nonatomic, copy, nullable) NSArray<SnippetNode *> *items;

+ (instancetype)itemWithTitle:(NSString *)title text:(NSString *)text;
+ (instancetype)secureItemWithTitle:(NSString *)title identifier:(NSString *)identifier;
+ (instancetype)groupWithTitle:(NSString *)title items:(nullable NSArray<SnippetNode *> *)items;
+ (instancetype)separator;

+ (nullable NSArray<SnippetNode *> *)nodesFromJSONObject:(id)object error:(NSError * _Nullable * _Nullable)error;
+ (NSArray *)JSONArrayFromNodes:(NSArray<SnippetNode *> *)nodes;
+ (nullable NSData *)JSONDataFromNodes:(NSArray<SnippetNode *> *)nodes error:(NSError * _Nullable * _Nullable)error;

- (NSDictionary<NSString *, id> *)JSONDictionary;
- (BOOL)isGroup;
- (BOOL)isSecureItem;
- (BOOL)isNormalItem;
- (NSString *)displayTitle;
- (NSArray<NSString *> *)allSecureSnippetIDs;
- (BOOL)containsDescendant:(SnippetNode *)node;
- (SnippetNode *)deepCopyNode;

@end

NS_ASSUME_NONNULL_END
