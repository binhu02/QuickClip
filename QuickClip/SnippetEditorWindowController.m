#import "SnippetEditorWindowController.h"
#import "SnippetManager.h"
#import "SecureSnippetStore.h"
#import "SecureAuthenticationManager.h"
#import "AuthenticationManager.h"
#import "QCStatusImages.h"
#import "QCErrors.h"
#import <LocalAuthentication/LocalAuthentication.h>
#import <Security/Security.h>

static NSPasteboardType const QCSnippetDragType = @"com.quickclip.QuickClip.snippet-drag";

@interface SnippetEditorWindowController () <NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate, NSWindowDelegate, NSSplitViewDelegate>
@property (nonatomic, strong) SnippetManager *snippetManager;
@property (nonatomic, strong) SecureSnippetStore *secureStore;
@property (nonatomic, strong) SecureAuthenticationManager *secureAuth;
@property (nonatomic, strong) AuthenticationManager *authenticationManager;

@property (nonatomic, strong) NSSplitView *splitView;
@property (nonatomic, strong) NSOutlineView *outlineView;
@property (nonatomic, strong, nullable) SnippetNode *draggedNode;
@property (nonatomic, strong) NSView *detailContainer;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *titleField;
@property (nonatomic, strong) NSTextField *valueLabel;
@property (nonatomic, strong) NSTextView *valueView;
@property (nonatomic, strong) NSScrollView *valueScroll;
@property (nonatomic, strong) NSButton *secureCheckbox;
@property (nonatomic, strong) NSSecureTextField *secretField;
@property (nonatomic, strong) NSButton *revealButton;
@property (nonatomic, strong) NSButton *saveButton;
@property (nonatomic, strong) NSStackView *revealRow;
@property (nonatomic, strong) NSStackView *saveRow;
@property (nonatomic, strong) NSTextField *placeholderLabel;
@property (nonatomic, strong) NSTextField *pendingHintLabel;
@property (nonatomic, strong) NSTextField *keychainHintLabel;
@property (nonatomic, strong) NSTextField *dragPromptLabel;
@property (nonatomic, strong) NSProgressIndicator *spinner;
@property (nonatomic, assign) CGFloat leftControlsWidth;

@property (nonatomic, weak) SnippetNode *displayedNode;
@property (nonatomic, assign) BOOL secretLoaded;
@property (nonatomic, assign) BOOL secretDirty;
@property (nonatomic, assign) BOOL isNewUnsavedSecureItem;
@property (nonatomic, assign) BOOL pendingConvertToSecure;
@property (nonatomic, assign) BOOL suppressDetailSync;
@end

@implementation SnippetEditorWindowController

- (instancetype)initWithSnippetManager:(SnippetManager *)snippetManager
                            secureStore:(SecureSnippetStore *)secureStore
                              secureAuth:(SecureAuthenticationManager *)secureAuth
                  authenticationManager:(AuthenticationManager *)authenticationManager {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 820, 520)
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                              NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskResizable |
                                                              NSWindowStyleMaskMiniaturizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Edit Snippets";
    window.releasedWhenClosed = NO;
    window.hidesOnDeactivate = NO;
    window.restorable = NO;
    window.level = NSFloatingWindowLevel;
    window.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace | NSWindowCollectionBehaviorFullScreenAuxiliary;
    self = [super initWithWindow:window];
    if (self != nil) {
        _snippetManager = snippetManager;
        _secureStore = secureStore;
        _secureAuth = secureAuth;
        _authenticationManager = authenticationManager;
        window.delegate = self;
        [self buildUI];
        [self sizeWindowToContent];
    }
    return self;
}

- (void)sizeWindowToContent {
    CGFloat leftWidth = MAX(168.0, self.leftControlsWidth + 16.0);
    CGFloat rightWidth = 360.0;
    CGFloat contentWidth = 12.0 + leftWidth + 10.0 + rightWidth + 12.0;
    [self.window setContentSize:NSMakeSize(contentWidth, 520.0)];
    self.window.minSize = NSMakeSize(leftWidth + 280.0, 400.0);
}

- (void)show {
    [self.outlineView reloadData];
    [self expandAllGroups];
    [self refreshDetail];
    if (!self.window.isVisible) {
        [self.window center];
    }
    [self.window makeKeyAndOrderFront:nil];
    [self.window orderFrontRegardless];
    [self.window makeMainWindow];
}

- (void)selectNodeWithIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return;
    }
    SnippetNode *found = [self findNodeWithIdentifier:identifier inNodes:self.snippetManager.rootNodes];
    if (found != nil) {
        [self selectNode:found];
    }
}

- (SnippetNode *)findNodeWithIdentifier:(NSString *)identifier inNodes:(NSArray<SnippetNode *> *)nodes {
    for (SnippetNode *node in nodes) {
        if ([node.identifier isEqualToString:identifier]) {
            return node;
        }
        if (node.type == SnippetNodeTypeGroup) {
            SnippetNode *found = [self findNodeWithIdentifier:identifier inNodes:node.items];
            if (found != nil) {
                return found;
            }
        }
    }
    return nil;
}

- (void)commitVisibleNonSecretFields {
    SnippetNode *node = self.displayedNode;
    if (node == nil || node.type == SnippetNodeTypeSeparator) {
        return;
    }
    node.title = self.titleField.hidden ? node.title : self.titleField.stringValue;
    if (node.type == SnippetNodeTypeItem) {
        node.text = self.valueView.string ?: @"";
    }
}

- (void)protectSecureFields {
    [self clearLoadedSecret];
    if (self.window.isVisible) {
        [self refreshDetail];
    }
}

- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    [self clearLoadedSecret];
}

- (void)clearLoadedSecret {
    self.secretLoaded = NO;
    self.secretDirty = NO;
    self.secretField.stringValue = @"";
}

- (void)buildUI {
    NSView *content = self.window.contentView;
    NSRect bounds = NSInsetRect(content.bounds, 12.0, 12.0);

    NSSplitView *split = [[NSSplitView alloc] initWithFrame:bounds];
    split.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    split.vertical = YES;
    split.dividerStyle = NSSplitViewDividerStyleThin;
    split.delegate = self;
    [content addSubview:split];
    self.splitView = split;

    NSView *left = [self buildLeftPane];
    NSView *right = [self buildRightPane];
    CGFloat leftWidth = MAX(168.0, self.leftControlsWidth + 16.0);
    left.frame = NSMakeRect(0.0, 0.0, leftWidth, bounds.size.height);
    right.frame = NSMakeRect(0.0, 0.0, MAX(280.0, bounds.size.width - leftWidth - 10.0), bounds.size.height);
    [split addSubview:left];
    [split addSubview:right];
    [split setPosition:leftWidth ofDividerAtIndex:0];
}

- (CGFloat)minimumEqualButtonWidthForButtons:(NSArray<NSButton *> *)buttons {
    CGFloat width = 0.0;
    for (NSButton *button in buttons) {
        [button sizeToFit];
        width = MAX(width, ceil(NSWidth(button.bounds)));
    }
    return width;
}

- (NSView *)buildLeftPane {
    NSView *left = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 220.0, 496.0)];

    NSScrollView *scroll = [[NSScrollView alloc] init];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.autohidesScrollers = YES;

    NSOutlineView *outline = [[NSOutlineView alloc] init];
    outline.headerView = nil;
    outline.allowsMultipleSelection = NO;
    outline.rowSizeStyle = NSTableViewRowSizeStyleSmall;
    outline.indentationPerLevel = 16.0;
    outline.delegate = self;
    outline.dataSource = self;
    outline.usesAlternatingRowBackgroundColors = YES;
    outline.draggingDestinationFeedbackStyle = NSTableViewDraggingDestinationFeedbackStyleSourceList;
    [outline registerForDraggedTypes:@[QCSnippetDragType]];
    [outline setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
    NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"title"];
    column.title = @"Snippets";
    column.resizingMask = NSTableColumnAutoresizingMask;
    [outline addTableColumn:column];
    outline.outlineTableColumn = column;
    scroll.documentView = outline;
    self.outlineView = outline;

    NSButton *addItem = [NSButton buttonWithTitle:@"Add Item" target:self action:@selector(addItem:)];
    NSButton *addGroup = [NSButton buttonWithTitle:@"Add Group" target:self action:@selector(addGroup:)];
    NSButton *addSep = [NSButton buttonWithTitle:@"Add Separator" target:self action:@selector(addSeparator:)];
    NSButton *deleteButton = [NSButton buttonWithTitle:@"Delete" target:self action:@selector(deleteSelected:)];
    NSArray<NSButton *> *buttons = @[addItem, addGroup, addSep, deleteButton];
    CGFloat buttonWidth = [self minimumEqualButtonWidthForButtons:buttons];
    CGFloat rowWidth = buttonWidth * 2.0 + 6.0;
    self.leftControlsWidth = rowWidth;

    NSStackView *row1 = [NSStackView stackViewWithViews:@[addItem, addGroup]];
    NSStackView *row2 = [NSStackView stackViewWithViews:@[addSep, deleteButton]];
    for (NSStackView *row in @[row1, row2]) {
        row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
        row.alignment = NSLayoutAttributeCenterY;
        row.spacing = 6.0;
    }

    self.dragPromptLabel = [NSTextField wrappingLabelWithString:@"Drag to reorder or nest."];
    self.dragPromptLabel.textColor = [NSColor secondaryLabelColor];
    self.dragPromptLabel.font = [NSFont systemFontOfSize:11.0];
    self.dragPromptLabel.alignment = NSTextAlignmentCenter;
    self.dragPromptLabel.preferredMaxLayoutWidth = rowWidth;

    NSStackView *buttonStack = [NSStackView stackViewWithViews:@[self.dragPromptLabel, row1, row2]];
    buttonStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    buttonStack.alignment = NSLayoutAttributeCenterX;
    buttonStack.spacing = 6.0;
    buttonStack.translatesAutoresizingMaskIntoConstraints = NO;

    [left addSubview:scroll];
    [left addSubview:buttonStack];

    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
        [scroll.topAnchor constraintEqualToAnchor:left.topAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:left.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:left.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:buttonStack.topAnchor constant:-8.0],
        [buttonStack.centerXAnchor constraintEqualToAnchor:left.centerXAnchor],
        [buttonStack.bottomAnchor constraintEqualToAnchor:left.bottomAnchor],
        [row1.widthAnchor constraintEqualToConstant:rowWidth],
        [row2.widthAnchor constraintEqualToConstant:rowWidth],
        [self.dragPromptLabel.widthAnchor constraintEqualToConstant:rowWidth]
    ]];
    for (NSButton *button in buttons) {
        [constraints addObject:[button.widthAnchor constraintEqualToConstant:buttonWidth]];
    }
    [NSLayoutConstraint activateConstraints:constraints];
    return left;
}

- (NSView *)buildRightPane {
    NSView *right = [[NSView alloc] initWithFrame:NSMakeRect(0.0, 0.0, 360.0, 496.0)];

    self.placeholderLabel = [NSTextField wrappingLabelWithString:@"Select a snippet, group, or separator to edit it."];
    self.placeholderLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.placeholderLabel.textColor = [NSColor secondaryLabelColor];

    self.detailContainer = [[NSView alloc] init];
    self.detailContainer.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *rightStack = [NSStackView stackViewWithViews:@[self.placeholderLabel, self.detailContainer]];
    rightStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    rightStack.alignment = NSLayoutAttributeLeading;
    rightStack.spacing = 4.0;
    rightStack.detachesHiddenViews = YES;
    rightStack.translatesAutoresizingMaskIntoConstraints = NO;
    [right addSubview:rightStack];
    [NSLayoutConstraint activateConstraints:@[
        [rightStack.topAnchor constraintEqualToAnchor:right.topAnchor constant:4.0],
        [rightStack.leadingAnchor constraintEqualToAnchor:right.leadingAnchor constant:12.0],
        [rightStack.trailingAnchor constraintEqualToAnchor:right.trailingAnchor constant:-12.0],
        [rightStack.bottomAnchor constraintLessThanOrEqualToAnchor:right.bottomAnchor constant:-4.0],
        [self.placeholderLabel.widthAnchor constraintEqualToAnchor:rightStack.widthAnchor],
        [self.detailContainer.widthAnchor constraintEqualToAnchor:rightStack.widthAnchor]
    ]];

    NSStackView *detail = [[NSStackView alloc] init];
    detail.translatesAutoresizingMaskIntoConstraints = NO;
    detail.orientation = NSUserInterfaceLayoutOrientationVertical;
    detail.alignment = NSLayoutAttributeLeading;
    detail.spacing = 8.0;
    detail.detachesHiddenViews = YES;
    [self.detailContainer addSubview:detail];
    [NSLayoutConstraint activateConstraints:@[
        [detail.topAnchor constraintEqualToAnchor:self.detailContainer.topAnchor],
        [detail.leadingAnchor constraintEqualToAnchor:self.detailContainer.leadingAnchor],
        [detail.trailingAnchor constraintEqualToAnchor:self.detailContainer.trailingAnchor],
        [detail.bottomAnchor constraintEqualToAnchor:self.detailContainer.bottomAnchor],
        [detail.widthAnchor constraintEqualToAnchor:self.detailContainer.widthAnchor]
    ]];

    self.titleLabel = [NSTextField labelWithString:@"Title"];
    self.titleField = [[NSTextField alloc] init];
    self.titleField.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleField.delegate = self;

    self.secureCheckbox = [NSButton checkboxWithTitle:@"Secure" target:self action:@selector(secureCheckboxChanged:)];

    self.valueLabel = [NSTextField labelWithString:@"Value"];
    self.valueScroll = [[NSScrollView alloc] init];
    self.valueScroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.valueScroll.hasVerticalScroller = YES;
    self.valueScroll.borderType = NSBezelBorder;
    self.valueScroll.autohidesScrollers = YES;
    NSTextView *textView = [[NSTextView alloc] init];
    textView.font = [NSFont systemFontOfSize:13.0];
    textView.richText = NO;
    textView.automaticQuoteSubstitutionEnabled = NO;
    textView.automaticTextReplacementEnabled = NO;
    textView.minSize = NSMakeSize(0.0, 40.0);
    textView.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    textView.verticallyResizable = YES;
    textView.horizontallyResizable = NO;
    textView.textContainer.containerSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    textView.textContainer.widthTracksTextView = YES;
    self.valueView = textView;
    textView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    self.valueScroll.documentView = textView;

    self.pendingHintLabel = [NSTextField wrappingLabelWithString:@"The value stays editable until you save. After Save Changes, it is stored in Keychain and hidden."];
    self.pendingHintLabel.textColor = [NSColor secondaryLabelColor];
    self.pendingHintLabel.preferredMaxLayoutWidth = 360.0;
    self.pendingHintLabel.hidden = YES;

    self.secretField = [[NSSecureTextField alloc] init];
    self.secretField.translatesAutoresizingMaskIntoConstraints = NO;
    self.secretField.placeholderString = @"••••••••";
    self.secretField.enabled = NO;
    self.secretField.delegate = self;

    self.revealButton = [NSButton buttonWithTitle:@"Edit Secure Value…" target:self action:@selector(editSecureValue:)];

    self.saveButton = [NSButton buttonWithTitle:@"Save Changes" target:self action:@selector(saveCurrent:)];
    self.spinner = [[NSProgressIndicator alloc] init];
    self.spinner.style = NSProgressIndicatorStyleSpinning;
    self.spinner.controlSize = NSControlSizeSmall;
    self.spinner.displayedWhenStopped = NO;

    self.revealRow = [NSStackView stackViewWithViews:@[self.revealButton, self.spinner]];
    self.revealRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    self.revealRow.spacing = 8.0;
    self.revealRow.alignment = NSLayoutAttributeCenterY;

    self.saveRow = [NSStackView stackViewWithViews:@[self.saveButton]];
    self.saveRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    self.saveRow.spacing = 8.0;

    self.keychainHintLabel = [NSTextField wrappingLabelWithString:@"Secure Snippet values are stored in Keychain."];
    self.keychainHintLabel.textColor = [NSColor secondaryLabelColor];
    self.keychainHintLabel.font = [NSFont systemFontOfSize:11.0];
    self.keychainHintLabel.preferredMaxLayoutWidth = 360.0;
    self.keychainHintLabel.hidden = YES;

    [detail addArrangedSubview:self.titleLabel];
    [detail addArrangedSubview:self.titleField];
    [detail addArrangedSubview:self.secureCheckbox];
    [detail addArrangedSubview:self.valueLabel];
    [detail addArrangedSubview:self.valueScroll];
    [detail addArrangedSubview:self.pendingHintLabel];
    [detail addArrangedSubview:self.saveRow];
    [detail addArrangedSubview:self.secretField];
    [detail addArrangedSubview:self.revealRow];
    [detail addArrangedSubview:self.keychainHintLabel];

    [self.titleField setContentHuggingPriority:1.0 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.valueScroll setContentHuggingPriority:1.0 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.secretField setContentHuggingPriority:1.0 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.titleField setContentCompressionResistancePriority:1.0 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.valueScroll setContentCompressionResistancePriority:1.0 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.secretField setContentCompressionResistancePriority:1.0 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [NSLayoutConstraint activateConstraints:@[
        [self.valueScroll.heightAnchor constraintEqualToConstant:93.0],
        [self.titleField.widthAnchor constraintEqualToAnchor:detail.widthAnchor],
        [self.valueScroll.widthAnchor constraintEqualToAnchor:detail.widthAnchor],
        [self.secretField.widthAnchor constraintEqualToAnchor:detail.widthAnchor],
        [self.pendingHintLabel.widthAnchor constraintEqualToAnchor:detail.widthAnchor],
        [self.keychainHintLabel.widthAnchor constraintEqualToAnchor:detail.widthAnchor]
    ]];

    self.detailContainer.hidden = YES;
    return right;
}

#pragma mark - Outline

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    (void)outlineView;
    if (item == nil) {
        return (NSInteger)self.snippetManager.rootNodes.count;
    }
    SnippetNode *node = (SnippetNode *)item;
    if (node.type == SnippetNodeTypeGroup) {
        return (NSInteger)node.items.count;
    }
    return 0;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    (void)outlineView;
    return ((SnippetNode *)item).type == SnippetNodeTypeGroup;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    (void)outlineView;
    NSArray<SnippetNode *> *nodes = (item == nil) ? self.snippetManager.rootNodes : ((SnippetNode *)item).items;
    if (index < 0 || index >= (NSInteger)nodes.count) {
        return nil;
    }
    return nodes[(NSUInteger)index];
}

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    (void)tableColumn;
    SnippetNode *node = (SnippetNode *)item;
    if (node.type == SnippetNodeTypeSeparator) {
        NSTableCellView *cell = [outlineView makeViewWithIdentifier:@"separatorCell" owner:self];
        if (cell == nil) {
            cell = [[NSTableCellView alloc] init];
            cell.identifier = @"separatorCell";
            NSTextField *textField = [NSTextField labelWithString:@""];
            textField.translatesAutoresizingMaskIntoConstraints = NO;
            textField.lineBreakMode = NSLineBreakByTruncatingTail;
            cell.textField = textField;
            [cell addSubview:textField];
            [NSLayoutConstraint activateConstraints:@[
                [textField.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
                [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
                [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
            ]];
        }
        cell.textField.stringValue = @"— Separator —";
        cell.textField.textColor = [NSColor secondaryLabelColor];
        return cell;
    }

    NSTableCellView *cell = [outlineView makeViewWithIdentifier:@"snippetCell" owner:self];
    if (cell == nil) {
        cell = [[NSTableCellView alloc] init];
        cell.identifier = @"snippetCell";
        NSImageView *imageView = [[NSImageView alloc] init];
        imageView.translatesAutoresizingMaskIntoConstraints = NO;
        imageView.imageScaling = NSImageScaleProportionallyDown;
        NSTextField *textField = [NSTextField labelWithString:@""];
        textField.translatesAutoresizingMaskIntoConstraints = NO;
        textField.lineBreakMode = NSLineBreakByTruncatingTail;
        cell.imageView = imageView;
        cell.textField = textField;
        [cell addSubview:imageView];
        [cell addSubview:textField];
        [NSLayoutConstraint activateConstraints:@[
            [imageView.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
            [imageView.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [imageView.widthAnchor constraintEqualToConstant:16],
            [imageView.heightAnchor constraintEqualToConstant:16],
            [textField.leadingAnchor constraintEqualToAnchor:imageView.trailingAnchor constant:6],
            [textField.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
            [textField.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor]
        ]];
    }
    cell.textField.textColor = [NSColor labelColor];
    switch (node.type) {
        case SnippetNodeTypeSecureItem:
            cell.imageView.image = [QCStatusImages secureSnippetImage];
            cell.textField.stringValue = node.displayTitle;
            break;
        case SnippetNodeTypeGroup:
            cell.imageView.image = [QCStatusImages groupImage];
            cell.textField.stringValue = node.displayTitle;
            break;
        case SnippetNodeTypeItem:
            cell.imageView.image = [QCStatusImages itemImage];
            cell.textField.stringValue = node.displayTitle;
            break;
        case SnippetNodeTypeSeparator:
            break;
    }
    return cell;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    (void)notification;
    [self clearLoadedSecret];
    self.isNewUnsavedSecureItem = NO;
    self.pendingConvertToSecure = NO;
    [self refreshDetail];
}

- (void)expandAllGroups {
    [self.outlineView expandItem:nil expandChildren:YES];
}

#pragma mark - Drag and drop

- (id<NSPasteboardWriting>)outlineView:(NSOutlineView *)outlineView pasteboardWriterForItem:(id)item {
    (void)outlineView;
    if (![item isKindOfClass:[SnippetNode class]]) {
        return nil;
    }
    self.draggedNode = item;
    NSPasteboardItem *pasteboardItem = [[NSPasteboardItem alloc] init];
    [pasteboardItem setString:[NSString stringWithFormat:@"%p", (__bridge void *)item] forType:QCSnippetDragType];
    return pasteboardItem;
}

- (SnippetNode *)draggedNodeFromInfo:(id<NSDraggingInfo>)info {
    if ([self.draggedNode isKindOfClass:[SnippetNode class]]) {
        return self.draggedNode;
    }
    NSString *token = [[info draggingPasteboard] stringForType:QCSnippetDragType];
    return [self nodeMatchingPointerToken:token inNodes:self.snippetManager.rootNodes];
}

- (SnippetNode *)nodeMatchingPointerToken:(NSString *)token inNodes:(NSArray<SnippetNode *> *)nodes {
    if (token.length == 0) {
        return nil;
    }
    for (SnippetNode *node in nodes) {
        NSString *pointer = [NSString stringWithFormat:@"%p", (__bridge void *)node];
        if ([pointer isEqualToString:token]) {
            return node;
        }
        if (node.type == SnippetNodeTypeGroup) {
            SnippetNode *found = [self nodeMatchingPointerToken:token inNodes:node.items];
            if (found != nil) {
                return found;
            }
        }
    }
    return nil;
}

- (void)outlineView:(NSOutlineView *)outlineView
    draggingSession:(NSDraggingSession *)session
   willBeginAtPoint:(NSPoint)screenPoint
           forItems:(NSArray *)draggedItems {
    (void)outlineView;
    (void)session;
    (void)screenPoint;
    self.draggedNode = draggedItems.firstObject;
}

- (void)outlineView:(NSOutlineView *)outlineView
    draggingSession:(NSDraggingSession *)session
       endedAtPoint:(NSPoint)screenPoint
          operation:(NSDragOperation)operation {
    (void)outlineView;
    (void)session;
    (void)screenPoint;
    (void)operation;
    self.draggedNode = nil;
}

- (NSDragOperation)outlineView:(NSOutlineView *)outlineView
                  validateDrop:(id<NSDraggingInfo>)info
                  proposedItem:(id)item
            proposedChildIndex:(NSInteger)index {
    SnippetNode *dragged = [self draggedNodeFromInfo:info];
    if (dragged == nil) {
        return NSDragOperationNone;
    }
    SnippetNode *proposedParent = [item isKindOfClass:[SnippetNode class]] ? item : nil;

    if (proposedParent != nil && proposedParent.type == SnippetNodeTypeGroup) {
        if (proposedParent == dragged || [dragged containsDescendant:proposedParent]) {
            return NSDragOperationNone;
        }
        if (index == NSOutlineViewDropOnItemIndex) {
            [outlineView expandItem:proposedParent];
            return NSDragOperationMove;
        }
        return NSDragOperationMove;
    }

    if (proposedParent != nil && proposedParent.type != SnippetNodeTypeGroup) {
        SnippetNode *grandparent = [self.snippetManager parentOfNode:proposedParent];
        if (grandparent == dragged || [dragged containsDescendant:grandparent]) {
            return NSDragOperationNone;
        }
        NSArray<SnippetNode *> *siblings = grandparent != nil ? grandparent.items : self.snippetManager.rootNodes;
        NSUInteger siblingIndex = [siblings indexOfObject:proposedParent];
        if (siblingIndex == NSNotFound) {
            return NSDragOperationNone;
        }
        NSInteger dropIndex = (index == NSOutlineViewDropOnItemIndex) ? (NSInteger)siblingIndex + 1 : (NSInteger)siblingIndex;
        [outlineView setDropItem:grandparent dropChildIndex:dropIndex];
        return NSDragOperationMove;
    }

    if (index == NSOutlineViewDropOnItemIndex) {
        return NSDragOperationNone;
    }
    return NSDragOperationMove;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView
         acceptDrop:(id<NSDraggingInfo>)info
               item:(id)item
         childIndex:(NSInteger)index {
    SnippetNode *dragged = [self draggedNodeFromInfo:info];
    if (dragged == nil) {
        return NO;
    }
    SnippetNode *newParent = [item isKindOfClass:[SnippetNode class]] ? item : nil;
    NSUInteger destIndex = 0;
    if (newParent != nil && newParent.type == SnippetNodeTypeGroup && index == NSOutlineViewDropOnItemIndex) {
        destIndex = newParent.items.count;
        [outlineView expandItem:newParent];
    } else {
        destIndex = (index == NSOutlineViewDropOnItemIndex) ? 0 : (NSUInteger)MAX(0, index);
        if (newParent != nil && newParent.type != SnippetNodeTypeGroup) {
            return NO;
        }
    }
    if (![self.snippetManager moveNode:dragged toParent:newParent atIndex:destIndex]) {
        return NO;
    }
    [self persistOrAlert];
    if (newParent != nil) {
        [self.outlineView expandItem:newParent];
    }
    [self selectNode:dragged];
    return YES;
}

#pragma mark - Split view

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMinimum ofSubviewAt:(NSInteger)dividerIndex {
    (void)dividerIndex;
    if (NSWidth(splitView.bounds) < 480.0) {
        return proposedMinimum;
    }
    return MAX(self.leftControlsWidth + 8.0, 168.0);
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMaximum ofSubviewAt:(NSInteger)dividerIndex {
    (void)dividerIndex;
    CGFloat width = NSWidth(splitView.bounds);
    if (width < 480.0) {
        return proposedMaximum;
    }
    return width - 280.0;
}

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview {
    (void)splitView;
    (void)subview;
    return NO;
}

- (NSLayoutPriority)splitView:(NSSplitView *)splitView holdingPriorityForSubviewAtIndex:(NSInteger)subviewIndex {
    (void)splitView;
    return (subviewIndex == 0) ? 50 : 150;
}

- (void)splitViewDidResizeSubviews:(NSNotification *)notification {
    (void)notification;
}

- (SnippetNode *)selectedNode {
    NSInteger row = self.outlineView.selectedRow;
    if (row < 0) {
        return nil;
    }
    id item = [self.outlineView itemAtRow:row];
    return [item isKindOfClass:[SnippetNode class]] ? item : nil;
}

- (SnippetNode *)parentForInsertionAtIndex:(NSUInteger *)outIndex {
    SnippetNode *selected = [self selectedNode];
    if (selected == nil) {
        if (outIndex != NULL) {
            *outIndex = self.snippetManager.rootNodes.count;
        }
        return nil;
    }
    if (selected.type == SnippetNodeTypeGroup) {
        if (outIndex != NULL) {
            *outIndex = selected.items.count;
        }
        return selected;
    }
    SnippetNode *parent = [self.snippetManager parentOfNode:selected];
    NSArray<SnippetNode *> *siblings = parent != nil ? parent.items : self.snippetManager.rootNodes;
    NSUInteger index = [siblings indexOfObject:selected];
    if (outIndex != NULL) {
        *outIndex = (index == NSNotFound) ? siblings.count : index + 1;
    }
    return parent;
}

- (void)selectNode:(SnippetNode *)node {
    [self.outlineView reloadData];
    [self expandAllGroups];
    NSInteger row = [self.outlineView rowForItem:node];
    if (row >= 0) {
        [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
        [self.outlineView scrollRowToVisible:row];
    }
    [self refreshDetail];
}

#pragma mark - Detail

- (void)refreshDetail {
    SnippetNode *node = [self selectedNode];
    self.displayedNode = node;
    if (node == nil) {
        self.detailContainer.hidden = YES;
        self.placeholderLabel.hidden = NO;
        self.placeholderLabel.stringValue = @"Select a snippet, group, or separator to edit it.";
        return;
    }
    self.placeholderLabel.hidden = YES;
    self.detailContainer.hidden = NO;
    self.suppressDetailSync = YES;
    self.titleField.stringValue = node.title ?: @"";

    BOOL isSeparator = node.type == SnippetNodeTypeSeparator;
    BOOL isGroup = node.type == SnippetNodeTypeGroup;
    BOOL isSecure = node.type == SnippetNodeTypeSecureItem;
    BOOL isItem = node.type == SnippetNodeTypeItem;
    BOOL pendingSecure = isItem && self.pendingConvertToSecure;
    BOOL showLockedSecret = isSecure && !pendingSecure;

    if (isSeparator) {
        self.detailContainer.hidden = YES;
        self.placeholderLabel.hidden = NO;
        self.placeholderLabel.stringValue = @"Separators have no editable fields.";
        self.suppressDetailSync = NO;
        return;
    }

    self.titleLabel.hidden = NO;
    self.titleField.hidden = NO;
    self.secureCheckbox.hidden = !(isItem || isSecure);
    self.secureCheckbox.state = (isSecure || pendingSecure) ? NSControlStateValueOn : NSControlStateValueOff;
    self.valueLabel.hidden = !(isItem || pendingSecure);
    self.valueScroll.hidden = !(isItem || pendingSecure);
    if (isItem || pendingSecure) {
        self.valueView.string = node.text ?: @"";
        self.valueView.editable = YES;
    } else {
        self.valueView.string = @"";
    }
    self.pendingHintLabel.hidden = !pendingSecure;
    self.secretField.hidden = !showLockedSecret;
    self.revealButton.hidden = !showLockedSecret;
    self.revealRow.hidden = !showLockedSecret;
    self.saveButton.hidden = showLockedSecret || isSeparator;
    self.saveRow.hidden = showLockedSecret || isSeparator;
    self.keychainHintLabel.hidden = !showLockedSecret;

    if (showLockedSecret) {
        if (self.isNewUnsavedSecureItem) {
            self.secretField.enabled = YES;
            self.secretField.placeholderString = @"Enter secret value";
            self.revealButton.enabled = NO;
        } else if (self.secretLoaded) {
            self.secretField.enabled = YES;
            self.revealButton.enabled = NO;
        } else {
            self.secretField.enabled = NO;
            self.secretField.stringValue = @"";
            self.secretField.placeholderString = @"••••••••";
            self.revealButton.enabled = YES;
        }
    } else {
        self.secretField.stringValue = @"";
        self.secretField.enabled = NO;
    }

    if (isGroup) {
        self.valueLabel.hidden = YES;
        self.valueScroll.hidden = YES;
        self.secretField.hidden = YES;
        self.pendingHintLabel.hidden = YES;
        self.revealButton.hidden = YES;
        self.revealRow.hidden = YES;
        self.secureCheckbox.hidden = YES;
        self.saveButton.hidden = NO;
        self.saveRow.hidden = NO;
        self.keychainHintLabel.hidden = YES;
    }

    self.suppressDetailSync = NO;
}

- (void)controlTextDidChange:(NSNotification *)obj {
    (void)obj;
    if (self.suppressDetailSync) {
        return;
    }
    if (obj.object == self.secretField && self.secretField.enabled) {
        self.secretDirty = YES;
    }
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    if (self.suppressDetailSync) {
        return;
    }
    SnippetNode *node = [self selectedNode];
    if (node == nil) {
        return;
    }
    if (obj.object == self.titleField && node.type == SnippetNodeTypeSecureItem) {
        node.title = self.titleField.stringValue;
        [self persistOrAlert];
        return;
    }
    if (obj.object == self.secretField && node.type == SnippetNodeTypeSecureItem && (self.secretDirty || self.isNewUnsavedSecureItem)) {
        [self saveCurrent:nil];
    }
}

#pragma mark - Mutations

- (void)persistOrAlert {
    [self commitVisibleNonSecretFields];
    NSError *error = nil;
    if (![self.snippetManager saveWithError:&error]) {
        [self presentError:error title:@"Couldn’t save snippets.json"];
    } else {
        [self.outlineView reloadData];
        [self expandAllGroups];
    }
}

- (void)presentError:(NSError *)error title:(NSString *)title {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = title;
    alert.informativeText = error.localizedDescription ?: @"An unknown error occurred.";
    [alert addButtonWithTitle:@"OK"];
    if (self.window.isVisible) {
        [alert beginSheetModalForWindow:self.window completionHandler:nil];
    } else {
        [alert runModal];
    }
}

- (void)addItem:(id)sender {
    (void)sender;
    NSUInteger index = 0;
    SnippetNode *parent = [self parentForInsertionAtIndex:&index];
    SnippetNode *node = [SnippetNode itemWithTitle:@"New Snippet" text:@""];
    [self.snippetManager insertNode:node parent:parent atIndex:index];
    [self persistOrAlert];
    [self selectNode:node];
    [self.window makeFirstResponder:self.titleField];
}

- (void)addGroup:(id)sender {
    (void)sender;
    NSUInteger index = 0;
    SnippetNode *parent = [self parentForInsertionAtIndex:&index];
    SnippetNode *node = [SnippetNode groupWithTitle:@"New Group" items:@[]];
    [self.snippetManager insertNode:node parent:parent atIndex:index];
    [self persistOrAlert];
    [self selectNode:node];
    [self.window makeFirstResponder:self.titleField];
}

- (void)addSeparator:(id)sender {
    (void)sender;
    NSUInteger index = 0;
    SnippetNode *parent = [self parentForInsertionAtIndex:&index];
    SnippetNode *node = [SnippetNode separator];
    [self.snippetManager insertNode:node parent:parent atIndex:index];
    [self persistOrAlert];
    [self selectNode:node];
}

- (void)deleteSelected:(id)sender {
    (void)sender;
    SnippetNode *node = [self selectedNode];
    if (node == nil) {
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    if (node.type == SnippetNodeTypeSecureItem) {
        alert.messageText = @"Delete Secure Snippet?";
        alert.informativeText = [NSString stringWithFormat:@"“%@” will be removed from QuickClip and its Keychain value will be deleted. This cannot be undone.", node.displayTitle];
    } else if (node.type == SnippetNodeTypeGroup) {
        alert.messageText = @"Delete Group?";
        alert.informativeText = @"The group and everything inside it will be removed. Secure Snippets inside the group will also have their Keychain values deleted.";
    } else {
        alert.messageText = @"Delete Snippet?";
        alert.informativeText = [NSString stringWithFormat:@"Delete “%@”?", node.displayTitle];
    }
    [alert addButtonWithTitle:@"Delete"];
    [alert addButtonWithTitle:@"Cancel"];
    __weak typeof(self) weakSelf = self;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode == NSAlertFirstButtonReturn) {
            [weakSelf performDelete:node];
        }
    }];
}

- (void)performDelete:(SnippetNode *)node {
    NSArray<NSString *> *secureIDs = [node allSecureSnippetIDs];
    SnippetNode *parent = [self.snippetManager parentOfNode:node];
    NSArray<SnippetNode *> *siblings = parent != nil ? parent.items : self.snippetManager.rootNodes;
    NSUInteger index = [siblings indexOfObject:node];
    if (![self.snippetManager removeNode:node]) {
        return;
    }
    NSError *error = nil;
    if (![self.snippetManager saveWithError:&error]) {
        if (index != NSNotFound) {
            [self.snippetManager insertNode:node parent:parent atIndex:index];
        }
        [self presentError:error title:@"Couldn’t update snippets.json"];
        [self selectNode:node];
        return;
    }
    [self.outlineView reloadData];
    [self expandAllGroups];
    [self refreshDetail];
    if (secureIDs.count == 0) {
        return;
    }
    [self deleteKeychainIDs:secureIDs remainingFailures:[NSMutableArray array]];
}

- (void)deleteKeychainIDs:(NSArray<NSString *> *)ids remainingFailures:(NSMutableArray<NSString *> *)failures {
    if (ids.count == 0) {
        if (failures.count > 0) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.alertStyle = NSAlertStyleWarning;
            alert.messageText = @"Orphaned Keychain item";
            alert.informativeText = @"The snippet was removed from snippets.json, but QuickClip could not delete every matching Keychain item. An orphaned Keychain entry may remain. QuickClip will not automatically delete other Keychain items.";
            [alert addButtonWithTitle:@"OK"];
            [alert beginSheetModalForWindow:self.window completionHandler:nil];
        }
        return;
    }
    NSString *next = ids.firstObject;
    NSArray<NSString *> *rest = [ids subarrayWithRange:NSMakeRange(1, ids.count - 1)];
    __weak typeof(self) weakSelf = self;
    [self.secureStore deleteSecretForSnippetID:next authenticationContext:self.authenticationManager.currentAuthenticatedContext completion:^(NSError * _Nullable error) {
        if (error != nil) {
            [failures addObject:next];
        }
        [weakSelf deleteKeychainIDs:rest remainingFailures:failures];
    }];
}

- (void)saveCurrent:(id)sender {
    (void)sender;
    SnippetNode *node = [self selectedNode];
    if (node == nil) {
        return;
    }
    node.title = self.titleField.stringValue;
    if (node.type == SnippetNodeTypeItem) {
        node.text = self.valueView.string ?: @"";
        if (self.pendingConvertToSecure) {
            [self convertNodeToSecure:node];
            return;
        }
        [self persistOrAlert];
        [self selectNode:node];
        return;
    }
    if (node.type == SnippetNodeTypeGroup) {
        [self persistOrAlert];
        [self selectNode:node];
        return;
    }
    if (node.type != SnippetNodeTypeSecureItem) {
        return;
    }

    BOOL needsSecretWrite = self.isNewUnsavedSecureItem || self.secretDirty;
    if (needsSecretWrite) {
        NSString *secret = [self.secretField.stringValue copy];
        if (secret.length == 0) {
            [self presentError:[QCErrors errorWithCode:QCErrorCodeValidation
                                           description:@"Enter a secret value before saving this Secure Snippet."]
                         title:@"Secret required"];
            return;
        }
        [self.spinner startAnimation:nil];
        self.saveButton.enabled = NO;
        __weak typeof(self) weakSelf = self;
        void (^finish)(NSError * _Nullable) = ^(NSError *error) {
            __strong typeof(weakSelf) self = weakSelf;
            if (self == nil) { return; }
            [self.spinner stopAnimation:nil];
            self.saveButton.enabled = YES;
            if (error != nil) {
                [self presentError:error title:@"Couldn’t store the secure value"];
                return;
            }
            NSError *saveError = nil;
            if (![self.snippetManager saveWithError:&saveError]) {
                [self.secureStore deleteSecretForSnippetID:node.identifier
                                    authenticationContext:self.authenticationManager.currentAuthenticatedContext
                                               completion:^(NSError * _Nullable rollbackError) {
                    NSString *message = saveError.localizedDescription ?: @"Couldn’t write snippets.json.";
                    if (rollbackError != nil) {
                        message = [message stringByAppendingString:@" The Keychain item may remain as an orphaned entry."];
                    }
                    [self presentError:[QCErrors errorWithCode:QCErrorCodeRollback description:message]
                                 title:@"Secure Snippet save failed"];
                }];
                return;
            }
            self.isNewUnsavedSecureItem = NO;
            self.secretDirty = NO;
            self.secretLoaded = NO;
            self.secretField.stringValue = @"";
            [self selectNode:node];
        };

        if (self.isNewUnsavedSecureItem) {
            [self.secureStore addSecret:secret forSnippetID:node.identifier completion:finish];
        } else {
            [self.secureStore updateSecret:secret
                             forSnippetID:node.identifier
                   authenticationContext:self.authenticationManager.currentAuthenticatedContext
                               completion:finish];
        }
        return;
    }

    [self persistOrAlert];
    [self selectNode:node];
}

- (void)editSecureValue:(id)sender {
    (void)sender;
    SnippetNode *node = [self selectedNode];
    if (node == nil || node.type != SnippetNodeTypeSecureItem) {
        return;
    }
    if (!self.authenticationManager.isUnlocked) {
        [self presentError:[QCErrors errorWithCode:QCErrorCodeAuthentication description:@"Unlock QuickClip first."]
                     title:@"QuickClip is locked"];
        return;
    }
    [self.spinner startAnimation:nil];
    self.revealButton.enabled = NO;
    __weak typeof(self) weakSelf = self;
    NSString *title = node.title ?: @"item";
    [self.secureAuth obtainContextForSnippetTitle:title completion:^(LAContext * _Nullable context, NSError * _Nullable authError) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) { return; }
        if (context == nil) {
            [self.spinner stopAnimation:nil];
            self.revealButton.enabled = YES;
            if (authError != nil && authError.code != LAErrorUserCancel && authError.code != errSecUserCanceled) {
                [self presentError:authError title:@"Authentication failed"];
            }
            return;
        }
        [self.secureStore fetchSecretForSnippetID:node.identifier authenticationContext:context completion:^(NSString * _Nullable secret, NSError * _Nullable error) {
            [self.spinner stopAnimation:nil];
            if ([self.secureAuth shouldInvalidateContextAfterUse]) {
                [context invalidate];
            }
            if (secret == nil) {
                self.revealButton.enabled = YES;
                NSAlert *alert = [[NSAlert alloc] init];
                alert.alertStyle = NSAlertStyleWarning;
                alert.messageText = @"Secure value missing";
                alert.informativeText = error.localizedDescription ?: @"The secure value for this snippet could not be found in Keychain.";
                [alert addButtonWithTitle:@"Replace Value"];
                [alert addButtonWithTitle:@"OK"];
                [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
                    if (returnCode == NSAlertFirstButtonReturn) {
                        self.secretField.enabled = YES;
                        self.secretField.stringValue = @"";
                        self.secretLoaded = YES;
                        self.secretDirty = YES;
                        self.isNewUnsavedSecureItem = YES;
                        [self.window makeFirstResponder:self.secretField];
                    }
                }];
                return;
            }
            self.secretField.enabled = YES;
            self.secretField.stringValue = secret;
            self.secretLoaded = YES;
            self.secretDirty = NO;
            self.revealButton.enabled = NO;
            [self.window makeFirstResponder:self.secretField];
        }];
    }];
}

- (void)secureCheckboxChanged:(NSButton *)sender {
    SnippetNode *node = [self selectedNode];
    if (node == nil) {
        return;
    }
    BOOL wantSecure = sender.state == NSControlStateValueOn;
    if (node.type == SnippetNodeTypeItem) {
        self.pendingConvertToSecure = wantSecure;
        [self refreshDetail];
        return;
    }
    if (!wantSecure && node.type == SnippetNodeTypeSecureItem) {
        [self convertNodeToNormal:node];
        return;
    }
    [self refreshDetail];
}

- (void)convertNodeToSecure:(SnippetNode *)node {
    if (node.type != SnippetNodeTypeItem) {
        return;
    }
    [self commitVisibleNonSecretFields];
    NSString *plaintext = [node.text copy] ?: @"";
    if (node.identifier.length == 0) {
        node.identifier = [[NSUUID UUID] UUIDString];
    }
    NSString *identifier = node.identifier;
    NSString *previousTitle = node.title;
    NSString *previousText = node.text;
    [self.spinner startAnimation:nil];
    __weak typeof(self) weakSelf = self;
    [self.secureStore addSecret:plaintext forSnippetID:identifier completion:^(NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) { return; }
        if (error != nil) {
            [self.spinner stopAnimation:nil];
            self.pendingConvertToSecure = YES;
            self.secureCheckbox.state = NSControlStateValueOn;
            [self presentError:error title:@"Couldn’t convert to Secure Snippet"];
            return;
        }
        node.type = SnippetNodeTypeSecureItem;
        node.text = nil;
        node.title = previousTitle;
        NSError *saveError = nil;
        if (![self.snippetManager saveWithError:&saveError]) {
            node.type = SnippetNodeTypeItem;
            node.text = previousText;
            [self.secureStore deleteSecretForSnippetID:identifier
                                authenticationContext:self.authenticationManager.currentAuthenticatedContext
                                           completion:^(NSError * _Nullable rollbackError) {
                [self.spinner stopAnimation:nil];
                NSString *message = saveError.localizedDescription ?: @"Couldn’t write snippets.json.";
                if (rollbackError != nil) {
                    message = [message stringByAppendingString:@" A Keychain item may remain as an orphaned entry."];
                }
                self.pendingConvertToSecure = YES;
                self.secureCheckbox.state = NSControlStateValueOn;
                [self presentError:[QCErrors errorWithCode:QCErrorCodeRollback description:message]
                             title:@"Conversion rolled back"];
                [self refreshDetail];
            }];
            return;
        }
        [self.spinner stopAnimation:nil];
        self.secretLoaded = NO;
        self.secretDirty = NO;
        self.isNewUnsavedSecureItem = NO;
        self.pendingConvertToSecure = NO;
        [self selectNode:node];
    }];
}

- (void)convertNodeToNormal:(SnippetNode *)node {
    if (node.type != SnippetNodeTypeSecureItem) {
        return;
    }
    [self commitVisibleNonSecretFields];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleCritical;
    alert.messageText = @"Convert to a normal snippet?";
    alert.informativeText = @"This will store the snippet value as plaintext in snippets.json.";
    [alert addButtonWithTitle:@"Convert"];
    [alert addButtonWithTitle:@"Cancel"];
    __weak typeof(self) weakSelf = self;
    [alert beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse returnCode) {
        if (returnCode != NSAlertFirstButtonReturn) {
            weakSelf.secureCheckbox.state = NSControlStateValueOn;
            return;
        }
        [weakSelf performConvertToNormal:node];
    }];
}

- (void)performConvertToNormal:(SnippetNode *)node {
    [self.spinner startAnimation:nil];
    __weak typeof(self) weakSelf = self;
    NSString *title = node.title ?: @"item";
    [self.secureAuth obtainContextForSnippetTitle:title completion:^(LAContext * _Nullable context, NSError * _Nullable authError) {
        __strong typeof(weakSelf) self = weakSelf;
        if (self == nil) { return; }
        if (context == nil) {
            [self.spinner stopAnimation:nil];
            self.secureCheckbox.state = NSControlStateValueOn;
            if (authError != nil && authError.code != LAErrorUserCancel && authError.code != errSecUserCanceled) {
                [self presentError:authError title:@"Authentication failed"];
            }
            return;
        }
        [self.secureStore fetchSecretForSnippetID:node.identifier authenticationContext:context completion:^(NSString * _Nullable secret, NSError * _Nullable error) {
            if (secret == nil) {
                [self.spinner stopAnimation:nil];
                self.secureCheckbox.state = NSControlStateValueOn;
                [self presentError:error ?: [QCErrors errorWithCode:QCErrorCodeMissingSecureValue
                                                       description:@"The secure value for this snippet could not be found in Keychain."]
                             title:@"Couldn’t convert snippet"];
                return;
            }
            NSString *identifier = node.identifier;
            node.type = SnippetNodeTypeItem;
            node.text = secret;
            secret = nil;
            NSError *saveError = nil;
            if (![self.snippetManager saveWithError:&saveError]) {
                node.type = SnippetNodeTypeSecureItem;
                node.text = nil;
                [self.spinner stopAnimation:nil];
                self.secureCheckbox.state = NSControlStateValueOn;
                [self presentError:saveError title:@"Couldn’t write snippets.json"];
                [self refreshDetail];
                return;
            }
            [self.secureStore deleteSecretForSnippetID:identifier authenticationContext:context completion:^(NSError * _Nullable deleteError) {
                [self.spinner stopAnimation:nil];
                self.secretLoaded = NO;
                self.secretDirty = NO;
                [self selectNode:node];
                if (deleteError != nil) {
                    NSAlert *alert = [[NSAlert alloc] init];
                    alert.alertStyle = NSAlertStyleWarning;
                    alert.messageText = @"Snippet converted, but Keychain cleanup failed";
                    alert.informativeText = @"The value is now stored as plaintext in snippets.json. An orphaned Keychain copy may remain. QuickClip will not automatically delete other Keychain items.";
                    [alert addButtonWithTitle:@"OK"];
                    [alert beginSheetModalForWindow:self.window completionHandler:nil];
                }
            }];
        }];
    }];
}

@end
