#import "SnippetNode.h"
#import "QCErrors.h"

@implementation SnippetNode

+ (instancetype)itemWithTitle:(NSString *)title text:(NSString *)text {
    SnippetNode *node = [[SnippetNode alloc] init];
    node.type = SnippetNodeTypeItem;
    node.identifier = [[NSUUID UUID] UUIDString];
    node.title = title;
    node.text = text ?: @"";
    return node;
}

+ (instancetype)secureItemWithTitle:(NSString *)title identifier:(NSString *)identifier {
    SnippetNode *node = [[SnippetNode alloc] init];
    node.type = SnippetNodeTypeSecureItem;
    node.identifier = identifier.length > 0 ? identifier : [[NSUUID UUID] UUIDString];
    node.title = title;
    node.text = nil;
    return node;
}

+ (instancetype)groupWithTitle:(NSString *)title items:(NSArray<SnippetNode *> *)items {
    SnippetNode *node = [[SnippetNode alloc] init];
    node.type = SnippetNodeTypeGroup;
    node.title = title;
    node.items = items ?: @[];
    return node;
}

+ (instancetype)separator {
    SnippetNode *node = [[SnippetNode alloc] init];
    node.type = SnippetNodeTypeSeparator;
    return node;
}

- (BOOL)isGroup {
    return self.type == SnippetNodeTypeGroup;
}

- (BOOL)isSecureItem {
    return self.type == SnippetNodeTypeSecureItem;
}

- (BOOL)isNormalItem {
    return self.type == SnippetNodeTypeItem;
}

- (NSString *)displayTitle {
    switch (self.type) {
        case SnippetNodeTypeSeparator:
            return @"Separator";
        case SnippetNodeTypeGroup:
            return self.title.length > 0 ? self.title : @"Untitled Group";
        default:
            return self.title.length > 0 ? self.title : @"Untitled";
    }
}

- (void)setText:(NSString *)text {
    if (self.type == SnippetNodeTypeSecureItem) {
        _text = nil;
        return;
    }
    _text = [text copy];
}

- (void)setType:(SnippetNodeType)type {
    _type = type;
    if (type == SnippetNodeTypeSecureItem) {
        _text = nil;
    }
}

- (NSArray<NSString *> *)allSecureSnippetIDs {
    NSMutableArray<NSString *> *ids = [NSMutableArray array];
    [self collectSecureSnippetIDs:ids];
    return ids;
}

- (BOOL)containsDescendant:(SnippetNode *)node {
    if (node == nil || self.type != SnippetNodeTypeGroup) {
        return NO;
    }
    for (SnippetNode *child in self.items) {
        if (child == node || [child containsDescendant:node]) {
            return YES;
        }
    }
    return NO;
}

- (void)collectSecureSnippetIDs:(NSMutableArray<NSString *> *)ids {
    if (self.type == SnippetNodeTypeSecureItem && self.identifier.length > 0) {
        [ids addObject:self.identifier];
    }
    for (SnippetNode *child in self.items) {
        [child collectSecureSnippetIDs:ids];
    }
}

- (SnippetNode *)deepCopyNode {
    SnippetNode *copy = [[SnippetNode alloc] init];
    copy.type = self.type;
    copy.identifier = self.identifier;
    copy.title = self.title;
    if (self.type != SnippetNodeTypeSecureItem) {
        copy.text = self.text;
    }
    if (self.items != nil) {
        NSMutableArray<SnippetNode *> *children = [NSMutableArray arrayWithCapacity:self.items.count];
        for (SnippetNode *child in self.items) {
            [children addObject:[child deepCopyNode]];
        }
        copy.items = children;
    }
    return copy;
}

- (NSDictionary<NSString *, id> *)JSONDictionary {
    switch (self.type) {
        case SnippetNodeTypeItem: {
            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            dict[@"type"] = @"item";
            dict[@"id"] = self.identifier.length > 0 ? self.identifier : [[NSUUID UUID] UUIDString];
            dict[@"title"] = self.title ?: @"";
            dict[@"text"] = self.text ?: @"";
            return dict;
        }
        case SnippetNodeTypeSecureItem: {
            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            dict[@"type"] = @"secureItem";
            dict[@"id"] = self.identifier.length > 0 ? self.identifier : [[NSUUID UUID] UUIDString];
            dict[@"title"] = self.title ?: @"";
            // Intentionally never serializes a secret "text" field.
            return dict;
        }
        case SnippetNodeTypeGroup: {
            NSMutableDictionary *dict = [NSMutableDictionary dictionary];
            dict[@"type"] = @"group";
            dict[@"title"] = self.title ?: @"";
            dict[@"items"] = [SnippetNode JSONArrayFromNodes:self.items ?: @[]];
            return dict;
        }
        case SnippetNodeTypeSeparator:
            return @{@"type": @"separator"};
    }
    return @{@"type": @"separator"};
}

+ (NSArray *)JSONArrayFromNodes:(NSArray<SnippetNode *> *)nodes {
    NSMutableArray *array = [NSMutableArray arrayWithCapacity:nodes.count];
    for (SnippetNode *node in nodes) {
        [array addObject:[node JSONDictionary]];
    }
    return array;
}

+ (NSData *)JSONDataFromNodes:(NSArray<SnippetNode *> *)nodes error:(NSError **)error {
    NSArray *jsonObject = [self JSONArrayFromNodes:nodes];
    if (![self validateNoSecretsInJSONObject:jsonObject error:error]) {
        return nil;
    }
    NSError *serializationError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:jsonObject
                                                   options:(NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys)
                                                     error:&serializationError];
    if (data == nil) {
        if (error != NULL) {
            *error = [QCErrors errorWithCode:QCErrorCodeJSONWriteFailed
                                 description:@"Couldn’t serialize snippets.json."
                                  underlying:serializationError];
        }
        return nil;
    }
    return data;
}

+ (BOOL)validateNoSecretsInJSONObject:(id)object error:(NSError **)error {
    if ([object isKindOfClass:[NSArray class]]) {
        for (id child in (NSArray *)object) {
            if (![self validateNoSecretsInJSONObject:child error:error]) {
                return NO;
            }
        }
        return YES;
    }
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)object;
        NSString *type = dict[@"type"];
        if ([type isEqualToString:@"secureItem"] && dict[@"text"] != nil) {
            if (error != NULL) {
                *error = [QCErrors errorWithCode:QCErrorCodeJSONWriteFailed
                                     description:@"Refusing to write a Secure Snippet that contains a plaintext “text” field."];
            }
            return NO;
        }
        id items = dict[@"items"];
        if (items != nil) {
            return [self validateNoSecretsInJSONObject:items error:error];
        }
    }
    return YES;
}

+ (NSArray<SnippetNode *> *)nodesFromJSONObject:(id)object error:(NSError **)error {
    if (![object isKindOfClass:[NSArray class]]) {
        if (error != NULL) {
            *error = [QCErrors jsonErrorAtPath:@"<root>" reason:@"the file must contain a JSON array"];
        }
        return nil;
    }
    return [self nodesFromArray:(NSArray *)object path:@"<root>" error:error];
}

+ (NSArray<SnippetNode *> *)nodesFromArray:(NSArray *)array path:(NSString *)path error:(NSError **)error {
    NSMutableArray<SnippetNode *> *nodes = [NSMutableArray arrayWithCapacity:array.count];
    NSUInteger index = 0;
    for (id entry in array) {
        NSString *childPath = [NSString stringWithFormat:@"%@[%lu]", path, (unsigned long)index];
        SnippetNode *node = [self nodeFromObject:entry path:childPath error:error];
        if (node == nil) {
            return nil;
        }
        [nodes addObject:node];
        index += 1;
    }
    return nodes;
}

+ (SnippetNode *)nodeFromObject:(id)object path:(NSString *)path error:(NSError **)error {
    if (![object isKindOfClass:[NSDictionary class]]) {
        if (error != NULL) {
            *error = [QCErrors jsonErrorAtPath:path reason:@"expected a JSON object"];
        }
        return nil;
    }
    NSDictionary *dict = (NSDictionary *)object;
    id typeValue = dict[@"type"];
    if (![typeValue isKindOfClass:[NSString class]]) {
        if (error != NULL) {
            *error = [QCErrors jsonErrorAtPath:path reason:@"missing or invalid “type” string"];
        }
        return nil;
    }
    NSString *type = (NSString *)typeValue;

    if ([type isEqualToString:@"item"]) {
        SnippetNode *node = [[SnippetNode alloc] init];
        node.type = SnippetNodeTypeItem;
        node.identifier = [self stringValue:dict[@"id"]] ?: [[NSUUID UUID] UUIDString];
        node.title = [self stringValue:dict[@"title"]] ?: @"";
        node.text = [self stringValue:dict[@"text"]] ?: @"";
        return node;
    }

    if ([type isEqualToString:@"secureItem"]) {
        NSString *identifier = [self stringValue:dict[@"id"]];
        if (identifier.length == 0) {
            if (error != NULL) {
                *error = [QCErrors jsonErrorAtPath:path reason:@"secureItem is missing required “id”"];
            }
            return nil;
        }
        if (dict[@"text"] != nil) {
            NSLog(@"QuickClip: ignoring unexpected “text” field on secureItem %@", identifier);
        }
        SnippetNode *node = [[SnippetNode alloc] init];
        node.type = SnippetNodeTypeSecureItem;
        node.identifier = identifier;
        node.title = [self stringValue:dict[@"title"]] ?: @"";
        node.text = nil;
        return node;
    }

    if ([type isEqualToString:@"group"]) {
        id itemsValue = dict[@"items"];
        if (itemsValue == nil) {
            itemsValue = @[];
        }
        if (![itemsValue isKindOfClass:[NSArray class]]) {
            if (error != NULL) {
                *error = [QCErrors jsonErrorAtPath:path reason:@"group “items” must be an array"];
            }
            return nil;
        }
        NSString *itemsPath = [path stringByAppendingString:@".items"];
        NSArray<SnippetNode *> *children = [self nodesFromArray:(NSArray *)itemsValue path:itemsPath error:error];
        if (children == nil) {
            return nil;
        }
        SnippetNode *node = [[SnippetNode alloc] init];
        node.type = SnippetNodeTypeGroup;
        node.title = [self stringValue:dict[@"title"]] ?: @"";
        node.items = children;
        return node;
    }

    if ([type isEqualToString:@"separator"]) {
        return [SnippetNode separator];
    }

    if (error != NULL) {
        *error = [QCErrors jsonErrorAtPath:path
                                    reason:[NSString stringWithFormat:@"unknown type “%@”", type]];
    }
    return nil;
}

+ (NSString *)stringValue:(id)value {
    if ([value isKindOfClass:[NSString class]]) {
        return (NSString *)value;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value stringValue];
    }
    return nil;
}

@end
