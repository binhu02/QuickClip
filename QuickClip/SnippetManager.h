#import <Foundation/Foundation.h>
#import "SnippetNode.h"

NS_ASSUME_NONNULL_BEGIN

extern NSNotificationName const QCSnippetsDidChangeNotification;

@interface SnippetManager : NSObject

@property (nonatomic, readonly) NSURL *directoryURL;
@property (nonatomic, readonly) NSURL *snippetsFileURL;
@property (nonatomic, readonly, copy) NSArray<SnippetNode *> *rootNodes;
@property (nonatomic, readonly) BOOL hasLoadedSuccessfully;

- (BOOL)loadAndCreateIfNeededWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)reloadWithError:(NSError * _Nullable * _Nullable)error;
- (BOOL)saveWithError:(NSError * _Nullable * _Nullable)error;

- (void)replaceRootNodes:(NSArray<SnippetNode *> *)nodes;
- (void)insertNode:(SnippetNode *)node parent:(nullable SnippetNode *)parent atIndex:(NSUInteger)index;
- (BOOL)removeNode:(SnippetNode *)node;
- (BOOL)moveNode:(SnippetNode *)node toParent:(nullable SnippetNode *)parent atIndex:(NSUInteger)index;
- (nullable SnippetNode *)parentOfNode:(SnippetNode *)node;
- (NSMutableArray<SnippetNode *> *)mutableArrayContainingNode:(SnippetNode *)node
                                                       parent:(SnippetNode * _Nullable * _Nullable)outParent;
- (NSArray<NSString *> *)allSecureSnippetIDs;
- (BOOL)hasSecureSnippets;

@end

NS_ASSUME_NONNULL_END
