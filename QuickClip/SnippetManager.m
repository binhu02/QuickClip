#import "SnippetManager.h"
#import "QCErrors.h"

NSNotificationName const QCSnippetsDidChangeNotification = @"QCSnippetsDidChangeNotification";

@interface SnippetManager ()
@property (nonatomic, copy, readwrite) NSArray<SnippetNode *> *rootNodes;
@property (nonatomic, assign, readwrite) BOOL hasLoadedSuccessfully;
@property (nonatomic, strong) NSURL *directoryURL;
@property (nonatomic, strong) NSURL *snippetsFileURL;
@end

@implementation SnippetManager

- (instancetype)init {
    self = [super init];
    if (self != nil) {
        _rootNodes = @[];
        NSError *error = nil;
        NSURL *appSupport = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory
                                                                   inDomain:NSUserDomainMask
                                                          appropriateForURL:nil
                                                                     create:YES
                                                                      error:&error];
        if (appSupport != nil) {
            _directoryURL = [appSupport URLByAppendingPathComponent:@"QuickClip" isDirectory:YES];
            _snippetsFileURL = [_directoryURL URLByAppendingPathComponent:@"snippets.json" isDirectory:NO];
        }
    }
    return self;
}

- (BOOL)ensureDirectoryWithError:(NSError **)error {
    if (self.directoryURL == nil) {
        if (error != NULL) {
            *error = [QCErrors errorWithCode:QCErrorCodeJSONWriteFailed
                                 description:@"Couldn’t locate the Application Support directory."];
        }
        return NO;
    }
    NSError *createError = nil;
    BOOL ok = [[NSFileManager defaultManager] createDirectoryAtURL:self.directoryURL
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:&createError];
    if (!ok && error != NULL) {
        *error = [QCErrors errorWithCode:QCErrorCodeJSONWriteFailed
                             description:@"Couldn’t create the QuickClip Application Support directory."
                              underlying:createError];
    }
    return ok;
}

- (NSArray<SnippetNode *> *)defaultNodes {
    return @[
        [SnippetNode itemWithTitle:@"Email" text:@"example@umd.edu"],
        [SnippetNode itemWithTitle:@"Phone" text:@"(555) 010-1234"],
        [SnippetNode itemWithTitle:@"Website" text:@"https://example.com"],
        [SnippetNode separator],
        [SnippetNode groupWithTitle:@"Addresses" items:@[
            [SnippetNode itemWithTitle:@"Work" text:@"123 Main Street, College Park, MD 20742"]
        ]]
    ];
}

- (BOOL)loadAndCreateIfNeededWithError:(NSError **)error {
    if (![self ensureDirectoryWithError:error]) {
        return NO;
    }

    BOOL isDirectory = NO;
    BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:self.snippetsFileURL.path isDirectory:&isDirectory];
    if (!exists) {
        self.rootNodes = [self defaultNodes];
        if (![self saveWithError:error]) {
            return NO;
        }
        self.hasLoadedSuccessfully = YES;
        return YES;
    }
    if (isDirectory) {
        if (error != NULL) {
            *error = [QCErrors errorWithCode:QCErrorCodeJSONMalformed
                                 description:@"snippets.json exists but is a directory."];
        }
        return NO;
    }
    return [self reloadWithError:error];
}

- (BOOL)reloadWithError:(NSError **)error {
    if (self.snippetsFileURL == nil) {
        if (error != NULL) {
            *error = [QCErrors errorWithCode:QCErrorCodeJSONMalformed
                                 description:@"snippets.json path is unavailable."];
        }
        return NO;
    }

    NSError *readError = nil;
    NSData *data = [NSData dataWithContentsOfURL:self.snippetsFileURL options:0 error:&readError];
    if (data == nil) {
        if (error != NULL) {
            *error = [QCErrors errorWithCode:QCErrorCodeJSONMalformed
                                 description:@"Couldn’t read snippets.json."
                                  underlying:readError];
        }
        return NO;
    }

    NSError *jsonError = nil;
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (object == nil) {
        if (error != NULL) {
            NSString *reason = jsonError.localizedDescription ?: @"the file is not valid JSON";
            *error = [QCErrors jsonErrorAtPath:@"<root>" reason:reason];
        }
        return NO;
    }

    NSError *parseError = nil;
    NSArray<SnippetNode *> *nodes = [SnippetNode nodesFromJSONObject:object error:&parseError];
    if (nodes == nil) {
        if (error != NULL) {
            *error = parseError;
        }
        return NO;
    }

    self.rootNodes = nodes;
    self.hasLoadedSuccessfully = YES;
    return YES;
}

- (BOOL)saveWithError:(NSError **)error {
    if (![self ensureDirectoryWithError:error]) {
        return NO;
    }
    NSError *dataError = nil;
    NSData *data = [SnippetNode JSONDataFromNodes:self.rootNodes error:&dataError];
    if (data == nil) {
        if (error != NULL) {
            *error = dataError;
        }
        return NO;
    }
    NSError *writeError = nil;
    BOOL ok = [data writeToURL:self.snippetsFileURL options:NSDataWritingAtomic error:&writeError];
    if (!ok) {
        if (error != NULL) {
            *error = [QCErrors errorWithCode:QCErrorCodeJSONWriteFailed
                                 description:@"Couldn’t write snippets.json."
                                  underlying:writeError];
        }
        return NO;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:QCSnippetsDidChangeNotification object:self];
    return YES;
}

- (void)replaceRootNodes:(NSArray<SnippetNode *> *)nodes {
    self.rootNodes = nodes ?: @[];
}

- (NSMutableArray<SnippetNode *> *)mutableRootNodes {
    return [NSMutableArray arrayWithArray:self.rootNodes ?: @[]];
}

- (void)commitRootNodes:(NSArray<SnippetNode *> *)nodes {
    self.rootNodes = [nodes copy];
}

- (void)insertNode:(SnippetNode *)node parent:(SnippetNode *)parent atIndex:(NSUInteger)index {
    if (node == nil) {
        return;
    }
    if (parent != nil && parent.type == SnippetNodeTypeGroup) {
        NSMutableArray<SnippetNode *> *items = [NSMutableArray arrayWithArray:parent.items ?: @[]];
        NSUInteger clamped = MIN(index, items.count);
        [items insertObject:node atIndex:clamped];
        parent.items = items;
        self.rootNodes = [self.rootNodes copy];
        return;
    }
    NSMutableArray<SnippetNode *> *root = [self mutableRootNodes];
    NSUInteger clamped = MIN(index, root.count);
    [root insertObject:node atIndex:clamped];
    [self commitRootNodes:root];
}

- (BOOL)removeNode:(SnippetNode *)node {
    SnippetNode *parent = nil;
    NSMutableArray<SnippetNode *> *array = [self mutableArrayContainingNode:node parent:&parent];
    if (array == nil) {
        return NO;
    }
    [array removeObject:node];
    if (parent != nil) {
        parent.items = array;
        self.rootNodes = [self.rootNodes copy];
    } else {
        [self commitRootNodes:array];
    }
    return YES;
}

- (BOOL)moveNode:(SnippetNode *)node toParent:(SnippetNode *)parent atIndex:(NSUInteger)index {
    if (node == nil) {
        return NO;
    }
    if (parent != nil && parent.type != SnippetNodeTypeGroup) {
        return NO;
    }
    if (node == parent || [node containsDescendant:parent]) {
        return NO;
    }

    SnippetNode *oldParent = [self parentOfNode:node];
    NSArray<SnippetNode *> *oldSiblings = oldParent != nil ? oldParent.items : self.rootNodes;
    NSUInteger oldIndex = [oldSiblings indexOfObject:node];
    if (oldIndex == NSNotFound) {
        return NO;
    }

    BOOL sameParent = (oldParent == parent);
    if (sameParent) {
        NSUInteger dest = MIN(index, oldSiblings.count);
        if (dest == oldIndex || dest == oldIndex + 1) {
            return NO;
        }
        NSMutableArray<SnippetNode *> *array = [NSMutableArray arrayWithArray:oldSiblings];
        [array removeObjectAtIndex:oldIndex];
        if (oldIndex < dest) {
            dest -= 1;
        }
        dest = MIN(dest, array.count);
        [array insertObject:node atIndex:dest];
        if (parent != nil) {
            parent.items = array;
            self.rootNodes = [self.rootNodes copy];
        } else {
            [self commitRootNodes:array];
        }
        return YES;
    }

    if (![self removeNode:node]) {
        return NO;
    }
    [self insertNode:node parent:parent atIndex:index];
    return YES;
}

- (SnippetNode *)parentOfNode:(SnippetNode *)node {
    SnippetNode *parent = nil;
    [self mutableArrayContainingNode:node parent:&parent];
    return parent;
}

- (NSMutableArray<SnippetNode *> *)mutableArrayContainingNode:(SnippetNode *)node
                                                       parent:(SnippetNode **)outParent {
    if (outParent != NULL) {
        *outParent = nil;
    }
    if (node == nil) {
        return nil;
    }
    NSUInteger rootIndex = [self.rootNodes indexOfObject:node];
    if (rootIndex != NSNotFound) {
        return [self mutableRootNodes];
    }
    return [self searchArray:self.rootNodes parent:nil forNode:node outParent:outParent];
}

- (NSMutableArray<SnippetNode *> *)searchArray:(NSArray<SnippetNode *> *)array
                                        parent:(SnippetNode *)parent
                                       forNode:(SnippetNode *)node
                                     outParent:(SnippetNode **)outParent {
    (void)parent;
    for (SnippetNode *candidate in array) {
        if (candidate.type == SnippetNodeTypeGroup) {
            NSUInteger index = [candidate.items indexOfObject:node];
            if (index != NSNotFound) {
                if (outParent != NULL) {
                    *outParent = candidate;
                }
                return [NSMutableArray arrayWithArray:candidate.items ?: @[]];
            }
            NSMutableArray<SnippetNode *> *found = [self searchArray:candidate.items
                                                              parent:candidate
                                                             forNode:node
                                                           outParent:outParent];
            if (found != nil) {
                return found;
            }
        }
    }
    return nil;
}

- (NSArray<NSString *> *)allSecureSnippetIDs {
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    for (SnippetNode *node in self.rootNodes) {
        [ids addObjectsFromArray:[node allSecureSnippetIDs]];
    }
    return ids;
}

- (BOOL)hasSecureSnippets {
    return self.allSecureSnippetIDs.count > 0;
}

@end
