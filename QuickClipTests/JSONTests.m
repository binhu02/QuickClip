#import <Foundation/Foundation.h>
#import "SnippetNode.h"
#import "QCErrors.h"

static int gFailures = 0;

static void QCAssert(BOOL condition, NSString *message) {
    if (!condition) {
        gFailures += 1;
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
    } else {
        fprintf(stdout, "ok: %s\n", message.UTF8String);
    }
}

int main(int argc, const char * argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        SnippetNode *email = [SnippetNode itemWithTitle:@"Email" text:@"example@umd.edu"];
        SnippetNode *secure = [SnippetNode secureItemWithTitle:@"API Key" identifier:@"550E8400-E29B-41D4-A716-446655440000"];
        secure.text = @"should-never-serialize";
        QCAssert(secure.text == nil, @"secure node rejects text assignment");

        SnippetNode *group = [SnippetNode groupWithTitle:@"Credentials" items:@[secure]];
        NSArray<SnippetNode *> *root = @[email, group, [SnippetNode separator]];

        NSError *error = nil;
        NSData *data = [SnippetNode JSONDataFromNodes:root error:&error];
        QCAssert(data != nil && error == nil, @"JSON serialization succeeds");

        NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        QCAssert([json containsString:@"\"type\" : \"secureItem\""] || [json containsString:@"\"type\":\"secureItem\""], @"secure item type is present");
        QCAssert(![json containsString:@"should-never-serialize"], @"secure secret is absent from JSON");
        QCAssert(![json containsString:@"example-password"], @"no credential example leaked");

        id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        NSArray *array = (NSArray *)object;
        NSDictionary *secureJSON = array[1][@"items"][0];
        QCAssert([secureJSON[@"type"] isEqualToString:@"secureItem"], @"nested secure item type");
        QCAssert(secureJSON[@"text"] == nil, @"nested secure item has no text key");
        QCAssert([secureJSON[@"id"] isEqualToString:@"550E8400-E29B-41D4-A716-446655440000"], @"UUID preserved");

        NSString *malformedSecure = @"[{\"type\":\"secureItem\",\"title\":\"X\"}]";
        NSData *malformedData = [malformedSecure dataUsingEncoding:NSUTF8StringEncoding];
        id malformedObject = [NSJSONSerialization JSONObjectWithData:malformedData options:0 error:nil];
        NSError *parseError = nil;
        NSArray *parsed = [SnippetNode nodesFromJSONObject:malformedObject error:&parseError];
        QCAssert(parsed == nil && parseError != nil, @"secureItem without id is a parse error");

        NSString *withText = @"[{\"type\":\"secureItem\",\"id\":\"ABC\",\"title\":\"X\",\"text\":\"LEAK\"}]";
        id withTextObject = [NSJSONSerialization JSONObjectWithData:[withText dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
        NSError *ignoreError = nil;
        NSArray<SnippetNode *> *stripped = [SnippetNode nodesFromJSONObject:withTextObject error:&ignoreError];
        QCAssert(stripped.count == 1, @"secureItem with unexpected text still loads");
        QCAssert(stripped[0].text == nil, @"unexpected text is not kept in the model");
        NSData *rewritten = [SnippetNode JSONDataFromNodes:stripped error:nil];
        NSString *rewrittenJSON = [[NSString alloc] initWithData:rewritten encoding:NSUTF8StringEncoding];
        QCAssert(![rewrittenJSON containsString:@"LEAK"], @"rewritten JSON does not contain the leaked text");

        NSString *bad = @"{not-json";
        NSError *jsonError = nil;
        id badObject = [NSJSONSerialization JSONObjectWithData:[bad dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&jsonError];
        QCAssert(badObject == nil && jsonError != nil, @"malformed JSON is reported by NSJSONSerialization");

        NSError *rootError = nil;
        NSArray *badRoot = [SnippetNode nodesFromJSONObject:@{@"type": @"item"} error:&rootError];
        QCAssert(badRoot == nil && rootError != nil, @"non-array root is a parse error");

        if (gFailures == 0) {
            fprintf(stdout, "All JSON tests passed.\n");
            return 0;
        }
        fprintf(stderr, "%d test(s) failed.\n", gFailures);
        return 1;
    }
}
