//
//  ASTableView.mm
//  Texture
//
//  Copyright (c) Facebook, Inc. and its affiliates.  All rights reserved.
//  Changes after 4/13/2017 are: Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import <TargetConditionals.h>
#import "ASTableViewInternal.h"

#import "_ASHierarchyChangeSet.h"
#import "ASBatchFetching.h"
#import "ASDataController.h"
#import "ASCellNode+Internal.h"
#import "ASCollectionElement.h"
#import "ASCollections.h"
#import "ASConfigurationInternal.h"
#import "ASDisplayNodeExtras.h"
#import "ASDisplayNode+InterfaceState.h"
#import "ASDisplayNode+FrameworkPrivate.h"
#import "ASDisplayNodeInternal.h"
#import "ASElementMap.h"
#import "ASInternalHelpers.h"
#import "ASLayout.h"
#import "ASTableNode.h"
#import "ASRangeController.h"
#import "ASTableLayoutController.h"
#import "ASBatchContext.h"

#if !AS_PLATFORM_MACOS
#import "_ASCoreAnimationExtras.h"
#import "_ASDisplayLayer.h"
#import "ASDelegateProxy.h"
#import "ASTableNode+Beta.h"
#import "ASTableView+Undeprecated.h"
#endif


static NSString * const kCellReuseIdentifier = @"_ASTableViewCell";

//#define LOG(...) NSLog(__VA_ARGS__)
#define LOG(...)

/**
 * See note at the top of ASCollectionView.mm near declaration of macro GET_COLLECTIONNODE_OR_RETURN
 */
#define GET_TABLENODE_OR_RETURN(__var, __val) \
  ASTableNode *__var = self.tableNode; \
  if (__var == nil) { \
    return __val; \
  }

#if !AS_PLATFORM_MACOS
#define UITABLEVIEW_RESPONDS_TO_SELECTOR() \
  ({ \
    static BOOL superResponds; \
    static dispatch_once_t onceToken; \
    dispatch_once(&onceToken, ^{ \
      superResponds = [UITableView instancesRespondToSelector:_cmd]; \
    }); \
    superResponds; \
  })
#endif

#if !AS_PLATFORM_MACOS
@interface UITableView (ScrollViewDelegate)

- (void)scrollViewDidScroll:(ASScrollView *)scrollView;
- (void)scrollViewDidEndDecelerating:(ASScrollView *)scrollView;
- (void)scrollViewWillBeginDragging:(ASScrollView *)scrollView;
- (void)scrollViewWillEndDragging:(ASScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset;
- (void)scrollViewDidEndDragging:(ASScrollView *)scrollView willDecelerate:(BOOL)decelerate;

@end
#endif

#pragma mark -
#pragma mark ASCellNode<->UITableViewCell bridging.

#if !AS_PLATFORM_MACOS
@class _ASTableViewCell;

@protocol _ASTableViewCellDelegate <NSObject>
- (void)didLayoutSubviewsOfTableViewCell:(_ASTableViewCell *)tableViewCell;
@end

@interface _ASTableViewCell : UITableViewCell
@property (nonatomic, weak) id<_ASTableViewCellDelegate> delegate;
@property (nonatomic, readonly) ASCellNode *node;
@property (nonatomic) ASCollectionElement *element;
@end

@implementation _ASTableViewCell
// TODO add assertions to prevent use of view-backed UITableViewCell properties (eg .textLabel)

- (void)layoutSubviews
{
  [super layoutSubviews];
  [_delegate didLayoutSubviewsOfTableViewCell:self];
}

- (void)didTransitionToState:(UITableViewCellStateMask)state
{
  [self setNeedsLayout];
  [self layoutIfNeeded];
  [super didTransitionToState:state];
}

- (ASCellNode *)node
{
  return self.element.node;
}

- (void)setElement:(ASCollectionElement *)element
{
  _element = element;
  ASCellNode *node = element.node;
  
  if (node) {
    self.backgroundColor = node.backgroundColor;
#if !AS_PLATFORM_MACOS
    self.selectedBackgroundView = node.selectedBackgroundView;
    self.backgroundView = node.backgroundView;
#if TARGET_OS_IOS
    self.separatorInset = node.separatorInset;
#endif
    self.selectionStyle = node.selectionStyle; 
    self.focusStyle = node.focusStyle;
    self.accessoryType = node.accessoryType;
    self.isAccessibilityElement = node.isAccessibilityElement;
    self.accessibilityElementsHidden = node.accessibilityElementsHidden;
#endif
    // the following ensures that we clip the entire cell to it's bounds if node.clipsToBounds is set (the default)
    // This is actually a workaround for a bug we are seeing in some rare cases (selected background view
    // overlaps other cells if size of ASCellNode has changed.)
    self.clipsToBounds = node.clipsToBounds;

    // If the cell node has been explicitly configured with a tint color, we can apply that directly to the cell view to preserve the previous behavior
    self.tintColor = node->_tintColor;
  }
  
  [node __setSelectedFromUIKit:self.selected];
  [node __setHighlightedFromUIKit:self.highlighted];
}

- (BOOL)consumesCellNodeVisibilityEvents
{
  ASCellNode *node = self.node;
  if (node == nil) {
    return NO;
  }
  return ASSubclassOverridesSelector([ASCellNode class], [node class], @selector(cellNodeVisibilityEvent:inScrollView:withCellFrame:));
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
  [super setSelected:selected animated:animated];
  [self.node __setSelectedFromUIKit:selected];
}

- (void)setHighlighted:(BOOL)highlighted animated:(BOOL)animated
{
  [super setHighlighted:highlighted animated:animated];
  [self.node __setHighlightedFromUIKit:highlighted];
}

- (void)prepareForReuse
{
  // Need to clear element before UIKit calls setSelected:NO / setHighlighted:NO on its cells
  self.element = nil;
  [super prepareForReuse];
}

@end
#endif

#pragma mark -
#pragma mark ASTableView

#if !AS_PLATFORM_MACOS
@interface ASTableView () <ASRangeControllerDataSource, ASRangeControllerDelegate, ASDataControllerSource, ASCellNodeInteractionDelegate, ASBatchFetchingScrollView, _ASTableViewCellDelegate, ASDelegateProxyInterceptor>
#else
@interface ASTableView () <ASRangeControllerDataSource, ASRangeControllerDelegate, ASDataControllerSource, ASCellNodeInteractionDelegate, ASBatchFetchingScrollView, NSTableViewDelegate, NSTableViewDataSource>
#endif
{
#if !AS_PLATFORM_MACOS
  ASTableViewProxy *_proxyDataSource;
  ASTableViewProxy *_proxyDelegate;
#endif

  ASTableLayoutController *_layoutController;

  ASRangeController *_rangeController;

  ASBatchContext *_batchContext;

  // When we update our data controller in response to an interactive move,
  // we don't want to tell the table view about the change (it knows!)
  BOOL _updatingInResponseToInteractiveMove;
  BOOL _inverted;

  // The top cell node that was visible before the update.
  __weak ASCellNode *_contentOffsetAdjustmentTopVisibleNode;
  // The y-offset of the top visible row's origin before the update.
  CGFloat _contentOffsetAdjustmentTopVisibleNodeOffset;
  CGFloat _leadingScreensForBatching;
  BOOL _automaticallyAdjustsContentOffset;
  
  CGPoint _deceleratingVelocity;

  CGFloat _nodesConstrainedWidth;
  BOOL _queuedNodeHeightUpdate;
  BOOL _isDeallocating;
#if !AS_PLATFORM_MACOS
  NSHashTable<_ASTableViewCell *> *_cellsForVisibilityUpdates;
#endif
  
  // CountedSet because UIKit may display the same element in multiple cells e.g. during animations.
  NSCountedSet<ASCollectionElement *> *_visibleElements;
  
  NSHashTable<ASCellNode *> *_cellsForLayoutUpdates;

  // See documentation on same property in ASCollectionView
  BOOL _hasEverCheckedForBatchFetchingDueToUpdate;

  // The section index overlay view, if there is one present.
  // This is useful because we need to measure our row nodes against (width - indexView.width).
  __weak ASDisplayView *_sectionIndexView;
  
  /**
   * The change set that we're currently building, if any.
   */
  _ASHierarchyChangeSet *_changeSet;
  
  /**
   * Counter used to keep track of nested batch updates.
   */
  NSInteger _batchUpdateCount;

  /**
   * Keep a strong reference to node till view is ready to release.
   */
  ASTableNode *_keepalive_node;
#if AS_PLATFORM_MACOS
  __weak NSClipView *_as_observedClipView;
  NSPoint _as_lastObservedDocumentOrigin;
  ASScrollDirection _as_lastScrollDirection;
  BOOL _as_allowsSelectionDuringEditing;
  BOOL _as_allowsMultipleSelectionDuringEditing;
  NSIndexSet *_as_previousSelectedRows;
#endif

  struct {
    unsigned int scrollViewDidScroll:1;
    unsigned int scrollViewWillBeginDragging:1;
    unsigned int scrollViewDidEndDragging:1;
    unsigned int scrollViewWillEndDragging:1;
    unsigned int scrollViewDidEndDecelerating:1;
    unsigned int tableNodeWillDisplayNodeForRow:1;
    unsigned int tableViewWillDisplayNodeForRow:1;
    unsigned int tableViewWillDisplayNodeForRowDeprecated:1;
    unsigned int tableNodeDidEndDisplayingNodeForRow:1;
    unsigned int tableViewDidEndDisplayingNodeForRow:1;
    unsigned int tableNodeWillBeginBatchFetch:1;
    unsigned int tableViewWillBeginBatchFetch:1;
    unsigned int shouldBatchFetchForTableView:1;
    unsigned int shouldBatchFetchForTableNode:1;
    unsigned int tableViewConstrainedSizeForRow:1;
    unsigned int tableNodeConstrainedSizeForRow:1;
    unsigned int tableViewWillSelectRow:1;
    unsigned int tableNodeWillSelectRow:1;
    unsigned int tableViewDidSelectRow:1;
    unsigned int tableNodeDidSelectRow:1;
    unsigned int tableViewWillDeselectRow:1;
    unsigned int tableNodeWillDeselectRow:1;
    unsigned int tableViewDidDeselectRow:1;
    unsigned int tableNodeDidDeselectRow:1;
    unsigned int tableViewShouldHighlightRow:1;
    unsigned int tableNodeShouldHighlightRow:1;
    unsigned int tableViewDidHighlightRow:1;
    unsigned int tableNodeDidHighlightRow:1;
    unsigned int tableViewDidUnhighlightRow:1;
    unsigned int tableNodeDidUnhighlightRow:1;
    unsigned int tableViewShouldShowMenuForRow:1;
    unsigned int tableNodeShouldShowMenuForRow:1;
    unsigned int tableViewCanPerformActionForRow:1;
    unsigned int tableNodeCanPerformActionForRow:1;
    unsigned int tableViewPerformActionForRow:1;
    unsigned int tableNodePerformActionForRow:1;
  } _asyncDelegateFlags;
  
  struct {
    unsigned int numberOfSectionsInTableView:1;
    unsigned int numberOfSectionsInTableNode:1;
    unsigned int tableNodeNumberOfRowsInSection:1;
    unsigned int tableViewNumberOfRowsInSection:1;
    unsigned int tableViewNodeBlockForRow:1;
    unsigned int tableNodeNodeBlockForRow:1;
    unsigned int tableViewNodeForRow:1;
    unsigned int tableNodeNodeForRow:1;
    unsigned int tableViewCanMoveRow:1;
    unsigned int tableNodeCanMoveRow:1;
    unsigned int tableViewMoveRow:1;
    unsigned int tableNodeMoveRow:1;
    unsigned int sectionIndexMethods:1; // if both section index methods are implemented
    unsigned int modelIdentifierMethods:1; // if both modelIdentifierForElementAtIndexPath and indexPathForElementWithModelIdentifier are implemented
  } _asyncDataSourceFlags;
}

@property (nonatomic) ASDataController *dataController;

@property (nonatomic, weak)   ASTableNode *tableNode;

@property (nonatomic) BOOL test_enableSuperUpdateCallLogging;

@property (nullable, nonatomic, weak) id<ASTableDelegate> asyncDelegate;
@property (nullable, nonatomic, weak) id<ASTableDataSource> asyncDataSource;
@property (nonatomic) BOOL inverted;
@property (nonatomic) CGFloat leadingScreensForBatching;
@property (nonatomic) BOOL automaticallyAdjustsContentOffset;

#if AS_PLATFORM_MACOS
@property (nonatomic) ASEdgeInsets contentInset;
@property (nonatomic) CGPoint contentOffset;
@property (nullable, nonatomic, readonly) NSArray<NSIndexPath *> *indexPathsForVisibleRows;
@property (nullable, nonatomic, readonly) NSArray<NSIndexPath *> *indexPathsForSelectedRows;
@property (nullable, nonatomic, readonly) NSIndexPath *indexPathForSelectedRow;
#endif
@end

@implementation ASTableView
{
  __weak id<ASTableDelegate> _asyncDelegate;
  __weak id<ASTableDataSource> _asyncDataSource;
}

// Using _ASDisplayLayer ensures things like -layout are properly forwarded to ASTableNode.
#if !AS_PLATFORM_MACOS
+ (Class)layerClass
{
  return [_ASDisplayLayer class];
}
#endif

+ (Class)dataControllerClass
{
  return [ASDataController class];
}

#pragma mark -
#pragma mark Lifecycle

- (instancetype)initWithFrame:(CGRect)frame style:(ASTableViewStyle)style
{
  return [self _initWithFrame:frame style:style dataControllerClass:nil owningNode:nil];
}

- (instancetype)_initWithFrame:(CGRect)frame style:(ASTableViewStyle)style dataControllerClass:(Class)dataControllerClass owningNode:(ASTableNode *)tableNode
{
#if AS_PLATFORM_MACOS
  (void)style;
  if (!(self = [super initWithFrame:frame])) {
#else
  if (!(self = [super initWithFrame:frame style:style])) {
#endif
    return nil;
  }
#if !AS_PLATFORM_MACOS
  _cellsForVisibilityUpdates = [NSHashTable hashTableWithOptions:NSHashTableObjectPointerPersonality];
#else
  _as_lastScrollDirection = ASScrollDirectionDown;
  _as_allowsSelectionDuringEditing = NO;
  _as_allowsMultipleSelectionDuringEditing = NO;
  _as_previousSelectedRows = [NSIndexSet indexSet];
#endif
  _cellsForLayoutUpdates = [NSHashTable hashTableWithOptions:NSHashTableObjectPointerPersonality];
  if (!dataControllerClass) {
    dataControllerClass = [[self class] dataControllerClass];
  }
  
  _layoutController = [[ASTableLayoutController alloc] initWithTableView:self];
  
  _rangeController = [[ASRangeController alloc] init];
  _rangeController.layoutController = _layoutController;
  _rangeController.dataSource = self;
  _rangeController.delegate = self;
  
  _dataController = [[dataControllerClass alloc] initWithDataSource:self node:tableNode];
  _dataController.delegate = _rangeController;
  
  _leadingScreensForBatching = 2.0;
  _batchContext = [[ASBatchContext alloc] init];
  _visibleElements = [[NSCountedSet alloc] init];
  
  _automaticallyAdjustsContentOffset = NO;
  
  _nodesConstrainedWidth = self.bounds.size.width;
  
#if !AS_PLATFORM_MACOS
  _proxyDelegate = [[ASTableViewProxy alloc] initWithTarget:nil interceptor:self];
  super.delegate = (id<UITableViewDelegate>)_proxyDelegate;
  
  _proxyDataSource = [[ASTableViewProxy alloc] initWithTarget:nil interceptor:self];
  super.dataSource = (id<UITableViewDataSource>)_proxyDataSource;
  
  [self registerClass:_ASTableViewCell.class forCellReuseIdentifier:kCellReuseIdentifier];
  
  // iOS 11 automatically uses estimated heights, so disable those (see PR #485)
  super.estimatedRowHeight = 0.0;
  super.estimatedSectionHeaderHeight = 0.0;
  super.estimatedSectionFooterHeight = 0.0;
#else
  super.delegate = self;
  super.dataSource = self;
  [self _as_startObservingEnclosingScrollViewIfNeeded];
  [self _as_setNeedsRangeUpdate];
#endif
  
  return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
  NSLog(@"Warning: AsyncDisplayKit is not designed to be used with Interface Builder.  Table properties set in IB will be lost.");
  return [self initWithFrame:CGRectZero style:ASTableViewStylePlain];
}

- (void)dealloc
{
  ASDisplayNodeAssertMainThread();
  ASDisplayNodeCAssert(_batchUpdateCount == 0, @"ASTableView deallocated in the middle of a batch update.");
  
  // Sometimes the UIKit classes can call back to their delegate even during deallocation.
  _isDeallocating = YES;
#if AS_PLATFORM_MACOS
  [self _as_stopObservingEnclosingScrollView];
#endif
  if (!ASActivateExperimentalFeature(ASExperimentalCollectionTeardown)) {
    [self setAsyncDelegate:nil];
    [self setAsyncDataSource:nil];
  }
}

#if AS_PLATFORM_MACOS
- (void)setFrame:(NSRect)frameRect
{
  [super setFrame:frameRect];
  [self _as_setNeedsRangeUpdate];
}

- (void)setFrameSize:(NSSize)newSize
{
  [super setFrameSize:newSize];
  [self _as_setNeedsRangeUpdate];
}

- (void)_as_startObservingEnclosingScrollViewIfNeeded
{
  NSClipView *clipView = self.enclosingScrollView.contentView;
  if (_as_observedClipView == clipView) {
    return;
  }
  [self _as_stopObservingEnclosingScrollView];
  _as_observedClipView = clipView;
  if (clipView == nil) {
    return;
  }
  _as_lastObservedDocumentOrigin = clipView.bounds.origin;
  clipView.postsBoundsChangedNotifications = YES;
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(_as_enclosingClipViewBoundsDidChange:)
                                               name:NSViewBoundsDidChangeNotification
                                             object:clipView];
}

- (void)_as_stopObservingEnclosingScrollView
{
  if (_as_observedClipView != nil) {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:NSViewBoundsDidChangeNotification
                                                  object:_as_observedClipView];
    _as_observedClipView = nil;
  }
}

- (void)_as_enclosingClipViewBoundsDidChange:(NSNotification *)notification
{
  NSClipView *clipView = (NSClipView *)notification.object;
  NSPoint newOrigin = clipView.bounds.origin;
  if (newOrigin.y > _as_lastObservedDocumentOrigin.y) {
    _as_lastScrollDirection = ASScrollDirectionDown;
  } else if (newOrigin.y < _as_lastObservedDocumentOrigin.y) {
    _as_lastScrollDirection = ASScrollDirectionUp;
  }
  _as_lastObservedDocumentOrigin = newOrigin;
  [self _as_setNeedsRangeUpdate];
}

- (void)_as_setNeedsRangeUpdate
{
  [self.rangeController setNeedsUpdate];
  [self.rangeController updateIfNeeded];
}
#endif

#pragma mark -
#pragma mark Overrides

- (void)setDataSource:(id
#if AS_PLATFORM_MACOS
                    <NSTableViewDataSource>
#else
                    <UITableViewDataSource>
#endif
                    )dataSource
{
  // The backing view can internally generate this call while changing asyncDataSource; only assert for non-nil.
  ASDisplayNodeAssert(dataSource == nil, @"ASTableView uses asyncDataSource, not the platform dataSource property.");
}

- (void)setDelegate:(id
#if AS_PLATFORM_MACOS
                  <NSTableViewDelegate>
#else
                  <UITableViewDelegate>
#endif
                  )delegate
{
  // The backing view clears delegate on teardown. Only assert if we get a non-nil value here.
  ASDisplayNodeAssert(delegate == nil, @"ASTableView uses asyncDelegate, not the platform delegate property.");
}

- (id<ASTableDataSource>)asyncDataSource
{
  return _asyncDataSource;
}

- (void)setAsyncDataSource:(id<ASTableDataSource>)asyncDataSource
{
  // Changing super.dataSource will trigger a setNeedsLayout, so this must happen on the main thread.
  ASDisplayNodeAssertMainThread();

  // Note: It's common to check if the value hasn't changed and short-circuit but we aren't doing that here to handle
  // the (common) case of nilling the asyncDataSource in the ViewController's dealloc. In this case our _asyncDataSource
  // will return as nil (ARC magic) even though the _proxyDataSource still exists. It's really important to hold a strong
  // reference to the old dataSource in this case because calls to ASTableViewProxy will start failing and cause crashes.
  NS_VALID_UNTIL_END_OF_SCOPE id oldDataSource = self.dataSource;
  
  if (asyncDataSource == nil) {
    _asyncDataSource = nil;
#if !AS_PLATFORM_MACOS
    _proxyDataSource = _isDeallocating ? nil : [[ASTableViewProxy alloc] initWithTarget:nil interceptor:self];
#endif
    
    memset(&_asyncDataSourceFlags, 0, sizeof(_asyncDataSourceFlags));
  } else {
    _asyncDataSource = asyncDataSource;
#if !AS_PLATFORM_MACOS
    _proxyDataSource = [[ASTableViewProxy alloc] initWithTarget:_asyncDataSource interceptor:self];
#endif
    
    _asyncDataSourceFlags.numberOfSectionsInTableView = [_asyncDataSource respondsToSelector:@selector(numberOfSectionsInTableView:)];
    _asyncDataSourceFlags.numberOfSectionsInTableNode = [_asyncDataSource respondsToSelector:@selector(numberOfSectionsInTableNode:)];
    _asyncDataSourceFlags.tableViewNumberOfRowsInSection = [_asyncDataSource respondsToSelector:@selector(tableView:numberOfRowsInSection:)];
    _asyncDataSourceFlags.tableNodeNumberOfRowsInSection = [_asyncDataSource respondsToSelector:@selector(tableNode:numberOfRowsInSection:)];
    _asyncDataSourceFlags.tableViewNodeForRow = [_asyncDataSource respondsToSelector:@selector(tableView:nodeForRowAtIndexPath:)];
    _asyncDataSourceFlags.tableNodeNodeForRow = [_asyncDataSource respondsToSelector:@selector(tableNode:nodeForRowAtIndexPath:)];
    _asyncDataSourceFlags.tableViewNodeBlockForRow = [_asyncDataSource respondsToSelector:@selector(tableView:nodeBlockForRowAtIndexPath:)];
    _asyncDataSourceFlags.tableNodeNodeBlockForRow = [_asyncDataSource respondsToSelector:@selector(tableNode:nodeBlockForRowAtIndexPath:)];
    _asyncDataSourceFlags.tableViewCanMoveRow = [_asyncDataSource respondsToSelector:@selector(tableView:canMoveRowAtIndexPath:)];
    _asyncDataSourceFlags.tableViewMoveRow = [_asyncDataSource respondsToSelector:@selector(tableView:moveRowAtIndexPath:toIndexPath:)];
    _asyncDataSourceFlags.sectionIndexMethods = [_asyncDataSource respondsToSelector:@selector(sectionIndexTitlesForTableView:)] && [_asyncDataSource respondsToSelector:@selector(tableView:sectionForSectionIndexTitle:atIndex:)];
    _asyncDataSourceFlags.modelIdentifierMethods = [_asyncDataSource respondsToSelector:@selector(modelIdentifierForElementAtIndexPath:inNode:)] && [_asyncDataSource respondsToSelector:@selector(indexPathForElementWithModelIdentifier:inNode:)];
    
    ASDisplayNodeAssert(_asyncDataSourceFlags.tableViewNodeBlockForRow
                        || _asyncDataSourceFlags.tableViewNodeForRow
                        || _asyncDataSourceFlags.tableNodeNodeBlockForRow
                        || _asyncDataSourceFlags.tableNodeNodeForRow, @"Data source must implement tableNode:nodeBlockForRowAtIndexPath: or tableNode:nodeForRowAtIndexPath:");
    ASDisplayNodeAssert(_asyncDataSourceFlags.tableNodeNumberOfRowsInSection || _asyncDataSourceFlags.tableViewNumberOfRowsInSection, @"Data source must implement tableNode:numberOfRowsInSection:");
  }
  
  _dataController.validationErrorSource = asyncDataSource;
#if !AS_PLATFORM_MACOS
  super.dataSource = (id<UITableViewDataSource>)_proxyDataSource;
#else
  super.dataSource = self;
#endif
  [self _asyncDelegateOrDataSourceDidChange];
}

- (id<ASTableDelegate>)asyncDelegate
{
  return _asyncDelegate;
}

- (void)setAsyncDelegate:(id<ASTableDelegate>)asyncDelegate
{
  // Changing super.delegate will trigger a setNeedsLayout, so this must happen on the main thread.
  ASDisplayNodeAssertMainThread();

  // Note: It's common to check if the value hasn't changed and short-circuit but we aren't doing that here to handle
  // the (common) case of nilling the asyncDelegate in the ViewController's dealloc. In this case our _asyncDelegate
  // will return as nil (ARC magic) even though the _proxyDataSource still exists. It's really important to hold a strong
  // reference to the old delegate in this case because calls to ASTableViewProxy will start failing and cause crashes.
  NS_VALID_UNTIL_END_OF_SCOPE id oldDelegate = super.delegate;
  
  if (asyncDelegate == nil) {
    _asyncDelegate = nil;
#if !AS_PLATFORM_MACOS
    _proxyDelegate = _isDeallocating ? nil : [[ASTableViewProxy alloc] initWithTarget:nil interceptor:self];
#endif
    
    memset(&_asyncDelegateFlags, 0, sizeof(_asyncDelegateFlags));
  } else {
    _asyncDelegate = asyncDelegate;
#if !AS_PLATFORM_MACOS
    _proxyDelegate = [[ASTableViewProxy alloc] initWithTarget:_asyncDelegate interceptor:self];
#endif
    
    _asyncDelegateFlags.scrollViewDidScroll = [_asyncDelegate respondsToSelector:@selector(scrollViewDidScroll:)];

    _asyncDelegateFlags.tableViewWillDisplayNodeForRow = [_asyncDelegate respondsToSelector:@selector(tableView:willDisplayNode:forRowAtIndexPath:)];
    _asyncDelegateFlags.tableNodeWillDisplayNodeForRow = [_asyncDelegate respondsToSelector:@selector(tableNode:willDisplayRowWithNode:)];
    if (_asyncDelegateFlags.tableViewWillDisplayNodeForRow == NO) {
      _asyncDelegateFlags.tableViewWillDisplayNodeForRowDeprecated = [_asyncDelegate respondsToSelector:@selector(tableView:willDisplayNodeForRowAtIndexPath:)];
    }
    _asyncDelegateFlags.tableViewDidEndDisplayingNodeForRow = [_asyncDelegate respondsToSelector:@selector(tableView:didEndDisplayingNode:forRowAtIndexPath:)];
    _asyncDelegateFlags.tableNodeDidEndDisplayingNodeForRow = [_asyncDelegate respondsToSelector:@selector(tableNode:didEndDisplayingRowWithNode:)];
    _asyncDelegateFlags.scrollViewWillEndDragging = [_asyncDelegate respondsToSelector:@selector(scrollViewWillEndDragging:withVelocity:targetContentOffset:)];
    _asyncDelegateFlags.scrollViewDidEndDecelerating = [_asyncDelegate respondsToSelector:@selector(scrollViewDidEndDecelerating:)];
    _asyncDelegateFlags.tableViewWillBeginBatchFetch = [_asyncDelegate respondsToSelector:@selector(tableView:willBeginBatchFetchWithContext:)];
    _asyncDelegateFlags.tableNodeWillBeginBatchFetch = [_asyncDelegate respondsToSelector:@selector(tableNode:willBeginBatchFetchWithContext:)];
    _asyncDelegateFlags.shouldBatchFetchForTableView = [_asyncDelegate respondsToSelector:@selector(shouldBatchFetchForTableView:)];
    _asyncDelegateFlags.shouldBatchFetchForTableNode = [_asyncDelegate respondsToSelector:@selector(shouldBatchFetchForTableNode:)];
    _asyncDelegateFlags.scrollViewWillBeginDragging = [_asyncDelegate respondsToSelector:@selector(scrollViewWillBeginDragging:)];
    _asyncDelegateFlags.scrollViewDidEndDragging = [_asyncDelegate respondsToSelector:@selector(scrollViewDidEndDragging:willDecelerate:)];
    _asyncDelegateFlags.tableViewConstrainedSizeForRow = [_asyncDelegate respondsToSelector:@selector(tableView:constrainedSizeForRowAtIndexPath:)];
    _asyncDelegateFlags.tableNodeConstrainedSizeForRow = [_asyncDelegate respondsToSelector:@selector(tableNode:constrainedSizeForRowAtIndexPath:)];

    _asyncDelegateFlags.tableViewWillSelectRow = [_asyncDelegate respondsToSelector:@selector(tableView:willSelectRowAtIndexPath:)];
    _asyncDelegateFlags.tableNodeWillSelectRow = [_asyncDelegate respondsToSelector:@selector(tableNode:willSelectRowAtIndexPath:)];
    _asyncDelegateFlags.tableViewDidSelectRow = [_asyncDelegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)];
    _asyncDelegateFlags.tableNodeDidSelectRow = [_asyncDelegate respondsToSelector:@selector(tableNode:didSelectRowAtIndexPath:)];
    _asyncDelegateFlags.tableViewWillDeselectRow = [_asyncDelegate respondsToSelector:@selector(tableView:willDeselectRowAtIndexPath:)];
    _asyncDelegateFlags.tableNodeWillDeselectRow = [_asyncDelegate respondsToSelector:@selector(tableNode:willDeselectRowAtIndexPath:)];
    _asyncDelegateFlags.tableViewDidDeselectRow = [_asyncDelegate respondsToSelector:@selector(tableView:didDeselectRowAtIndexPath:)];
    _asyncDelegateFlags.tableNodeDidDeselectRow = [_asyncDelegate respondsToSelector:@selector(tableNode:didDeselectRowAtIndexPath:)];
    _asyncDelegateFlags.tableViewShouldHighlightRow = [_asyncDelegate respondsToSelector:@selector(tableView:shouldHighlightRowAtIndexPath:)];
    _asyncDelegateFlags.tableNodeShouldHighlightRow = [_asyncDelegate respondsToSelector:@selector(tableNode:shouldHighlightRowAtIndexPath:)];
    _asyncDelegateFlags.tableViewDidHighlightRow = [_asyncDelegate respondsToSelector:@selector(tableView:didHighlightRowAtIndexPath:)];
    _asyncDelegateFlags.tableNodeDidHighlightRow = [_asyncDelegate respondsToSelector:@selector(tableNode:didHighlightRowAtIndexPath:)];
    _asyncDelegateFlags.tableViewDidUnhighlightRow = [_asyncDelegate respondsToSelector:@selector(tableView:didUnhighlightRowAtIndexPath:)];
    _asyncDelegateFlags.tableNodeDidUnhighlightRow = [_asyncDelegate respondsToSelector:@selector(tableNode:didUnhighlightRowAtIndexPath:)];
    _asyncDelegateFlags.tableViewShouldShowMenuForRow = [_asyncDelegate respondsToSelector:@selector(tableView:shouldShowMenuForRowAtIndexPath:)];
    _asyncDelegateFlags.tableNodeShouldShowMenuForRow = [_asyncDelegate respondsToSelector:@selector(tableNode:shouldShowMenuForRowAtIndexPath:)];
    _asyncDelegateFlags.tableViewCanPerformActionForRow = [_asyncDelegate respondsToSelector:@selector(tableView:canPerformAction:forRowAtIndexPath:withSender:)];
    _asyncDelegateFlags.tableNodeCanPerformActionForRow = [_asyncDelegate respondsToSelector:@selector(tableNode:canPerformAction:forRowAtIndexPath:withSender:)];
    _asyncDelegateFlags.tableViewPerformActionForRow = [_asyncDelegate respondsToSelector:@selector(tableView:performAction:forRowAtIndexPath:withSender:)];
    _asyncDelegateFlags.tableNodePerformActionForRow = [_asyncDelegate respondsToSelector:@selector(tableNode:performAction:forRowAtIndexPath:withSender:)];
  }
  
#if !AS_PLATFORM_MACOS
  super.delegate = (id<UITableViewDelegate>)_proxyDelegate;
#else
  super.delegate = self;
#endif
  [self _asyncDelegateOrDataSourceDidChange];
}

- (void)_asyncDelegateOrDataSourceDidChange
{
  ASDisplayNodeAssertMainThread();
 
  if (_asyncDataSource == nil && _asyncDelegate == nil && !ASActivateExperimentalFeature(ASExperimentalSkipClearData)) {
    [_dataController clearData];
  }
}

#if !AS_PLATFORM_MACOS
- (void)proxyTargetHasDeallocated:(ASDelegateProxy *)proxy
{
  if (proxy == _proxyDelegate) {
    [self setAsyncDelegate:nil];
  } else if (proxy == _proxyDataSource) {
    [self setAsyncDataSource:nil];
  }
}
#endif

- (void)reloadDataWithCompletion:(void (^)())completion
{
  ASDisplayNodeAssertMainThread();
  
  if (! _dataController.initialReloadDataHasBeenCalled) {
    // If this is the first reload, forward to super immediately to prevent it from triggering more "initial" loads while our data controller is working. 
    [super reloadData];
  }
  
  void (^batchUpdatesCompletion)(BOOL);
  if (completion) {
    batchUpdatesCompletion = ^(BOOL) {
      completion();
    };
  }
  
  [self beginUpdates];
  [_changeSet reloadData];
  [self endUpdatesWithCompletion:batchUpdatesCompletion];
}

- (void)reloadData
{
  [self reloadDataWithCompletion:nil];
}

- (void)scrollToRowAtIndexPath:(NSIndexPath *)indexPath atScrollPosition:(ASTableViewScrollPosition)scrollPosition animated:(BOOL)animated
{
  if ([self validateIndexPath:indexPath]) {
#if AS_PLATFORM_MACOS
    NSInteger row = [self flatRowForIndexPath:indexPath inMap:self.dataController.visibleMap];
    if (row == NSNotFound) {
      return;
    }
    NSRect rowRect = [self rectOfRow:row];
    NSScrollView *scrollView = self.enclosingScrollView;
    NSClipView *clipView = scrollView.contentView;
    NSPoint targetOrigin = clipView.bounds.origin;
    CGFloat viewportHeight = clipView.bounds.size.height;
    CGFloat maxY = MAX(0.0, self.bounds.size.height - viewportHeight);
    switch (scrollPosition) {
      case ASTableViewScrollPositionTop:
        targetOrigin.y = NSMinY(rowRect);
        break;
      case ASTableViewScrollPositionMiddle:
        targetOrigin.y = NSMidY(rowRect) - (viewportHeight * 0.5);
        break;
      case ASTableViewScrollPositionBottom:
        targetOrigin.y = NSMaxY(rowRect) - viewportHeight;
        break;
      case ASTableViewScrollPositionNone:
      default:
        [self scrollRowToVisible:row];
        return;
    }
    targetOrigin.y = MIN(maxY, MAX(0.0, targetOrigin.y));
    if (animated) {
      [[clipView animator] setBoundsOrigin:targetOrigin];
    } else {
      [clipView scrollToPoint:targetOrigin];
    }
    [scrollView reflectScrolledClipView:clipView];
#else
    [super scrollToRowAtIndexPath:indexPath atScrollPosition:scrollPosition animated:animated];
#endif
  }
}

- (CGRect)rectForRowAtIndexPath:(NSIndexPath *)indexPath
{
  indexPath = [self validateIndexPath:indexPath];
  if (indexPath == nil) {
    return CGRectZero;
  }
#if AS_PLATFORM_MACOS
  NSInteger row = [self flatRowForIndexPath:indexPath inMap:self.dataController.visibleMap];
  if (row == NSNotFound) {
    return CGRectZero;
  }
  return [self rectOfRow:row];
#else
  return [super rectForRowAtIndexPath:indexPath];
#endif
}

#if AS_PLATFORM_MACOS
- (void)selectRowAtIndexPath:(NSIndexPath *)indexPath animated:(BOOL)animated scrollPosition:(ASTableViewScrollPosition)scrollPosition
{
  (void)animated;
  indexPath = [self validateIndexPath:indexPath];
  if (indexPath == nil) {
    [self deselectAll:nil];
    return;
  }
  NSInteger row = [self flatRowForIndexPath:indexPath inMap:self.dataController.visibleMap];
  if (row == NSNotFound) {
    return;
  }
  [self selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
  [self scrollToRowAtIndexPath:indexPath atScrollPosition:scrollPosition animated:NO];
}

- (void)deselectRowAtIndexPath:(NSIndexPath *)indexPath animated:(BOOL)animated
{
  (void)animated;
  indexPath = [self validateIndexPath:indexPath];
  if (indexPath == nil) {
    return;
  }
  NSInteger row = [self flatRowForIndexPath:indexPath inMap:self.dataController.visibleMap];
  if (row != NSNotFound) {
    [self deselectRow:(NSInteger)row];
  }
}

- (void)setAllowsSelection:(BOOL)allowsSelection
{
  self.allowsEmptySelection = !allowsSelection;
  if (!allowsSelection) {
    [self deselectAll:nil];
  }
}

- (BOOL)allowsSelection
{
  return !self.allowsEmptySelection;
}

- (void)setAllowsSelectionDuringEditing:(BOOL)allowsSelectionDuringEditing
{
  _as_allowsSelectionDuringEditing = allowsSelectionDuringEditing;
}

- (BOOL)allowsSelectionDuringEditing
{
  return _as_allowsSelectionDuringEditing;
}

- (void)setAllowsMultipleSelectionDuringEditing:(BOOL)allowsMultipleSelectionDuringEditing
{
  _as_allowsMultipleSelectionDuringEditing = allowsMultipleSelectionDuringEditing;
}

- (BOOL)allowsMultipleSelectionDuringEditing
{
  return _as_allowsMultipleSelectionDuringEditing;
}

- (NSIndexPath *)indexPathForSelectedRow
{
  NSInteger selectedRow = self.selectedRow;
  if (selectedRow < 0) {
    return nil;
  }
  return [self indexPathForFlatRow:selectedRow inMap:self.dataController.visibleMap];
}

- (NSArray<NSIndexPath *> *)indexPathsForSelectedRows
{
  NSIndexSet *selected = self.selectedRowIndexes;
  if (selected.count == 0) {
    return nil;
  }
  NSMutableArray<NSIndexPath *> *result = [NSMutableArray arrayWithCapacity:selected.count];
  [selected enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
    (void)stop;
    NSIndexPath *indexPath = [self indexPathForFlatRow:(NSInteger)idx inMap:self.dataController.visibleMap];
    if (indexPath != nil) {
      [result addObject:indexPath];
    }
  }];
  return result;
}

- (NSIndexPath *)indexPathForRowAtPoint:(CGPoint)point
{
  NSInteger row = [self rowAtPoint:point];
  if (row < 0) {
    return nil;
  }
  return [self indexPathForFlatRow:row inMap:self.dataController.visibleMap];
}

- (NSArray<NSIndexPath *> *)indexPathsForRowsInRect:(CGRect)rect
{
  NSRange rows = [self rowsInRect:rect];
  if (rows.location == NSNotFound || rows.length == 0) {
    return @[];
  }
  NSMutableArray<NSIndexPath *> *result = [NSMutableArray arrayWithCapacity:rows.length];
  NSUInteger rowEnd = NSMaxRange(rows);
  for (NSUInteger row = rows.location; row < rowEnd; row++) {
    NSIndexPath *indexPath = [self indexPathForFlatRow:(NSInteger)row inMap:self.dataController.visibleMap];
    if (indexPath != nil) {
      [result addObject:indexPath];
    }
  }
  return result;
}

- (NSArray<NSIndexPath *> *)indexPathsForVisibleRows
{
  return [self indexPathsForRowsInRect:self.visibleRect];
}

- (ASEdgeInsets)contentInset
{
  NSScrollView *scrollView = self.enclosingScrollView;
  return (scrollView != nil) ? scrollView.contentInsets : ASEdgeInsetsZero;
}

- (void)setContentInset:(ASEdgeInsets)contentInset
{
  NSScrollView *scrollView = self.enclosingScrollView;
  if (scrollView != nil) {
    scrollView.contentInsets = contentInset;
    [self _as_setNeedsRangeUpdate];
  }
}

- (CGPoint)contentOffset
{
  NSClipView *clipView = self.enclosingScrollView.contentView;
  return (clipView != nil) ? clipView.bounds.origin : CGPointZero;
}

- (void)setContentOffset:(CGPoint)contentOffset
{
  [self setContentOffset:contentOffset animated:NO];
}

- (void)setContentOffset:(CGPoint)contentOffset animated:(BOOL)animated
{
  NSScrollView *scrollView = self.enclosingScrollView;
  NSClipView *clipView = scrollView.contentView;
  if (clipView == nil) {
    return;
  }
  if (animated) {
    [[clipView animator] setBoundsOrigin:contentOffset];
  } else {
    [clipView scrollToPoint:contentOffset];
  }
  [scrollView reflectScrolledClipView:clipView];
}
#endif

- (void)relayoutItems
{
  [_dataController relayoutAllNodesWithInvalidationBlock:nil];
}

- (void)setTuningParameters:(ASRangeTuningParameters)tuningParameters forRangeType:(ASLayoutRangeType)rangeType
{
  [_rangeController setTuningParameters:tuningParameters forRangeMode:ASLayoutRangeModeFull rangeType:rangeType];
}

- (ASRangeTuningParameters)tuningParametersForRangeType:(ASLayoutRangeType)rangeType
{
  return [_rangeController tuningParametersForRangeMode:ASLayoutRangeModeFull rangeType:rangeType];
}

- (void)setTuningParameters:(ASRangeTuningParameters)tuningParameters forRangeMode:(ASLayoutRangeMode)rangeMode rangeType:(ASLayoutRangeType)rangeType
{
  [_rangeController setTuningParameters:tuningParameters forRangeMode:rangeMode rangeType:rangeType];
}

- (ASRangeTuningParameters)tuningParametersForRangeMode:(ASLayoutRangeMode)rangeMode rangeType:(ASLayoutRangeType)rangeType
{
  return [_rangeController tuningParametersForRangeMode:rangeMode rangeType:rangeType];
}

- (ASElementMap *)elementMapForRangeController:(ASRangeController *)rangeController
{
  return _dataController.visibleMap;
}

- (ASCellNode *)nodeForRowAtIndexPath:(NSIndexPath *)indexPath
{
  indexPath = [self validateIndexPath:indexPath];
  if (indexPath == nil) {
    return nil;
  }
  return [_dataController.visibleMap elementForItemAtIndexPath:indexPath].node;
}

- (NSIndexPath *)convertIndexPathFromTableNode:(NSIndexPath *)indexPath waitingIfNeeded:(BOOL)wait
{
  NSIndexPath *viewIndexPath = [_dataController.visibleMap convertIndexPath:indexPath fromMap:_dataController.pendingMap];
  if (viewIndexPath == nil && wait) {
    [self waitUntilAllUpdatesAreCommitted];
    return [self convertIndexPathFromTableNode:indexPath waitingIfNeeded:NO];
  }
  return viewIndexPath;
}

- (NSIndexPath *)convertIndexPathToTableNode:(NSIndexPath *)indexPath
{
  if ([self validateIndexPath:indexPath] == nil) {
    return nil;
  }

  return [_dataController.pendingMap convertIndexPath:indexPath fromMap:_dataController.visibleMap];
}

- (NSArray<NSIndexPath *> *)convertIndexPathsToTableNode:(NSArray<NSIndexPath *> *)indexPaths
{
  if (indexPaths == nil) {
    return nil;
  }

  NSMutableArray<NSIndexPath *> *indexPathsArray = [NSMutableArray new];

  for (NSIndexPath *indexPathInView in indexPaths) {
    NSIndexPath *indexPath = [self convertIndexPathToTableNode:indexPathInView];
    if (indexPath != nil) {
      [indexPathsArray addObject:indexPath];
    }
  }
  return indexPathsArray;
}

- (NSInteger)flatRowForIndexPath:(NSIndexPath *)indexPath inMap:(ASElementMap *)map
{
  if (indexPath == nil || map == nil) {
    return NSNotFound;
  }
  NSInteger section = indexPath.section;
  NSInteger item = indexPath.item;
  if (section < 0 || section >= map.numberOfSections || item < 0 || item >= [map numberOfItemsInSection:section]) {
    return NSNotFound;
  }
  NSInteger flatRow = item;
  for (NSInteger currentSection = 0; currentSection < section; currentSection++) {
    flatRow += [map numberOfItemsInSection:currentSection];
  }
  return flatRow;
}

- (NSIndexPath *)indexPathForFlatRow:(NSInteger)row inMap:(ASElementMap *)map
{
  if (map == nil || row < 0) {
    return nil;
  }
  NSInteger remaining = row;
  NSInteger sectionCount = map.numberOfSections;
  for (NSInteger section = 0; section < sectionCount; section++) {
    NSInteger itemCount = [map numberOfItemsInSection:section];
    if (remaining < itemCount) {
      return [NSIndexPath indexPathForItem:remaining inSection:section];
    }
    remaining -= itemCount;
  }
  return nil;
}

- (NSIndexSet *)_rowIndexesForIndexPaths:(NSArray<NSIndexPath *> *)indexPaths inMap:(ASElementMap *)map
{
  NSMutableIndexSet *result = [NSMutableIndexSet indexSet];
  for (NSIndexPath *indexPath in indexPaths) {
    NSInteger row = [self flatRowForIndexPath:indexPath inMap:map];
    if (row != NSNotFound) {
      [result addIndex:(NSUInteger)row];
    }
  }
  return result;
}

- (NSIndexSet *)_rowIndexesForSections:(NSIndexSet *)sections inMap:(ASElementMap *)map
{
  if (sections.count == 0 || map == nil) {
    return [NSIndexSet indexSet];
  }
  NSMutableIndexSet *result = [NSMutableIndexSet indexSet];
  [sections enumerateIndexesUsingBlock:^(NSUInteger section, BOOL * _Nonnull stop) {
    (void)stop;
    if (section >= (NSUInteger)map.numberOfSections) {
      return;
    }
    NSInteger sectionStart = 0;
    for (NSInteger currentSection = 0; currentSection < (NSInteger)section; currentSection++) {
      sectionStart += [map numberOfItemsInSection:currentSection];
    }
    NSInteger sectionCount = [map numberOfItemsInSection:(NSInteger)section];
    if (sectionCount > 0) {
      [result addIndexesInRange:NSMakeRange((NSUInteger)sectionStart, (NSUInteger)sectionCount)];
    }
  }];
  return result;
}

- (NSIndexSet *)_tableColumnIndexes
{
#if AS_PLATFORM_MACOS
  NSInteger columnCount = MAX(1, self.numberOfColumns);
  return [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, (NSUInteger)columnCount)];
#else
  return [NSIndexSet indexSet];
#endif
}

- (NSIndexPath *)indexPathForNode:(ASCellNode *)cellNode
{
  return [self indexPathForNode:cellNode waitingIfNeeded:NO];
}

/**
 * Asserts that the index path is a valid view-index-path, and returns it if so, nil otherwise.
 */
- (nullable NSIndexPath *)validateIndexPath:(nullable NSIndexPath *)indexPath
{
  if (indexPath == nil) {
    return nil;
  }

  NSInteger section = indexPath.section;
#if AS_PLATFORM_MACOS
  ASElementMap *map = _dataController.visibleMap ?: _dataController.pendingMap;
  NSInteger sectionCount = map.numberOfSections;
#else
  NSInteger sectionCount = self.numberOfSections;
#endif
  if (section >= sectionCount || section < 0) {
    ASDisplayNodeFailAssert(@"Table view index path has invalid section %lu, section count = %lu", (unsigned long)section, (unsigned long)sectionCount);
    return nil;
  }

  NSInteger item = indexPath.item;
  // item == NSNotFound means e.g. "scroll to this section" and is acceptable
  NSInteger itemCount = NSNotFound;
#if AS_PLATFORM_MACOS
  itemCount = [map numberOfItemsInSection:section];
#else
  itemCount = [self numberOfRowsInSection:section];
#endif
  if (item != NSNotFound && (item >= itemCount || item < 0)) {
    ASDisplayNodeFailAssert(@"Table view index path has invalid item %lu in section %lu, item count = %lu", (unsigned long)indexPath.item, (unsigned long)section, (unsigned long)itemCount);
    return nil;
  }

  return indexPath;
}

- (nullable NSIndexPath *)indexPathForNode:(ASCellNode *)cellNode waitingIfNeeded:(BOOL)wait
{
  if (cellNode == nil) {
    return nil;
  }

  NSIndexPath *indexPath = [_dataController.visibleMap indexPathForElement:cellNode.collectionElement];
  indexPath = [self validateIndexPath:indexPath];
  if (indexPath == nil && wait) {
    [self waitUntilAllUpdatesAreCommitted];
    return [self indexPathForNode:cellNode waitingIfNeeded:NO];
  }
  return indexPath;
}

- (NSArray<ASCellNode *> *)visibleNodes
{
  const auto elements = [self visibleElementsForRangeController:_rangeController];
  return ASArrayByFlatMapping(elements, ASCollectionElement *e, e.node);
}

- (void)beginUpdates
{
  ASDisplayNodeAssertMainThread();
  // _changeSet must be available during batch update
  ASDisplayNodeAssertTrue((_batchUpdateCount > 0) == (_changeSet != nil));
  
  if (_batchUpdateCount == 0) {
    _changeSet = [[_ASHierarchyChangeSet alloc] initWithOldData:[_dataController itemCountsFromDataSource]];
  }
  _batchUpdateCount++;
}

- (void)endUpdates
{
  [self endUpdatesWithCompletion:nil];
}

- (void)endUpdatesWithCompletion:(void (^)(BOOL completed))completion
{
  // We capture the current state of whether animations are enabled if they don't provide us with one.
#if AS_PLATFORM_MACOS
  [self endUpdatesAnimated:YES completion:completion];
#else
  [self endUpdatesAnimated:[ASDisplayView areAnimationsEnabled] completion:completion];
#endif
}

- (void)endUpdatesAnimated:(BOOL)animated completion:(void (^)(BOOL completed))completion
{
  ASDisplayNodeAssertMainThread();
  ASDisplayNodeAssertNotNil(_changeSet, @"_changeSet must be available when batch update ends");
  
  _batchUpdateCount--;
  // Prevent calling endUpdatesAnimated:completion: in an unbalanced way
  NSAssert(_batchUpdateCount >= 0, @"endUpdatesAnimated:completion: called without having a balanced beginUpdates call");
  
  [_changeSet addCompletionHandler:completion];

  if (_batchUpdateCount == 0) {
    _ASHierarchyChangeSet *changeSet = _changeSet;
    // Nil out _changeSet before forwarding to _dataController to allow the change set to cause subsequent batch updates on the same run loop
    _changeSet = nil;
    changeSet.animated = animated;
    [_dataController updateWithChangeSet:changeSet];
  } 
}

- (BOOL)isProcessingUpdates
{
  return [_dataController isProcessingUpdates];
}

- (void)onDidFinishProcessingUpdates:(void (^)())completion
{
  [_dataController onDidFinishProcessingUpdates:completion];
}

- (void)waitUntilAllUpdatesAreCommitted
{
  ASDisplayNodeAssertMainThread();
  if (_batchUpdateCount > 0) {
    // This assertion will be enabled soon.
    //    ASDisplayNodeFailAssert(@"Should not call %@ during batch update", NSStringFromSelector(_cmd));
    return;
  }

  [_dataController waitUntilAllUpdatesAreProcessed];
}

#if !AS_PLATFORM_MACOS
- (void)layoutSubviews
{
  // Remeasure all rows if our row width has changed.
  ASEdgeInsets contentInset = self.contentInset;
  CGFloat constrainedWidth = self.bounds.size.width - [self sectionIndexWidth] - contentInset.left - contentInset.right;
  if (constrainedWidth > 0 && _nodesConstrainedWidth != constrainedWidth) {
    _nodesConstrainedWidth = constrainedWidth;
    [_cellsForLayoutUpdates removeAllObjects];

    [self beginUpdates];
    [_dataController relayoutAllNodesWithInvalidationBlock:nil];
    [self endUpdatesAnimated:(ASDisplayNodeLayerHasAnimations(self.layer) == NO) completion:nil];
  } else {
    if (_cellsForLayoutUpdates.count > 0) {
      NSArray<ASCellNode *> *nodes = [_cellsForLayoutUpdates allObjects];
      [_cellsForLayoutUpdates removeAllObjects];

      const auto nodesSizeChanged = [[NSMutableArray<ASCellNode *> alloc] init];
      [_dataController relayoutNodes:nodes nodesSizeChanged:nodesSizeChanged];
      if (nodesSizeChanged.count > 0) {
        [self requeryNodeHeights];
      }
    }
  }

  // To ensure _nodesConstrainedWidth is up-to-date for every usage, this call to super must be done last
  [super layoutSubviews];
  [_rangeController updateIfNeeded];
}
#else
- (void)layout
{
  [super layout];
  [_rangeController updateIfNeeded];
}
#endif

#pragma mark -
#pragma mark Editing

- (void)insertSections:(NSIndexSet *)sections withRowAnimation:(ASTableViewRowAnimation)animation
{
  ASDisplayNodeAssertMainThread();
  if (sections.count == 0) { return; }
  [self beginUpdates];
  [_changeSet insertSections:sections animationOptions:animation];
  [self endUpdates];
}

- (void)deleteSections:(NSIndexSet *)sections withRowAnimation:(ASTableViewRowAnimation)animation
{
  ASDisplayNodeAssertMainThread();
  if (sections.count == 0) { return; }
  [self beginUpdates];
  [_changeSet deleteSections:sections animationOptions:animation];
  [self endUpdates];
}

- (void)reloadSections:(NSIndexSet *)sections withRowAnimation:(ASTableViewRowAnimation)animation
{
  ASDisplayNodeAssertMainThread();
  if (sections.count == 0) { return; }
  [self beginUpdates];
  [_changeSet reloadSections:sections animationOptions:animation];
  [self endUpdates];
}

- (void)moveSection:(NSInteger)section toSection:(NSInteger)newSection
{
  ASDisplayNodeAssertMainThread();
  [self beginUpdates];
  [_changeSet moveSection:section toSection:newSection animationOptions:ASTableViewRowAnimationNone];
  [self endUpdates];
}

- (void)insertRowsAtIndexPaths:(NSArray *)indexPaths withRowAnimation:(ASTableViewRowAnimation)animation
{
  ASDisplayNodeAssertMainThread();
  if (indexPaths.count == 0) { return; }
  [self beginUpdates];
  [_changeSet insertItems:indexPaths animationOptions:animation];
  [self endUpdates];
}

- (void)deleteRowsAtIndexPaths:(NSArray *)indexPaths withRowAnimation:(ASTableViewRowAnimation)animation
{
  ASDisplayNodeAssertMainThread();
  if (indexPaths.count == 0) { return; }
  [self beginUpdates];
  [_changeSet deleteItems:indexPaths animationOptions:animation];
  [self endUpdates];
}

- (void)reloadRowsAtIndexPaths:(NSArray *)indexPaths withRowAnimation:(ASTableViewRowAnimation)animation
{
  ASDisplayNodeAssertMainThread();
  if (indexPaths.count == 0) { return; }
  [self beginUpdates];
  [_changeSet reloadItems:indexPaths animationOptions:animation];
  [self endUpdates];
}

- (void)moveRowAtIndexPath:(NSIndexPath *)indexPath toIndexPath:(NSIndexPath *)newIndexPath
{
  ASDisplayNodeAssertMainThread();
  [self beginUpdates];
  [_changeSet moveItemAtIndexPath:indexPath toIndexPath:newIndexPath animationOptions:ASTableViewRowAnimationNone];
  [self endUpdates];
}

#pragma mark -
#pragma mark adjust content offset

- (void)beginAdjustingContentOffset
{
  NSIndexPath *firstVisibleIndexPath = [self.indexPathsForVisibleRows sortedArrayUsingSelector:@selector(compare:)].firstObject;
  if (firstVisibleIndexPath) {
    ASCellNode *node = [self nodeForRowAtIndexPath:firstVisibleIndexPath];
    if (node) {
      _contentOffsetAdjustmentTopVisibleNode = node;
      _contentOffsetAdjustmentTopVisibleNodeOffset = [self rectForRowAtIndexPath:firstVisibleIndexPath].origin.y - self.bounds.origin.y;
    }
  }
}

- (void)endAdjustingContentOffsetAnimated:(BOOL)animated
{
  // We can't do this for animated updates.
  if (animated) {
    return;
  }
  
  // We can't do this if we didn't have a top visible row before.
  if (_contentOffsetAdjustmentTopVisibleNode == nil) {
    return;
  }
  
  NSIndexPath *newIndexPathForTopVisibleRow = [self indexPathForNode:_contentOffsetAdjustmentTopVisibleNode];
  // We can't do this if our top visible row was deleted
  if (newIndexPathForTopVisibleRow == nil) {
    return;
  }
  
  CGFloat newRowOriginYInSelf = [self rectForRowAtIndexPath:newIndexPathForTopVisibleRow].origin.y - self.bounds.origin.y;
  CGPoint newContentOffset = self.contentOffset;
  newContentOffset.y += (newRowOriginYInSelf - _contentOffsetAdjustmentTopVisibleNodeOffset);
  self.contentOffset = newContentOffset;
  _contentOffsetAdjustmentTopVisibleNode = nil;
}

#pragma mark - Intercepted selectors

- (void)setTableHeaderView:(ASDisplayView *)tableHeaderView
{
#if !AS_PLATFORM_MACOS
  // Typically the view will be nil before setting it, but reset state if it is being re-hosted.
  [self.tableHeaderView.asyncdisplaykit_node exitHierarchyState:ASHierarchyStateRangeManaged];
  [super setTableHeaderView:tableHeaderView];
  [self.tableHeaderView.asyncdisplaykit_node enterHierarchyState:ASHierarchyStateRangeManaged];
#else
  (void)tableHeaderView;
#endif
}

- (void)setTableFooterView:(ASDisplayView *)tableFooterView
{
#if !AS_PLATFORM_MACOS
  // Typically the view will be nil before setting it, but reset state if it is being re-hosted.
  [self.tableFooterView.asyncdisplaykit_node exitHierarchyState:ASHierarchyStateRangeManaged];
  [super setTableFooterView:tableFooterView];
  [self.tableFooterView.asyncdisplaykit_node enterHierarchyState:ASHierarchyStateRangeManaged];
#else
  (void)tableFooterView;
#endif
}

#if !AS_PLATFORM_MACOS
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
  _ASTableViewCell *cell = [self dequeueReusableCellWithIdentifier:kCellReuseIdentifier forIndexPath:indexPath];
  cell.delegate = self;

  ASCollectionElement *element = [_dataController.visibleMap elementForItemAtIndexPath:indexPath];
  cell.element = element;
  ASCellNode *node = element.node;
  if (node) {
    [_rangeController configureContentView:cell.contentView forCellNode:node];
  }

  return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
  CGFloat height = 0.0;

  ASCollectionElement *element = [_dataController.visibleMap elementForItemAtIndexPath:indexPath];
  if (element != nil) {
    ASCellNode *node = element.node;
    ASDisplayNodeAssertNotNil(node, @"Node must not be nil!");
    height = [node layoutThatFits:element.constrainedSize].size.height;
  }
  
#if TARGET_OS_IOS
  /**
   * Weirdly enough, Apple expects the return value here to _include_ the height
   * of the separator, if there is one! So if our node wants to be 43.5, we need
   * to return 44. UITableView will make a cell of height 44 with a content view
   * of height 43.5.
   */
  if (tableView.separatorStyle != UITableViewCellSeparatorStyleNone) {
    height += 1.0 / ASScreenScale();
  }
#endif
  
  return height;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
  return _dataController.visibleMap.numberOfSections;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
  return [_dataController.visibleMap numberOfItemsInSection:section];
}

- (nullable NSString *)modelIdentifierForElementAtIndexPath:(NSIndexPath *)indexPath inView:(ASDisplayView *)view {
    if (_asyncDataSourceFlags.modelIdentifierMethods) {
        GET_TABLENODE_OR_RETURN(tableNode, nil);
        NSIndexPath *convertedPath = [self convertIndexPathToTableNode:indexPath];
        if (convertedPath == nil) {
            return nil;
        } else {
            return [_asyncDataSource modelIdentifierForElementAtIndexPath:convertedPath inNode:tableNode];
        }
    } else {
        return nil;
    }
}

- (nullable NSIndexPath *)indexPathForElementWithModelIdentifier:(NSString *)identifier inView:(ASDisplayView *)view {
    if (_asyncDataSourceFlags.modelIdentifierMethods) {
        GET_TABLENODE_OR_RETURN(tableNode, nil);
        return  [_asyncDataSource indexPathForElementWithModelIdentifier:identifier inNode:tableNode];
      } else {
        return nil;
    }
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath
{
  if (_asyncDataSourceFlags.tableViewCanMoveRow) {
    return [_asyncDataSource tableView:self canMoveRowAtIndexPath:indexPath];
  } else {
    return NO;
  }
}

- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath toIndexPath:(NSIndexPath *)destinationIndexPath
{
  if (_asyncDataSourceFlags.tableViewMoveRow) {
    [_asyncDataSource tableView:self moveRowAtIndexPath:sourceIndexPath toIndexPath:destinationIndexPath];
  }

  // Move node after informing data source in case they call nodeAtIndexPath:
  // Get up to date
  [self waitUntilAllUpdatesAreCommitted];
  // Set our flag to suppress informing super about the change.
  _updatingInResponseToInteractiveMove = YES;
  // Submit the move
  [self moveRowAtIndexPath:sourceIndexPath toIndexPath:destinationIndexPath];
  // Wait for it to finish – should be fast!
  [self waitUntilAllUpdatesAreCommitted];
  // Clear the flag
  _updatingInResponseToInteractiveMove = NO;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(_ASTableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
  ASCollectionElement *element = cell.element;
  if (element) {
    ASDisplayNodeAssertTrue([_dataController.visibleMap elementForItemAtIndexPath:indexPath] == element);
    [_visibleElements addObject:element];
  } else {
    ASDisplayNodeAssert(NO, @"Unexpected nil element for willDisplayCell: %@, %@, %@", cell, self, indexPath);
    return;
  }

  ASCellNode *cellNode = element.node;
  cellNode.scrollView = tableView;

  ASDisplayNodeAssertNotNil(cellNode, @"Expected node associated with cell that will be displayed not to be nil. indexPath: %@", indexPath);

  if (_asyncDelegateFlags.tableNodeWillDisplayNodeForRow) {
    GET_TABLENODE_OR_RETURN(tableNode, (void)0);
    [_asyncDelegate tableNode:tableNode willDisplayRowWithNode:cellNode];
  } else if (_asyncDelegateFlags.tableViewWillDisplayNodeForRow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [_asyncDelegate tableView:self willDisplayNode:cellNode forRowAtIndexPath:indexPath];
  } else if (_asyncDelegateFlags.tableViewWillDisplayNodeForRowDeprecated) {
    [_asyncDelegate tableView:self willDisplayNodeForRowAtIndexPath:indexPath];
  }
#pragma clang diagnostic pop
  
  [_rangeController setNeedsUpdate];
  
  if ([cell consumesCellNodeVisibilityEvents]) {
    [_cellsForVisibilityUpdates addObject:cell];
  }
}

- (void)tableView:(UITableView *)tableView didEndDisplayingCell:(_ASTableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
  // Retrieve the element from cell instead of visible map because at this point visible map could have been updated and no longer holds the element.
  ASCollectionElement *element = cell.element;
  if (element) {
    [_visibleElements removeObject:element];
  } else {
    ASDisplayNodeAssert(NO, @"Unexpected nil element for didEndDisplayingCell: %@, %@, %@", cell, self, indexPath);
    return;
  }

  ASCellNode *cellNode = element.node;

  [_rangeController setNeedsUpdate];

  ASDisplayNodeAssertNotNil(cellNode, @"Expected node associated with removed cell not to be nil.");
  if (_asyncDelegateFlags.tableNodeDidEndDisplayingNodeForRow) {
    if (ASTableNode *tableNode = self.tableNode) {
    	[_asyncDelegate tableNode:tableNode didEndDisplayingRowWithNode:cellNode];
    }
  } else if (_asyncDelegateFlags.tableViewDidEndDisplayingNodeForRow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [_asyncDelegate tableView:self didEndDisplayingNode:cellNode forRowAtIndexPath:indexPath];
#pragma clang diagnostic pop
  }

  [_cellsForVisibilityUpdates removeObject:cell];
  
  cellNode.scrollView = nil;
}

- (NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(nonnull NSIndexPath *)indexPath
{
  if (_asyncDelegateFlags.tableNodeWillSelectRow) {
    GET_TABLENODE_OR_RETURN(tableNode, indexPath);
    NSIndexPath *result = [self convertIndexPathToTableNode:indexPath];
    // If this item was is gone, just let the table view do its default behavior and select.
    if (result == nil) {
      return indexPath;
    } else {
      result = [_asyncDelegate tableNode:tableNode willSelectRowAtIndexPath:result];
      result = [self convertIndexPathFromTableNode:result waitingIfNeeded:YES];
      return result;
    }
  } else if (_asyncDelegateFlags.tableViewWillSelectRow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [_asyncDelegate tableView:self willSelectRowAtIndexPath:indexPath];
#pragma clang diagnostic pop
  } else {
    return indexPath;
  }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(nonnull NSIndexPath *)indexPath
{
  if (_asyncDelegateFlags.tableNodeDidSelectRow) {
    GET_TABLENODE_OR_RETURN(tableNode, (void)0);
    indexPath = [self convertIndexPathToTableNode:indexPath];
    if (indexPath != nil) {
      [_asyncDelegate tableNode:tableNode didSelectRowAtIndexPath:indexPath];
    }
  } else if (_asyncDelegateFlags.tableViewDidSelectRow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [_asyncDelegate tableView:self didSelectRowAtIndexPath:indexPath];
#pragma clang diagnostic pop
  }
}

- (NSIndexPath *)tableView:(UITableView *)tableView willDeselectRowAtIndexPath:(nonnull NSIndexPath *)indexPath
{
  if (_asyncDelegateFlags.tableNodeWillDeselectRow) {
    GET_TABLENODE_OR_RETURN(tableNode, indexPath);
    NSIndexPath *result = [self convertIndexPathToTableNode:indexPath];
    // If this item was is gone, just let the table view do its default behavior and deselect.
    if (result == nil) {
      return indexPath;
    } else {
      result = [_asyncDelegate tableNode:tableNode willDeselectRowAtIndexPath:result];
      result = [self convertIndexPathFromTableNode:result waitingIfNeeded:YES];
      return result;
    }
  } else if (_asyncDelegateFlags.tableViewWillDeselectRow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [_asyncDelegate tableView:self willDeselectRowAtIndexPath:indexPath];
#pragma clang diagnostic pop
  }
  return indexPath;
}

- (void)tableView:(UITableView *)tableView didDeselectRowAtIndexPath:(nonnull NSIndexPath *)indexPath
{
  if (_asyncDelegateFlags.tableNodeDidDeselectRow) {
    GET_TABLENODE_OR_RETURN(tableNode, (void)0);
    indexPath = [self convertIndexPathToTableNode:indexPath];
    if (indexPath != nil) {
      [_asyncDelegate tableNode:tableNode didDeselectRowAtIndexPath:indexPath];
    }
  } else if (_asyncDelegateFlags.tableViewDidDeselectRow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [_asyncDelegate tableView:self didDeselectRowAtIndexPath:indexPath];
#pragma clang diagnostic pop
  }
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(nonnull NSIndexPath *)indexPath
{
  if (_asyncDelegateFlags.tableNodeShouldHighlightRow) {
    GET_TABLENODE_OR_RETURN(tableNode, NO);
    indexPath = [self convertIndexPathToTableNode:indexPath];
    if (indexPath != nil) {
      return [_asyncDelegate tableNode:tableNode shouldHighlightRowAtIndexPath:indexPath];
    }
  } else if (_asyncDelegateFlags.tableViewShouldHighlightRow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [_asyncDelegate tableView:self shouldHighlightRowAtIndexPath:indexPath];
#pragma clang diagnostic pop
  }
  return YES;
}

- (void)tableView:(UITableView *)tableView didHighlightRowAtIndexPath:(nonnull NSIndexPath *)indexPath
{
  if (_asyncDelegateFlags.tableNodeDidHighlightRow) {
    GET_TABLENODE_OR_RETURN(tableNode, (void)0);
    indexPath = [self convertIndexPathToTableNode:indexPath];
    if (indexPath != nil) {
      return [_asyncDelegate tableNode:tableNode didHighlightRowAtIndexPath:indexPath];
    }
  } else if (_asyncDelegateFlags.tableViewDidHighlightRow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [_asyncDelegate tableView:self didHighlightRowAtIndexPath:indexPath];
#pragma clang diagnostic pop
  }
}

- (void)tableView:(UITableView *)tableView didUnhighlightRowAtIndexPath:(nonnull NSIndexPath *)indexPath
{
  if (_asyncDelegateFlags.tableNodeDidHighlightRow) {
    GET_TABLENODE_OR_RETURN(tableNode, (void)0);
    indexPath = [self convertIndexPathToTableNode:indexPath];
    if (indexPath != nil) {
      return [_asyncDelegate tableNode:tableNode didUnhighlightRowAtIndexPath:indexPath];
    }
  } else if (_asyncDelegateFlags.tableViewDidUnhighlightRow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [_asyncDelegate tableView:self didUnhighlightRowAtIndexPath:indexPath];
#pragma clang diagnostic pop
  }
}

- (BOOL)tableView:(UITableView *)tableView shouldShowMenuForRowAtIndexPath:(nonnull NSIndexPath *)indexPath
{
  if (_asyncDelegateFlags.tableNodeShouldShowMenuForRow) {
    GET_TABLENODE_OR_RETURN(tableNode, NO);
    indexPath = [self convertIndexPathToTableNode:indexPath];
    if (indexPath != nil) {
      return [_asyncDelegate tableNode:tableNode shouldShowMenuForRowAtIndexPath:indexPath];
    }
  } else if (_asyncDelegateFlags.tableViewShouldShowMenuForRow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [_asyncDelegate tableView:self shouldShowMenuForRowAtIndexPath:indexPath];
#pragma clang diagnostic pop
  }
  return NO;
}

- (BOOL)tableView:(UITableView *)tableView canPerformAction:(nonnull SEL)action forRowAtIndexPath:(nonnull NSIndexPath *)indexPath withSender:(nullable id)sender
{
  if (_asyncDelegateFlags.tableNodeCanPerformActionForRow) {
    GET_TABLENODE_OR_RETURN(tableNode, NO);
    indexPath = [self convertIndexPathToTableNode:indexPath];
    if (indexPath != nil) {
      return [_asyncDelegate tableNode:tableNode canPerformAction:action forRowAtIndexPath:indexPath withSender:sender];
    }
  } else if (_asyncDelegateFlags.tableViewCanPerformActionForRow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [_asyncDelegate tableView:self canPerformAction:action forRowAtIndexPath:indexPath withSender:sender];
#pragma clang diagnostic pop
  }
  return NO;
}

- (void)tableView:(UITableView *)tableView performAction:(nonnull SEL)action forRowAtIndexPath:(nonnull NSIndexPath *)indexPath withSender:(nullable id)sender
{
  if (_asyncDelegateFlags.tableNodePerformActionForRow) {
    GET_TABLENODE_OR_RETURN(tableNode, (void)0);
    indexPath = [self convertIndexPathToTableNode:indexPath];
    if (indexPath != nil) {
      [_asyncDelegate tableNode:tableNode performAction:action forRowAtIndexPath:indexPath withSender:sender];
    }
  } else if (_asyncDelegateFlags.tableViewPerformActionForRow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [_asyncDelegate tableView:self performAction:action forRowAtIndexPath:indexPath withSender:sender];
#pragma clang diagnostic pop
  }
}
#endif

#if AS_PLATFORM_MACOS
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
  (void)tableView;
  ASElementMap *map = self.dataController.visibleMap;
  NSInteger rowCount = 0;
  NSInteger sectionCount = map.numberOfSections;
  for (NSInteger section = 0; section < sectionCount; section++) {
    rowCount += [map numberOfItemsInSection:section];
  }
  return rowCount;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
  (void)tableColumn;
  NSIndexPath *indexPath = [self indexPathForFlatRow:row inMap:self.dataController.visibleMap];
  if (indexPath == nil) {
    return nil;
  }
  ASCollectionElement *element = [self.dataController.visibleMap elementForItemAtIndexPath:indexPath];
  ASDisplayNodeAssert(element != nil, @"Unable to resolve table element at indexPath %@ for row %ld", indexPath, (long)row);
  ASCellNode *node = element.node;
  ASDisplayNodeAssert(node != nil, @"Unable to resolve ASCellNode for indexPath %@ on macOS table runtime.", indexPath);
  [_visibleElements addObject:element];
  node.scrollView = tableView.enclosingScrollView;
  if (_asyncDelegateFlags.tableNodeWillDisplayNodeForRow) {
    if (ASTableNode *tableNode = self.tableNode) {
      [_asyncDelegate tableNode:tableNode willDisplayRowWithNode:node];
    }
  } else if (_asyncDelegateFlags.tableViewWillDisplayNodeForRow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [_asyncDelegate tableView:self willDisplayNode:node forRowAtIndexPath:indexPath];
#pragma clang diagnostic pop
  }
  [_rangeController setNeedsUpdate];
  return node.view;
}

- (void)tableView:(NSTableView *)tableView didRemoveRowView:(NSTableRowView *)rowView forRow:(NSInteger)row
{
  (void)tableView;
  (void)rowView;
  NSIndexPath *indexPath = [self indexPathForFlatRow:row inMap:self.dataController.visibleMap];
  if (indexPath == nil) {
    return;
  }
  ASCollectionElement *element = [self.dataController.visibleMap elementForItemAtIndexPath:indexPath];
  if (element != nil) {
    [_visibleElements removeObject:element];
    ASCellNode *node = element.node;
    if (_asyncDelegateFlags.tableNodeDidEndDisplayingNodeForRow) {
      if (ASTableNode *tableNode = self.tableNode) {
        [_asyncDelegate tableNode:tableNode didEndDisplayingRowWithNode:node];
      }
    } else if (_asyncDelegateFlags.tableViewDidEndDisplayingNodeForRow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
      [_asyncDelegate tableView:self didEndDisplayingNode:node forRowAtIndexPath:indexPath];
#pragma clang diagnostic pop
    }
    node.scrollView = nil;
  }
  [_rangeController setNeedsUpdate];
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
  (void)tableView;
  NSIndexPath *indexPath = [self indexPathForFlatRow:row inMap:self.dataController.visibleMap];
  if (indexPath == nil) {
    return NO;
  }
  NSIndexPath *candidate = indexPath;
  if (_asyncDelegateFlags.tableNodeWillSelectRow) {
    if (ASTableNode *tableNode = self.tableNode) {
      candidate = [_asyncDelegate tableNode:tableNode willSelectRowAtIndexPath:indexPath];
    }
  } else if (_asyncDelegateFlags.tableViewWillSelectRow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    candidate = [_asyncDelegate tableView:self willSelectRowAtIndexPath:indexPath];
#pragma clang diagnostic pop
  }
  return (candidate != nil);
}

- (BOOL)tableView:(NSTableView *)tableView shouldDeselectRow:(NSInteger)row
{
  (void)tableView;
  NSIndexPath *indexPath = [self indexPathForFlatRow:row inMap:self.dataController.visibleMap];
  if (indexPath == nil) {
    return NO;
  }
  NSIndexPath *candidate = indexPath;
  if (_asyncDelegateFlags.tableNodeWillDeselectRow) {
    if (ASTableNode *tableNode = self.tableNode) {
      candidate = [_asyncDelegate tableNode:tableNode willDeselectRowAtIndexPath:indexPath];
    }
  } else if (_asyncDelegateFlags.tableViewWillDeselectRow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    candidate = [_asyncDelegate tableView:self willDeselectRowAtIndexPath:indexPath];
#pragma clang diagnostic pop
  }
  return (candidate != nil);
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
  (void)notification;
  NSIndexSet *currentSelection = [self.selectedRowIndexes copy];
  NSIndexSet *previousSelection = _as_previousSelectedRows ?: [NSIndexSet indexSet];

  NSMutableIndexSet *deselectedRows = [previousSelection mutableCopy];
  [deselectedRows removeIndexes:currentSelection];
  [deselectedRows enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
    (void)stop;
    NSIndexPath *indexPath = [self indexPathForFlatRow:(NSInteger)idx inMap:self.dataController.visibleMap];
    if (indexPath == nil) {
      return;
    }
    if (self->_asyncDelegateFlags.tableNodeDidDeselectRow) {
      if (ASTableNode *tableNode = self.tableNode) {
        [self->_asyncDelegate tableNode:tableNode didDeselectRowAtIndexPath:indexPath];
      }
    } else if (self->_asyncDelegateFlags.tableViewDidDeselectRow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
      [self->_asyncDelegate tableView:self didDeselectRowAtIndexPath:indexPath];
#pragma clang diagnostic pop
    }
  }];

  NSMutableIndexSet *selectedRows = [currentSelection mutableCopy];
  [selectedRows removeIndexes:previousSelection];
  [selectedRows enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
    (void)stop;
    NSIndexPath *indexPath = [self indexPathForFlatRow:(NSInteger)idx inMap:self.dataController.visibleMap];
    if (indexPath == nil) {
      return;
    }
    if (self->_asyncDelegateFlags.tableNodeDidSelectRow) {
      if (ASTableNode *tableNode = self.tableNode) {
        [self->_asyncDelegate tableNode:tableNode didSelectRowAtIndexPath:indexPath];
      }
    } else if (self->_asyncDelegateFlags.tableViewDidSelectRow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
      [self->_asyncDelegate tableView:self didSelectRowAtIndexPath:indexPath];
#pragma clang diagnostic pop
    }
  }];

  _as_previousSelectedRows = currentSelection;
}
#endif

#if !AS_PLATFORM_MACOS
- (void)scrollViewDidScroll:(ASScrollView *)scrollView
{
  if (scrollView != self && UITABLEVIEW_RESPONDS_TO_SELECTOR()) {
    [super scrollViewDidScroll:scrollView];
    return;
  }
  ASInterfaceState interfaceState = [self interfaceStateForRangeController:_rangeController];
  if (ASInterfaceStateIncludesVisible(interfaceState)) {
    [self _checkForBatchFetching];
  }  
#if !AS_PLATFORM_MACOS
  for (_ASTableViewCell *tableCell in _cellsForVisibilityUpdates) {
    [[tableCell node] cellNodeVisibilityEvent:ASCellNodeVisibilityEventVisibleRectChanged
                                 inScrollView:scrollView
                                withCellFrame:tableCell.frame];
  }
#endif
  if (_asyncDelegateFlags.scrollViewDidScroll) {
    [_asyncDelegate scrollViewDidScroll:scrollView];
  }
}

- (void)scrollViewWillEndDragging:(ASScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset
{
  if (scrollView != self && UITABLEVIEW_RESPONDS_TO_SELECTOR()) {
    [super scrollViewWillEndDragging:scrollView withVelocity:velocity targetContentOffset:targetContentOffset];
    return;
  }
  CGPoint contentOffset = scrollView.contentOffset;
  _deceleratingVelocity = CGPointMake(
    contentOffset.x - ((targetContentOffset != NULL) ? targetContentOffset->x : 0),
    contentOffset.y - ((targetContentOffset != NULL) ? targetContentOffset->y : 0)
  );

  if (targetContentOffset != NULL) {
    ASDisplayNodeAssert(_batchContext != nil, @"Batch context should exist");
    [self _beginBatchFetchingIfNeededWithContentOffset:*targetContentOffset velocity:velocity];
  }
  
  if (_asyncDelegateFlags.scrollViewWillEndDragging) {
    [_asyncDelegate scrollViewWillEndDragging:scrollView withVelocity:velocity targetContentOffset:(targetContentOffset ? : &contentOffset)];
  }
}

- (void)scrollViewDidEndDecelerating:(ASScrollView *)scrollView
{
  if (scrollView != self && UITABLEVIEW_RESPONDS_TO_SELECTOR()) {
    [super scrollViewDidEndDecelerating:scrollView];
    return;
  }
  _deceleratingVelocity = CGPointZero;

#if !AS_PLATFORM_MACOS
  for (_ASTableViewCell *tableViewCell in _cellsForVisibilityUpdates) {
    [[tableViewCell node] cellNodeVisibilityEvent:ASCellNodeVisibilityEventDidStopScrolling
                                          inScrollView:scrollView
                                         withCellFrame:tableViewCell.frame];
  }
#endif
  if (_asyncDelegateFlags.scrollViewDidEndDecelerating) {
      [_asyncDelegate scrollViewDidEndDecelerating:scrollView];
  }
}

- (void)scrollViewWillBeginDragging:(ASScrollView *)scrollView
{
  if (scrollView != self && UITABLEVIEW_RESPONDS_TO_SELECTOR()) {
    [super scrollViewWillBeginDragging:scrollView];
    return;
  }
  // If a scroll happens the current range mode needs to go to full
  _rangeController.contentHasBeenScrolled = YES;
  [_rangeController updateCurrentRangeWithMode:ASLayoutRangeModeFull];

#if !AS_PLATFORM_MACOS
  for (_ASTableViewCell *tableViewCell in _cellsForVisibilityUpdates) {
    [[tableViewCell node] cellNodeVisibilityEvent:ASCellNodeVisibilityEventWillBeginDragging
                                          inScrollView:scrollView
                                         withCellFrame:tableViewCell.frame];
  }
#endif
  if (_asyncDelegateFlags.scrollViewWillBeginDragging) {
    [_asyncDelegate scrollViewWillBeginDragging:scrollView];
  }
}

- (void)scrollViewDidEndDragging:(ASScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
  if (scrollView != self && UITABLEVIEW_RESPONDS_TO_SELECTOR()) {
    [super scrollViewDidEndDragging:scrollView willDecelerate:decelerate];
    return;
  }
#if !AS_PLATFORM_MACOS
  for (_ASTableViewCell *tableViewCell in _cellsForVisibilityUpdates) {
    [[tableViewCell node] cellNodeVisibilityEvent:ASCellNodeVisibilityEventDidEndDragging
                                          inScrollView:scrollView
                                         withCellFrame:tableViewCell.frame];
  }
#endif
  if (_asyncDelegateFlags.scrollViewDidEndDragging) {
    [_asyncDelegate scrollViewDidEndDragging:scrollView willDecelerate:decelerate];
  }
}
#endif

#pragma mark - Misc

- (BOOL)inverted
{
  return _inverted;
}

- (void)setInverted:(BOOL)inverted
{
  _inverted = inverted;
}

- (CGFloat)leadingScreensForBatching
{
  return _leadingScreensForBatching;
}

- (void)setLeadingScreensForBatching:(CGFloat)leadingScreensForBatching
{
  if (_leadingScreensForBatching != leadingScreensForBatching) {
    _leadingScreensForBatching = leadingScreensForBatching;
    ASPerformBlockOnMainThread(^{
      [self _checkForBatchFetching];
    });
  }
}

- (BOOL)automaticallyAdjustsContentOffset
{
  return _automaticallyAdjustsContentOffset;
}

- (void)setAutomaticallyAdjustsContentOffset:(BOOL)automaticallyAdjustsContentOffset
{
  _automaticallyAdjustsContentOffset = automaticallyAdjustsContentOffset;
}

#pragma mark - Scroll Direction

- (ASScrollDirection)scrollDirection
{
#if AS_PLATFORM_MACOS
  return _as_lastScrollDirection;
#else
  CGPoint scrollVelocity;
  if (self.isTracking) {
    scrollVelocity = [self.panGestureRecognizer velocityInView:self.superview];
  } else {
    scrollVelocity = _deceleratingVelocity;
  }
  
  ASScrollDirection scrollDirection = [self _scrollDirectionForVelocity:scrollVelocity];
  return ASScrollDirectionApplyTransform(scrollDirection, self.transform);
#endif
}

- (ASScrollDirection)_scrollDirectionForVelocity:(CGPoint)scrollVelocity
{
  ASScrollDirection direction = ASScrollDirectionNone;
  ASScrollDirection scrollableDirections = [self scrollableDirections];
  
  if (ASScrollDirectionContainsVerticalDirection(scrollableDirections)) { // Can scroll vertically.
    if (scrollVelocity.y < 0.0) {
      direction |= ASScrollDirectionDown;
    } else if (scrollVelocity.y > 0.0) {
      direction |= ASScrollDirectionUp;
    }
  }
  
  return direction;
}

- (ASScrollDirection)scrollableDirections
{
#if AS_PLATFORM_MACOS
  return ASScrollDirectionVerticalDirections;
#else
  ASScrollDirection scrollableDirection = ASScrollDirectionNone;
  CGFloat totalContentWidth = self.contentSize.width + self.contentInset.left + self.contentInset.right;
  CGFloat totalContentHeight = self.contentSize.height + self.contentInset.top + self.contentInset.bottom;
  
  if (self.alwaysBounceHorizontal || totalContentWidth > self.bounds.size.width) { // Can scroll horizontally.
    scrollableDirection |= ASScrollDirectionHorizontalDirections;
  }
  if (self.alwaysBounceVertical || totalContentHeight > self.bounds.size.height) { // Can scroll vertically.
    scrollableDirection |= ASScrollDirectionVerticalDirections;
  }
  return scrollableDirection;
#endif
}


#pragma mark - Batch Fetching

- (ASBatchContext *)batchContext
{
  return _batchContext;
}

- (BOOL)canBatchFetch
{
  // if the delegate does not respond to this method, there is no point in starting to fetch
  BOOL canFetch = _asyncDelegateFlags.tableNodeWillBeginBatchFetch || _asyncDelegateFlags.tableViewWillBeginBatchFetch;
  if (canFetch && _asyncDelegateFlags.shouldBatchFetchForTableNode) {
    GET_TABLENODE_OR_RETURN(tableNode, NO);
    return [_asyncDelegate shouldBatchFetchForTableNode:tableNode];
  } else if (canFetch && _asyncDelegateFlags.shouldBatchFetchForTableView) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [_asyncDelegate shouldBatchFetchForTableView:self];
#pragma clang diagnostic pop
  } else {
    return canFetch;
  }
}

- (id<ASBatchFetchingDelegate>)batchFetchingDelegate
{
#if AS_PLATFORM_MACOS
  return nil;
#else
  return self.tableNode.batchFetchingDelegate;
#endif
}

- (void)_scheduleCheckForBatchFetchingForNumberOfChanges:(NSUInteger)changes
{
  // Prevent fetching will continually trigger in a loop after reaching end of content and no new content was provided
  if (changes == 0 && _hasEverCheckedForBatchFetchingDueToUpdate) {
    return;
  }
  _hasEverCheckedForBatchFetchingDueToUpdate = YES;

  // Push this to the next runloop to be sure the scroll view has the right content size
  dispatch_async(dispatch_get_main_queue(), ^{
    [self _checkForBatchFetching];
  });
}

- (void)_checkForBatchFetching
{
#if !AS_PLATFORM_MACOS
  // Dragging will be handled in scrollViewWillEndDragging:withVelocity:targetContentOffset:
  if (self.isDragging || self.isTracking) {
    return;
  }
#endif
  
  [self _beginBatchFetchingIfNeededWithContentOffset:self.contentOffset velocity:CGPointZero];
}

- (void)_beginBatchFetchingIfNeededWithContentOffset:(CGPoint)contentOffset velocity:(CGPoint)velocity
{
#if AS_PLATFORM_MACOS
  CGSize contentSize = self.bounds.size;
  if (ASDisplayShouldFetchBatchForContext(_batchContext,
                                          self.scrollDirection,
                                          ASScrollDirectionVerticalDirections,
                                          self.bounds,
                                          contentSize,
                                          contentOffset,
                                          self.leadingScreensForBatching,
                                          ASInterfaceStateIncludesVisible([self interfaceStateForRangeController:_rangeController]),
                                          NO,
                                          velocity,
                                          NO,
                                          self.batchFetchingDelegate)) {
    [self _beginBatchFetching];
  }
#else
  if (ASDisplayShouldFetchBatchForScrollView(self, self.scrollDirection, ASScrollDirectionVerticalDirections, contentOffset, velocity, NO)) {
    [self _beginBatchFetching];
  }
#endif
}

- (void)_beginBatchFetching
{
  [_batchContext beginBatchFetching];
  if (_asyncDelegateFlags.tableNodeWillBeginBatchFetch) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
      GET_TABLENODE_OR_RETURN(tableNode, (void)0);
      [self->_asyncDelegate tableNode:tableNode willBeginBatchFetchWithContext:self->_batchContext];
    });
  } else if (_asyncDelegateFlags.tableViewWillBeginBatchFetch) {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
      [self->_asyncDelegate tableView:self willBeginBatchFetchWithContext:self->_batchContext];
#pragma clang diagnostic pop
    });
  }
}

#pragma mark - ASRangeControllerDataSource

- (ASRangeController *)rangeController
{
  return _rangeController;
}

- (NSHashTable<ASCollectionElement *> *)visibleElementsForRangeController:(ASRangeController *)rangeController
{
  return ASPointerTableByFlatMapping(_visibleElements, id element, element);
}

- (ASScrollDirection)scrollDirectionForRangeController:(ASRangeController *)rangeController
{
  return self.scrollDirection;
}

- (ASInterfaceState)interfaceStateForRangeController:(ASRangeController *)rangeController
{
#if AS_PLATFORM_MACOS
  if (self.window == nil || self.isHidden) {
    return ASInterfaceStateNone;
  }
  return ASInterfaceStateInHierarchy;
#else
  return ASInterfaceStateForDisplayNode(self.tableNode, self.window);
#endif
}

- (NSString *)nameForRangeControllerDataSource
{
  return self.asyncDataSource ? NSStringFromClass([self.asyncDataSource class]) : NSStringFromClass([self class]);
}

#pragma mark - ASRangeControllerDelegate

- (BOOL)rangeControllerShouldUpdateRanges:(ASRangeController *)rangeController
{
  return YES;
}

- (void)rangeController:(ASRangeController *)rangeController updateWithChangeSet:(_ASHierarchyChangeSet *)changeSet updates:(dispatch_block_t)updates
{
  ASDisplayNodeAssertMainThread();
  if (!self.asyncDataSource || _updatingInResponseToInteractiveMove) {
    updates();
    [changeSet executeCompletionHandlerWithFinished:NO];
    return; // if the asyncDataSource has become invalid while we are processing, ignore this request to avoid crashes
  }

  if (changeSet.includesReloadData) {
    LOG(@"UITableView reloadData");
    ASPerformBlockWithoutAnimation(!changeSet.animated, ^{
      if (self.test_enableSuperUpdateCallLogging) {
        NSLog(@"-[super reloadData]");
      }
      updates();
      [super reloadData];
      // Flush any range changes that happened as part of submitting the reload.
      [self->_rangeController updateIfNeeded];
      [self _scheduleCheckForBatchFetchingForNumberOfChanges:1];
      [changeSet executeCompletionHandlerWithFinished:YES];
    });
    return;
  }

#if AS_PLATFORM_MACOS
  BOOL shouldAdjustContentOffset = (_automaticallyAdjustsContentOffset && !changeSet.includesReloadData);
  if (shouldAdjustContentOffset) {
    [self beginAdjustingContentOffset];
  }

  ASElementMap *oldMap = self.dataController.visibleMap;
  updates();
  ASElementMap *newMap = self.dataController.visibleMap;
  if (oldMap == nil || newMap == nil) {
    ASDisplayNodeFailAssert(@"Missing element map while applying macOS table change set. Falling back to reloadData.");
    [super reloadData];
    [self->_rangeController updateIfNeeded];
    [self _scheduleCheckForBatchFetchingForNumberOfChanges:1];
    if (shouldAdjustContentOffset) {
      [self endAdjustingContentOffsetAnimated:changeSet.animated];
    }
    [changeSet executeCompletionHandlerWithFinished:YES];
    return;
  }

  NSUInteger numberOfUpdates = 0;
  [super beginUpdates];

  NSMutableIndexSet *reloadRows = [NSMutableIndexSet indexSet];
  for (_ASHierarchyItemChange *change in [changeSet itemChangesOfType:_ASHierarchyChangeTypeReload]) {
    [reloadRows addIndexes:[self _rowIndexesForIndexPaths:change.indexPaths inMap:oldMap]];
  }
  for (_ASHierarchySectionChange *change in [changeSet sectionChangesOfType:_ASHierarchyChangeTypeReload]) {
    [reloadRows addIndexes:[self _rowIndexesForSections:change.indexSet inMap:oldMap]];
  }
  if (reloadRows.count > 0) {
    [super reloadDataForRowIndexes:reloadRows columnIndexes:[self _tableColumnIndexes]];
    numberOfUpdates++;
  }

  NSMutableIndexSet *deleteRows = [NSMutableIndexSet indexSet];
  for (_ASHierarchyItemChange *change in [changeSet itemChangesOfType:_ASHierarchyChangeTypeOriginalDelete]) {
    [deleteRows addIndexes:[self _rowIndexesForIndexPaths:change.indexPaths inMap:oldMap]];
  }
  for (_ASHierarchySectionChange *change in [changeSet sectionChangesOfType:_ASHierarchyChangeTypeOriginalDelete]) {
    [deleteRows addIndexes:[self _rowIndexesForSections:change.indexSet inMap:oldMap]];
  }
  if (deleteRows.count > 0) {
    [super removeRowsAtIndexes:deleteRows withAnimation:NSTableViewAnimationEffectNone];
    numberOfUpdates++;
  }

  NSMutableIndexSet *insertRows = [NSMutableIndexSet indexSet];
  for (_ASHierarchySectionChange *change in [changeSet sectionChangesOfType:_ASHierarchyChangeTypeOriginalInsert]) {
    [insertRows addIndexes:[self _rowIndexesForSections:change.indexSet inMap:newMap]];
  }
  for (_ASHierarchyItemChange *change in [changeSet itemChangesOfType:_ASHierarchyChangeTypeOriginalInsert]) {
    [insertRows addIndexes:[self _rowIndexesForIndexPaths:change.indexPaths inMap:newMap]];
  }
  if (insertRows.count > 0) {
    [super insertRowsAtIndexes:insertRows withAnimation:NSTableViewAnimationEffectNone];
    numberOfUpdates++;
  }

  [super endUpdates];

  if (ASActivateExperimentalFeature(ASExperimentalRangeUpdateOnChangesetUpdate)) {
    [self->_rangeController setNeedsUpdate];
  }
  [self->_rangeController updateIfNeeded];
  [self _scheduleCheckForBatchFetchingForNumberOfChanges:numberOfUpdates];
  if (shouldAdjustContentOffset) {
    [self endAdjustingContentOffsetAnimated:changeSet.animated];
  }
  [changeSet executeCompletionHandlerWithFinished:YES];
  return;
#else
  BOOL shouldAdjustContentOffset = (_automaticallyAdjustsContentOffset && !changeSet.includesReloadData);
  if (shouldAdjustContentOffset) {
    [self beginAdjustingContentOffset];
  }
  
  NSUInteger numberOfUpdates = 0;
  
  LOG(@"--- UITableView beginUpdates");
  [super beginUpdates];

  updates();
  
  for (_ASHierarchyItemChange *change in [changeSet itemChangesOfType:_ASHierarchyChangeTypeReload]) {
    NSArray<NSIndexPath *> *indexPaths = change.indexPaths;
    ASTableViewRowAnimation animationOptions = (ASTableViewRowAnimation)change.animationOptions;
    
    LOG(@"UITableView reloadRows:%ld rows", indexPaths.count);
    BOOL preventAnimation = animationOptions == ASTableViewRowAnimationNone;
    ASPerformBlockWithoutAnimation(preventAnimation, ^{
      if (self.test_enableSuperUpdateCallLogging) {
        NSLog(@"-[super reloadRowsAtIndexPaths]: %@", indexPaths);
      }
      [super reloadRowsAtIndexPaths:indexPaths withRowAnimation:animationOptions];
    });
    
    numberOfUpdates++;
  }
  
  for (_ASHierarchySectionChange *change in [changeSet sectionChangesOfType:_ASHierarchyChangeTypeReload]) {
    NSIndexSet *sectionIndexes = change.indexSet;
    ASTableViewRowAnimation animationOptions = (ASTableViewRowAnimation)change.animationOptions;
    
    LOG(@"UITableView reloadSections:%@", sectionIndexes);
    BOOL preventAnimation = (animationOptions == ASTableViewRowAnimationNone);
    ASPerformBlockWithoutAnimation(preventAnimation, ^{
      if (self.test_enableSuperUpdateCallLogging) {
        NSLog(@"-[super reloadSections]: %@", sectionIndexes);
      }
      [super reloadSections:sectionIndexes withRowAnimation:animationOptions];
    });
    
    numberOfUpdates++;
  }
  
  for (_ASHierarchyItemChange *change in [changeSet itemChangesOfType:_ASHierarchyChangeTypeOriginalDelete]) {
    NSArray<NSIndexPath *> *indexPaths = change.indexPaths;
    ASTableViewRowAnimation animationOptions = (ASTableViewRowAnimation)change.animationOptions;
    
    LOG(@"UITableView deleteRows:%ld rows", indexPaths.count);
    BOOL preventAnimation = animationOptions == ASTableViewRowAnimationNone;
    ASPerformBlockWithoutAnimation(preventAnimation, ^{
      if (self.test_enableSuperUpdateCallLogging) {
        NSLog(@"-[super deleteRowsAtIndexPaths]: %@", indexPaths);
      }
      [super deleteRowsAtIndexPaths:indexPaths withRowAnimation:animationOptions];
    });
    
    numberOfUpdates++;
  }
  
  for (_ASHierarchySectionChange *change in [changeSet sectionChangesOfType:_ASHierarchyChangeTypeOriginalDelete]) {
    NSIndexSet *sectionIndexes = change.indexSet;
    ASTableViewRowAnimation animationOptions = (ASTableViewRowAnimation)change.animationOptions;
    
    LOG(@"UITableView deleteSections:%@", sectionIndexes);
    BOOL preventAnimation = (animationOptions == ASTableViewRowAnimationNone);
    ASPerformBlockWithoutAnimation(preventAnimation, ^{
      if (self.test_enableSuperUpdateCallLogging) {
        NSLog(@"-[super deleteSections]: %@", sectionIndexes);
      }
      [super deleteSections:sectionIndexes withRowAnimation:animationOptions];
    });
    
    numberOfUpdates++;
  }
  
  for (_ASHierarchySectionChange *change in [changeSet sectionChangesOfType:_ASHierarchyChangeTypeOriginalInsert]) {
    NSIndexSet *sectionIndexes = change.indexSet;
    ASTableViewRowAnimation animationOptions = (ASTableViewRowAnimation)change.animationOptions;
    
    LOG(@"UITableView insertSections:%@", sectionIndexes);
    BOOL preventAnimation = (animationOptions == ASTableViewRowAnimationNone);
    ASPerformBlockWithoutAnimation(preventAnimation, ^{
      if (self.test_enableSuperUpdateCallLogging) {
        NSLog(@"-[super insertSections]: %@", sectionIndexes);
      }
      [super insertSections:sectionIndexes withRowAnimation:animationOptions];
    });
    
    numberOfUpdates++;
  }
  
  for (_ASHierarchyItemChange *change in [changeSet itemChangesOfType:_ASHierarchyChangeTypeOriginalInsert]) {
    NSArray<NSIndexPath *> *indexPaths = change.indexPaths;
    ASTableViewRowAnimation animationOptions = (ASTableViewRowAnimation)change.animationOptions;
    
    LOG(@"UITableView insertRows:%ld rows", indexPaths.count);
    BOOL preventAnimation = (animationOptions == ASTableViewRowAnimationNone);
    ASPerformBlockWithoutAnimation(preventAnimation, ^{
      if (self.test_enableSuperUpdateCallLogging) {
        NSLog(@"-[super insertRowsAtIndexPaths]: %@", indexPaths);
      }
      [super insertRowsAtIndexPaths:indexPaths withRowAnimation:animationOptions];
    });
    
    numberOfUpdates++;
  }

  LOG(@"--- UITableView endUpdates");
  ASPerformBlockWithoutAnimation(!changeSet.animated, ^{
    [super endUpdates];
    if (numberOfUpdates > 0 && ASActivateExperimentalFeature(ASExperimentalRangeUpdateOnChangesetUpdate)) {
      [self->_rangeController setNeedsUpdate];
    }
    [self->_rangeController updateIfNeeded];
    [self _scheduleCheckForBatchFetchingForNumberOfChanges:numberOfUpdates];
  });
  if (shouldAdjustContentOffset) {
    [self endAdjustingContentOffsetAnimated:changeSet.animated];
  }
  [changeSet executeCompletionHandlerWithFinished:YES];
#endif
}

#pragma mark - ASDataControllerSource

- (BOOL)dataController:(ASDataController *)dataController shouldEagerlyLayoutNode:(ASCellNode *)node
{
  return YES;
}

- (BOOL)dataControllerShouldSerializeNodeCreation:(ASDataController *)dataController
{
  return NO;
}

- (BOOL)dataController:(ASDataController *)dataController shouldSynchronouslyProcessChangeSet:(_ASHierarchyChangeSet *)changeSet
{
  // Reload data is expensive, don't block main while doing so.
  if (changeSet.includesReloadData) {
    return NO;
  }
  // For more details on this method, see the comment in the ASCollectionView implementation.
  if (changeSet.countForAsyncLayout < 2) {
    return YES;
  }
  CGSize contentSize = CGSizeZero;
#if AS_PLATFORM_MACOS
  contentSize = self.bounds.size;
#else
  contentSize = self.contentSize;
#endif
  CGSize boundsSize = self.bounds.size;
  if (contentSize.height <= boundsSize.height && contentSize.width <= boundsSize.width) {
    return YES;
  }
  return NO;
}

- (void)dataControllerDidFinishWaiting:(ASDataController *)dataController
{
  // ASCellLayoutMode is not currently supported on ASTableView (see ASCollectionView for details).
}

- (id)dataController:(ASDataController *)dataController nodeModelForItemAtIndexPath:(NSIndexPath *)indexPath
{
  // Not currently supported for tables. Will be added when the collection API stabilizes.
  return nil;
}

- (ASCellNodeBlock)dataController:(ASDataController *)dataController nodeBlockAtIndexPath:(NSIndexPath *)indexPath shouldAsyncLayout:(BOOL *)shouldAsyncLayout
{
  ASCellNodeBlock block = nil;

  if (_asyncDataSourceFlags.tableNodeNodeBlockForRow) {
    if (ASTableNode *tableNode = self.tableNode) {
      block = [_asyncDataSource tableNode:tableNode nodeBlockForRowAtIndexPath:indexPath];
    }
  } else if (_asyncDataSourceFlags.tableNodeNodeForRow) {
    ASCellNode *node = nil;
    if (ASTableNode *tableNode = self.tableNode) {
    	node = [_asyncDataSource tableNode:tableNode nodeForRowAtIndexPath:indexPath];
    }
    if ([node isKindOfClass:[ASCellNode class]]) {
      block = ^{
        return node;
      };
    } else {
      ASDisplayNodeFailAssert(@"Data source returned invalid node from tableNode:nodeForRowAtIndexPath:. Node: %@", node);
    }
  } else if (_asyncDataSourceFlags.tableViewNodeBlockForRow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    block = [_asyncDataSource tableView:self nodeBlockForRowAtIndexPath:indexPath];
  } else if (_asyncDataSourceFlags.tableViewNodeForRow) {
    ASCellNode *node = [_asyncDataSource tableView:self nodeForRowAtIndexPath:indexPath];
#pragma clang diagnostic pop
    if ([node isKindOfClass:[ASCellNode class]]) {
      block = ^{
        return node;
      };
    } else {
      ASDisplayNodeFailAssert(@"Data source returned invalid node from tableView:nodeForRowAtIndexPath:. Node: %@", node);
    }
  }

  // Handle nil node block
  if (block == nil) {
    ASDisplayNodeFailAssert(@"ASTableNode could not get a node block for row at index path %@", indexPath);
    return ^{
      ASDisplayNodeFailAssert(@"ASTableNode data source contract violation for index path %@. nodeBlock must not be nil.", indexPath);
      return (ASCellNode *)nil;
    };
  }

  // Wrap the node block
  __weak __typeof__(self) weakSelf = self;
  return ^{
    __typeof__(self) strongSelf = weakSelf;
    ASCellNode *node = block();
    ASDisplayNodeAssert(node != nil, @"ASTableNode data source returned nil node for index path %@", indexPath);
    ASDisplayNodeAssert([node isKindOfClass:[ASCellNode class]], @"ASTableNode provided a non-ASCellNode! %@, %@", node, strongSelf);

    [node enterHierarchyState:ASHierarchyStateRangeManaged];
    if (node.interactionDelegate == nil) {
      node.interactionDelegate = strongSelf;
    }
    if (self->_inverted) {
        node.transform = CATransform3DMakeScale(1, -1, 1) ;
    }
    return node;
  };
}

- (ASSizeRange)dataController:(ASDataController *)dataController constrainedSizeForNodeAtIndexPath:(NSIndexPath *)indexPath
{
  ASSizeRange constrainedSize = ASSizeRangeZero;
  if (_asyncDelegateFlags.tableNodeConstrainedSizeForRow) {
    GET_TABLENODE_OR_RETURN(tableNode, constrainedSize);
    ASSizeRange delegateConstrainedSize = [_asyncDelegate tableNode:tableNode constrainedSizeForRowAtIndexPath:indexPath];
    // ignore widths in the returned size range (for TableView)
    constrainedSize = ASSizeRangeMake(CGSizeMake(_nodesConstrainedWidth, delegateConstrainedSize.min.height),
                                      CGSizeMake(_nodesConstrainedWidth, delegateConstrainedSize.max.height));
  } else if (_asyncDelegateFlags.tableViewConstrainedSizeForRow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    ASSizeRange delegateConstrainedSize = [_asyncDelegate tableView:self constrainedSizeForRowAtIndexPath:indexPath];
#pragma clang diagnostic pop
    // ignore widths in the returned size range (for TableView)
    constrainedSize = ASSizeRangeMake(CGSizeMake(_nodesConstrainedWidth, delegateConstrainedSize.min.height),
                                      CGSizeMake(_nodesConstrainedWidth, delegateConstrainedSize.max.height));
  } else {
    constrainedSize = ASSizeRangeMake(CGSizeMake(_nodesConstrainedWidth, 0),
                                      CGSizeMake(_nodesConstrainedWidth, CGFLOAT_MAX));
  }
  return constrainedSize;
}

- (NSUInteger)dataController:(ASDataController *)dataController rowsInSection:(NSUInteger)section
{
  if (_asyncDataSourceFlags.tableNodeNumberOfRowsInSection) {
    GET_TABLENODE_OR_RETURN(tableNode, 0);
    return [_asyncDataSource tableNode:tableNode numberOfRowsInSection:section];
  } else if (_asyncDataSourceFlags.tableViewNumberOfRowsInSection) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [_asyncDataSource tableView:self numberOfRowsInSection:section];
#pragma clang diagnostic pop
  } else {
    return 0;
  }
}

- (NSUInteger)numberOfSectionsInDataController:(ASDataController *)dataController
{
  if (_asyncDataSourceFlags.numberOfSectionsInTableNode) {
    GET_TABLENODE_OR_RETURN(tableNode, 0);
    return [_asyncDataSource numberOfSectionsInTableNode:tableNode];
  } else if (_asyncDataSourceFlags.numberOfSectionsInTableView) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [_asyncDataSource numberOfSectionsInTableView:self];
#pragma clang diagnostic pop
  } else {
    return 1; // default section number
  }
}

- (BOOL)dataController:(ASDataController *)dataController presentedSizeForElement:(ASCollectionElement *)element matchesSize:(CGSize)size
{
  NSIndexPath *indexPath = [self indexPathForNode:element.node];
  if (indexPath == nil) {
    ASDisplayNodeFailAssert(@"Data controller should not ask for presented size for element that is not presented.");
    return YES;
  }
  CGRect rect = [self rectForRowAtIndexPath:indexPath];
  
#if TARGET_OS_IOS
  /**
   * Weirdly enough, Apple expects the return value in tableView:heightForRowAtIndexPath: to _include_ the height
   * of the separator, if there is one! So if rectForRow would return 44.0 we need to use 43.5.
   */
  if (self.separatorStyle != UITableViewCellSeparatorStyleNone) {
    rect.size.height -= 1.0 / ASScreenScale();
  }
#endif

  return (fabs(rect.size.height - size.height) < FLT_EPSILON);
}

#pragma mark - _ASTableViewCellDelegate

#if !AS_PLATFORM_MACOS
- (void)didLayoutSubviewsOfTableViewCell:(_ASTableViewCell *)tableViewCell
{
  ASCellNode *node = tableViewCell.node;
  if (node == nil || _asyncDataSource == nil) {
    return;
  }
  
  CGFloat contentViewWidth = tableViewCell.contentView.bounds.size.width;
  ASSizeRange constrainedSize = node.constrainedSizeForCalculatedLayout;
  
  // Table view cells should always fill its content view width.
  // Normally the content view width equals to the constrained size width (which equals to the table view width).
  // If there is a mismatch between these values, for example after the table view entered or left editing mode,
  // content view width is preferred and used to re-measure the cell node.
  if (CGSizeEqualToSize(node.calculatedSize, CGSizeZero) == NO && contentViewWidth != constrainedSize.max.width) {
    constrainedSize.min.width = contentViewWidth;
    constrainedSize.max.width = contentViewWidth;

    // Re-measurement is done on main to ensure thread affinity. In the worst case, this is as fast as UIKit's implementation.
    //
    // Unloaded nodes *could* be re-measured off the main thread, but only with the assumption that content view width
    // is the same for all cells (because there is no easy way to get that individual value before the node being assigned to a _ASTableViewCell).
    // Also, in many cases, some nodes may not need to be re-measured at all, such as when user enters and then immediately leaves editing mode.
    // To avoid premature optimization and making such assumption, as well as to keep ASTableView simple, re-measurement is strictly done on main.
    CGSize oldSize = node.bounds.size;
    const CGSize calculatedSize = [node layoutThatFits:constrainedSize].size;
    node.frame = { .size = calculatedSize };

    // After the re-measurement, set the new constrained size to the node's backing colleciton element.
    node.collectionElement.constrainedSize = constrainedSize;

    // If the node height changed, trigger a height requery.
    if (oldSize.height != calculatedSize.height) {
      [self beginUpdates];
      [self endUpdatesAnimated:(ASDisplayNodeLayerHasAnimations(self.layer) == NO) completion:nil];
    }
  }
}
#endif

#pragma mark - ASCellNodeDelegate

- (void)nodeSelectedStateDidChange:(ASCellNode *)node
{
  NSIndexPath *indexPath = [self indexPathForNode:node];
  if (indexPath) {
    if (node.isSelected) {
      [self selectRowAtIndexPath:indexPath animated:NO scrollPosition:ASTableViewScrollPositionNone];
    } else {
      [self deselectRowAtIndexPath:indexPath animated:NO];
    }
  }
}

- (void)nodeHighlightedStateDidChange:(ASCellNode *)node
{
#if !AS_PLATFORM_MACOS
  NSIndexPath *indexPath = [self indexPathForNode:node];
  if (indexPath) {
    [self cellForRowAtIndexPath:indexPath].highlighted = node.isHighlighted;
  }
#else
  (void)node;
#endif
}

- (void)nodeDidInvalidateSize:(ASCellNode *)node
{
  [_cellsForLayoutUpdates addObject:node];
#if AS_PLATFORM_MACOS
  [self setNeedsLayout:YES];
#else
  [self setNeedsLayout];
#endif
}

// Cause UITableView to requery for the new height of this node
- (void)requeryNodeHeights
{
  _queuedNodeHeightUpdate = NO;

  [super beginUpdates];
  [super endUpdates];
}

#pragma mark - Helper Methods

// Note: This is called every layout, and so it is very performance sensitive.
- (CGFloat)sectionIndexWidth
{
  // If they don't implement the methods, then there's no section index.
  if (_asyncDataSourceFlags.sectionIndexMethods == NO) {
    return 0;
  }

  ASDisplayView *indexView = _sectionIndexView;
  if (indexView.superview == self) {
    return indexView.frame.size.width;
  }

  CGRect bounds = self.bounds;
  for (ASDisplayView *view in self.subviews) {
    CGRect frame = view.frame;
    // Section index is right-aligned and less than half-width.
    if (CGRectGetMaxX(frame) == CGRectGetMaxX(bounds) && frame.size.width * 2 < bounds.size.width) {
      _sectionIndexView = view;
      return frame.size.width;
    }
  }
  return 0;
}

#pragma mark - _ASDisplayView behavior substitutions
// Need these to drive interfaceState so we know when we are visible, if not nested in another range-managing element.
// Because our superclass is a true UIKit class, we cannot also subclass _ASDisplayView.
#if !AS_PLATFORM_MACOS
- (void)willMoveToWindow:(UIWindow *)newWindow
{
  BOOL visible = (newWindow != nil);
  ASDisplayNode *node = self.tableNode;
  if (visible && !node.inHierarchy) {
    [node __enterHierarchy];
  }
}

- (void)didMoveToWindow
{
  BOOL visible = (self.window != nil);
  ASDisplayNode *node = self.tableNode;
  BOOL rangeControllerNeedsUpdate = ![node supportsRangeManagedInterfaceState];;

  if (!visible && node.inHierarchy) {
    if (rangeControllerNeedsUpdate) {
      rangeControllerNeedsUpdate = NO;
      // Exit CellNodes first before Table to match UIKit behaviors (tear down bottom up).
      // Although we have not yet cleared the interfaceState's Visible bit (this  happens in __exitHierarchy),
      // the ASRangeController will get the correct value from -interfaceStateForRangeController:.
      [_rangeController updateRanges];
    }
    [node __exitHierarchy];
  }

  // Updating the visible node index paths only for not range managed nodes. Range managed nodes will get their
  // their update in the layout pass
  if (rangeControllerNeedsUpdate) {
    [_rangeController updateRanges];
  }

  // When we aren't visible, we will only fetch up to the visible area. Now that we are visible,
  // we will fetch visible area + leading screens, so we need to check.
  if (visible) {
    [self _checkForBatchFetching];
  }
}

- (void)willMoveToSuperview:(ASDisplayView *)newSuperview
{
  if (self.superview == nil && newSuperview != nil) {
    _keepalive_node = self.tableNode;
  }
}

- (void)didMoveToSuperview
{
  if (self.superview == nil) {
    _keepalive_node = nil;
  }
}
#else
- (void)viewWillMoveToWindow:(NSWindow *)newWindow
{
  BOOL visible = (newWindow != nil);
  ASDisplayNode *node = self.tableNode;
  if (visible && !node.inHierarchy) {
    [node __enterHierarchy];
  }
  [self _as_startObservingEnclosingScrollViewIfNeeded];
}

- (void)viewDidMoveToWindow
{
  [super viewDidMoveToWindow];
  BOOL visible = (self.window != nil);
  ASDisplayNode *node = self.tableNode;
  BOOL rangeControllerNeedsUpdate = ![node supportsRangeManagedInterfaceState];

  if (!visible && node.inHierarchy) {
    if (rangeControllerNeedsUpdate) {
      rangeControllerNeedsUpdate = NO;
      [_rangeController updateRanges];
    }
    [node __exitHierarchy];
  }

  if (rangeControllerNeedsUpdate) {
    [_rangeController updateRanges];
  }
  if (visible) {
    [self _checkForBatchFetching];
  }
  [self _as_startObservingEnclosingScrollViewIfNeeded];
  [self _as_setNeedsRangeUpdate];
}

- (void)viewWillMoveToSuperview:(NSView *)newSuperview
{
  [super viewWillMoveToSuperview:newSuperview];
  if (self.superview == nil && newSuperview != nil) {
    _keepalive_node = self.tableNode;
  }
}

- (void)viewDidMoveToSuperview
{
  [super viewDidMoveToSuperview];
  if (self.superview == nil) {
    _keepalive_node = nil;
  }
  [self _as_startObservingEnclosingScrollViewIfNeeded];
  [self _as_setNeedsRangeUpdate];
}
#endif

#pragma mark - Accessibility overrides

- (NSArray *)accessibilityElements
{
  [self waitUntilAllUpdatesAreCommitted];
#if AS_PLATFORM_MACOS
  return nil;
#else
  return [super accessibilityElements];
#endif
}

@end
