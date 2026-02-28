//
//  ASCollectionElement+Private.h
//  Texture
//
//  Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import "ASCollectionElement.h"

NS_ASSUME_NONNULL_BEGIN

@class ASCellNode;

/**
 * Private category exposing pool-related state on ASCollectionElement.
 *
 * Imported only by ASCollectionView.mm, ASTableView.mm, ASDataController.mm,
 * and ASRangeController.mm. Do NOT include in public headers.
 */
@interface ASCollectionElement (Private)

/**
 * When YES, _nodeBlock is preserved after first execution so the element can
 * re-execute it on every load cycle (pool dequeue or fresh alloc after eviction).
 *
 * Set YES only when both enableNodeReuse = YES AND a non-empty reuseIdentifier is
 * returned for this item. Must be NO for canUpdateToNodeModel: elements.
 */
@property (nonatomic) BOOL preservesNodeBlock;

/**
 * Called OUTSIDE element._lock after element.node assigns a new node, on whatever
 * thread called -node. Set by ASCollectionView/ASTableView via willFinalizeElement:.
 *
 * Implementations must be thread-safe (may run on BG or MT).
 */
@property (nonatomic, copy, nullable) void (^configureBlock)(ASCellNode *node);

/**
 * Atomically write both the cached layout size and the constrained size it was
 * measured for. Thread-safe; may be called from any thread.
 */
- (void)setCachedLayoutSize:(CGSize)size forConstrainedSize:(ASSizeRange)range;

/**
 * Return the cached layout size if @p constrainedSize matches exactly; CGSizeZero otherwise.
 * Thread-safe; may be called from any thread.
 */
- (CGSize)cachedLayoutSizeForConstrainedSize:(ASSizeRange)constrainedSize;

/**
 * Atomically clear _node and capture _constrainedSize in a single lock acquisition.
 *
 * Returns the evicted node, or nil if _node was nil or preservesNodeBlock == NO.
 * After this returns, nodeIfAllocated == nil on all threads.
 *
 * @note Must be called on the main thread. Both this method and the constrainedSize
 *   mutations in relayoutNodes: (ASDataController) run exclusively on the main thread,
 *   so reading _constrainedSize here without its own lock is safe.
 */
- (nullable ASCellNode *)_evictNodeCapturingConstrainedSize:(ASSizeRange *)outConstrainedSize;

@end

NS_ASSUME_NONNULL_END
