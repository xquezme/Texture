//
//  ASCollectionViewProtocols.h
//  Texture
//
//  Copyright (c) Facebook, Inc. and its affiliates.  All rights reserved.
//  Changes after 4/13/2017 are: Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import "ASPlatformDefines.h"
#import "ASBaseDefines.h"
#import "ASBlockTypes.h"
#import "ASDimension.h"

typedef NS_OPTIONS(unsigned short, ASCellLayoutMode) {
  /**
   * No options set. If cell layout mode is set to ASCellLayoutModeNone, the default values for
   * each flag listed below is used.
   */
  ASCellLayoutModeNone = 0,
  /**
   * If ASCellLayoutModeAlwaysSync is enabled it will cause the ASDataController to wait on the
   * background queue, and this ensures that any new / changed cells are in the hierarchy by the
   * very next CATransaction / frame draw.
   *
   * Note: Sync & Async flags force the behavior to be always one or the other, regardless of the
   * items. Default: If neither ASCellLayoutModeAlwaysSync or ASCellLayoutModeAlwaysAsync is set,
   * default behavior is synchronous when there are 0 or 1 ASCellNodes in the data source, and
   * asynchronous when there are 2 or more.
  */
  ASCellLayoutModeAlwaysSync = 1 << 1,                // Default OFF
  ASCellLayoutModeAlwaysAsync = 1 << 2,               // Default OFF
  ASCellLayoutModeForceIfNeeded = 1 << 3,             // Deprecated, default OFF.
  ASCellLayoutModeAlwaysPassthroughDelegate = 1 << 4, // Deprecated, default ON.
  /** Instead of using performBatchUpdates: prefer using reloadData for changes for collection view */
  ASCellLayoutModeAlwaysReloadData = 1 << 5,          // Default OFF
  /** If flag is enabled nodes are *not* gonna be range managed. */
  ASCellLayoutModeDisableRangeController = 1 << 6,    // Default OFF
  ASCellLayoutModeAlwaysLazy = 1 << 7,                // Deprecated, default OFF.
  /**
   * Defines if the node creation should happen serialized and not in parallel within the
   * data controller
   */
  ASCellLayoutModeSerializeNodeCreation = 1 << 8,     // Default OFF
  /**
   * When set, the performBatchUpdates: API (including animation) is used when handling Section
   * Reload operations. This is useful only when ASCellLayoutModeAlwaysReloadData is enabled and
   * cell height animations are desired.
   */
  ASCellLayoutModeAlwaysBatchUpdateSectionReload = 1 << 9, // Default OFF
};

#if AS_PLATFORM_MACOS

NS_ASSUME_NONNULL_BEGIN

@class ASCollectionView;
@class ASCollectionNode;
@class ASCellNode;
@class ASBatchContext;
@protocol ASSectionContext;

@protocol ASCommonCollectionDataSource <NSObject>
@optional
- (NSInteger)collectionView:(ASCollectionView *)collectionView numberOfItemsInSection:(NSInteger)section;
- (NSInteger)numberOfSectionsInCollectionView:(ASCollectionView *)collectionView;
@end

@protocol ASCommonCollectionDelegate <NSObject>
@optional
- (ASSizeRange)collectionView:(ASCollectionView *)collectionView constrainedSizeForNodeAtIndexPath:(NSIndexPath *)indexPath;
- (ASSizeRange)collectionNode:(ASCollectionNode *)collectionNode constrainedSizeForItemAtIndexPath:(NSIndexPath *)indexPath;
- (void)scrollViewDidScroll:(ASScrollView *)scrollView;
- (void)scrollViewWillBeginDragging:(ASScrollView *)scrollView;
- (void)scrollViewDidEndDecelerating:(ASScrollView *)scrollView;
@end

@protocol ASCollectionDataSource <ASCommonCollectionDataSource, NSObject>
@optional
- (NSInteger)collectionNode:(ASCollectionNode *)collectionNode numberOfItemsInSection:(NSInteger)section;
- (NSInteger)numberOfSectionsInCollectionNode:(ASCollectionNode *)collectionNode;

- (nullable id)collectionNode:(ASCollectionNode *)collectionNode nodeModelForItemAtIndexPath:(NSIndexPath *)indexPath;

- (ASCellNodeBlock)collectionView:(ASCollectionView *)collectionView nodeBlockForItemAtIndexPath:(NSIndexPath *)indexPath;
- (ASCellNode *)collectionView:(ASCollectionView *)collectionView nodeForItemAtIndexPath:(NSIndexPath *)indexPath;
- (ASCellNodeBlock)collectionNode:(ASCollectionNode *)collectionNode nodeBlockForItemAtIndexPath:(NSIndexPath *)indexPath;
- (ASCellNode *)collectionNode:(ASCollectionNode *)collectionNode nodeForItemAtIndexPath:(NSIndexPath *)indexPath;

- (ASCellNodeBlock)collectionNode:(ASCollectionNode *)collectionNode nodeBlockForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath;
- (ASCellNode *)collectionNode:(ASCollectionNode *)collectionNode nodeForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath;
- (ASCellNode *)collectionView:(ASCollectionView *)collectionView nodeForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath;

- (nullable id<ASSectionContext>)collectionNode:(ASCollectionNode *)collectionNode contextForSection:(NSInteger)section;
- (NSArray<NSString *> *)collectionNode:(ASCollectionNode *)collectionNode supplementaryElementKindsInSection:(NSInteger)section;

- (void)collectionViewLockDataSource:(ASCollectionView *)collectionView;
- (void)collectionViewUnlockDataSource:(ASCollectionView *)collectionView;
@end

@protocol ASCollectionDelegate <ASCommonCollectionDelegate, NSObject>
@optional
- (ASSizeRange)collectionNode:(ASCollectionNode *)collectionNode constrainedSizeForItemAtIndexPath:(NSIndexPath *)indexPath;
- (ASSizeRange)collectionView:(ASCollectionView *)collectionView constrainedSizeForNodeAtIndexPath:(NSIndexPath *)indexPath;

- (void)collectionNode:(ASCollectionNode *)collectionNode willDisplayItemWithNode:(ASCellNode *)node;
- (void)collectionNode:(ASCollectionNode *)collectionNode didEndDisplayingItemWithNode:(ASCellNode *)node;
- (void)collectionNode:(ASCollectionNode *)collectionNode willDisplaySupplementaryElementWithNode:(ASCellNode *)node;
- (void)collectionNode:(ASCollectionNode *)collectionNode didEndDisplayingSupplementaryElementWithNode:(ASCellNode *)node;

- (void)collectionView:(ASCollectionView *)collectionView willDisplayNode:(ASCellNode *)node forItemAtIndexPath:(NSIndexPath *)indexPath;
- (void)collectionView:(ASCollectionView *)collectionView didEndDisplayingNode:(ASCellNode *)node forItemAtIndexPath:(NSIndexPath *)indexPath;
- (void)collectionView:(ASCollectionView *)collectionView willDisplaySupplementaryView:(NSView *)view forElementKind:(NSString *)elementKind atIndexPath:(NSIndexPath *)indexPath;
- (void)collectionView:(ASCollectionView *)collectionView didEndDisplayingSupplementaryView:(NSView *)view forElementOfKind:(NSString *)elementKind atIndexPath:(NSIndexPath *)indexPath;

- (BOOL)collectionNode:(ASCollectionNode *)collectionNode shouldHighlightItemAtIndexPath:(NSIndexPath *)indexPath;
- (void)collectionNode:(ASCollectionNode *)collectionNode didHighlightItemAtIndexPath:(NSIndexPath *)indexPath;
- (void)collectionNode:(ASCollectionNode *)collectionNode didUnhighlightItemAtIndexPath:(NSIndexPath *)indexPath;
- (BOOL)collectionNode:(ASCollectionNode *)collectionNode shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath;
- (void)collectionNode:(ASCollectionNode *)collectionNode didSelectItemAtIndexPath:(NSIndexPath *)indexPath;
- (BOOL)collectionNode:(ASCollectionNode *)collectionNode shouldDeselectItemAtIndexPath:(NSIndexPath *)indexPath;
- (void)collectionNode:(ASCollectionNode *)collectionNode didDeselectItemAtIndexPath:(NSIndexPath *)indexPath;

- (BOOL)collectionView:(ASCollectionView *)collectionView shouldHighlightItemAtIndexPath:(NSIndexPath *)indexPath;
- (void)collectionView:(ASCollectionView *)collectionView didHighlightItemAtIndexPath:(NSIndexPath *)indexPath;
- (void)collectionView:(ASCollectionView *)collectionView didUnhighlightItemAtIndexPath:(NSIndexPath *)indexPath;
- (BOOL)collectionView:(ASCollectionView *)collectionView shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath;
- (void)collectionView:(ASCollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath;
- (BOOL)collectionView:(ASCollectionView *)collectionView shouldDeselectItemAtIndexPath:(NSIndexPath *)indexPath;
- (void)collectionView:(ASCollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath;

- (BOOL)collectionNode:(ASCollectionNode *)collectionNode shouldShowMenuForItemAtIndexPath:(NSIndexPath *)indexPath;
- (BOOL)collectionNode:(ASCollectionNode *)collectionNode canPerformAction:(SEL)action forItemAtIndexPath:(NSIndexPath *)indexPath sender:(nullable id)sender;
- (void)collectionNode:(ASCollectionNode *)collectionNode performAction:(SEL)action forItemAtIndexPath:(NSIndexPath *)indexPath sender:(nullable id)sender;

- (BOOL)collectionView:(ASCollectionView *)collectionView shouldShowMenuForItemAtIndexPath:(NSIndexPath *)indexPath;
- (BOOL)collectionView:(ASCollectionView *)collectionView canPerformAction:(SEL)action forItemAtIndexPath:(NSIndexPath *)indexPath withSender:(nullable id)sender;
- (void)collectionView:(ASCollectionView *)collectionView performAction:(SEL)action forItemAtIndexPath:(NSIndexPath *)indexPath withSender:(nullable id)sender;

- (void)collectionNode:(ASCollectionNode *)collectionNode willBeginBatchFetchWithContext:(ASBatchContext *)context;
- (BOOL)shouldBatchFetchForCollectionNode:(ASCollectionNode *)collectionNode;
- (void)collectionView:(ASCollectionView *)collectionView willBeginBatchFetchWithContext:(ASBatchContext *)context;
- (BOOL)shouldBatchFetchForCollectionView:(ASCollectionView *)collectionView;
@end

NS_ASSUME_NONNULL_END

#else

NS_ASSUME_NONNULL_BEGIN

/**
 * This is a subset of UICollectionViewDataSource.
 *
 * @see ASCollectionDataSource
 */
@protocol ASCommonCollectionDataSource <NSObject>

@optional

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section ASDISPLAYNODE_DEPRECATED_MSG("Implement -collectionNode:numberOfItemsInSection: instead.");

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView ASDISPLAYNODE_DEPRECATED_MSG("Implement -numberOfSectionsInCollectionNode: instead.");

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath ASDISPLAYNODE_DEPRECATED_MSG("Implement - collectionNode:nodeForSupplementaryElementOfKind:atIndexPath: instead.");

@end


/**
 * This is a subset of UICollectionViewDelegate.
 *
 * @see ASCollectionDelegate
 */
@protocol ASCommonCollectionDelegate <NSObject, UIScrollViewDelegate>

@optional

- (UICollectionViewTransitionLayout *)collectionView:(UICollectionView *)collectionView transitionLayoutForOldLayout:(ASCollectionViewLayout *)fromLayout newLayout:(ASCollectionViewLayout *)toLayout;

- (void)collectionView:(UICollectionView *)collectionView willDisplaySupplementaryView:(UICollectionReusableView *)view forElementKind:(NSString *)elementKind atIndexPath:(NSIndexPath *)indexPath ASDISPLAYNODE_DEPRECATED_MSG("Implement -collectionNode:willDisplaySupplementaryView:forElementKind:atIndexPath: instead.");
- (void)collectionView:(UICollectionView *)collectionView didEndDisplayingSupplementaryView:(UICollectionReusableView *)view forElementOfKind:(NSString *)elementKind atIndexPath:(NSIndexPath *)indexPath ASDISPLAYNODE_DEPRECATED_MSG("Implement -collectionNode:didEndDisplayingSupplementaryView:forElementKind:atIndexPath: instead.");

- (BOOL)collectionView:(UICollectionView *)collectionView shouldHighlightItemAtIndexPath:(NSIndexPath *)indexPath ASDISPLAYNODE_DEPRECATED_MSG("Implement collectionNode:shouldHighlightItemAtIndexPath: instead.");
- (void)collectionView:(UICollectionView *)collectionView didHighlightItemAtIndexPath:(NSIndexPath *)indexPath ASDISPLAYNODE_DEPRECATED_MSG("Implement collectionNode:didHighlightItemAtIndexPath: instead.");
- (void)collectionView:(UICollectionView *)collectionView didUnhighlightItemAtIndexPath:(NSIndexPath *)indexPath ASDISPLAYNODE_DEPRECATED_MSG("Implement collectionNode:didUnhighlightItemAtIndexPath: instead.");

- (BOOL)collectionView:(UICollectionView *)collectionView shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath ASDISPLAYNODE_DEPRECATED_MSG("Implement collectionNode:shouldSelectItemAtIndexPath: instead.");
- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath ASDISPLAYNODE_DEPRECATED_MSG("Implement collectionNode:didSelectItemAtIndexPath: instead.");
- (BOOL)collectionView:(UICollectionView *)collectionView shouldDeselectItemAtIndexPath:(NSIndexPath *)indexPath ASDISPLAYNODE_DEPRECATED_MSG("Implement collectionNode:shouldDeselectItemAtIndexPath: instead.");
- (void)collectionView:(UICollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath ASDISPLAYNODE_DEPRECATED_MSG("Implement collectionNode:didDeselectItemAtIndexPath: instead.");

- (BOOL)collectionView:(UICollectionView *)collectionView shouldShowMenuForItemAtIndexPath:(NSIndexPath *)indexPath ASDISPLAYNODE_DEPRECATED_MSG("Implement collectionNode:shouldShowMenuForItemAtIndexPath: instead.");
- (BOOL)collectionView:(UICollectionView *)collectionView canPerformAction:(SEL)action forItemAtIndexPath:(NSIndexPath *)indexPath withSender:(nullable id)sender ASDISPLAYNODE_DEPRECATED_MSG("Implement collectionNode:canPerformAction:forItemAtIndexPath:withSender: instead.");
- (void)collectionView:(UICollectionView *)collectionView performAction:(SEL)action forItemAtIndexPath:(NSIndexPath *)indexPath withSender:(nullable id)sender ASDISPLAYNODE_DEPRECATED_MSG("Implement collectionNode:performAction:forItemAtIndexPath:withSender: instead.");

#if AS_PLATFORM_IOS
- (nullable UIContextMenuConfiguration *)collectionView:(UICollectionView *)collectionView contextMenuConfigurationForItemAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point API_AVAILABLE(ios(13.0)) API_UNAVAILABLE(tvos);

- (nullable UITargetedPreview *)collectionView:(UICollectionView *)collectionView previewForHighlightingContextMenuWithConfiguration:(UIContextMenuConfiguration *)configuration API_AVAILABLE(ios(13.0)) API_UNAVAILABLE(tvos);

- (nullable UITargetedPreview *)collectionView:(UICollectionView *)collectionView previewForDismissingContextMenuWithConfiguration:(UIContextMenuConfiguration *)configuration API_AVAILABLE(ios(13.0)) API_UNAVAILABLE(tvos);

- (void)collectionView:(UICollectionView *)collectionView willPerformPreviewActionForMenuWithConfiguration:(UIContextMenuConfiguration *)configuration animator:(id<UIContextMenuInteractionCommitAnimating>)animator API_AVAILABLE(ios(13.0)) API_UNAVAILABLE(tvos);
#endif
@end

NS_ASSUME_NONNULL_END

#endif // !AS_PLATFORM_MACOS
