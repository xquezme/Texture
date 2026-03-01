//
//  ASTableViewInternal.h
//  Texture
//
//  Copyright (c) Facebook, Inc. and its affiliates.  All rights reserved.
//  Changes after 4/13/2017 are: Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import "ASTableView.h"
#import "ASPlatformDefines.h"

@class ASDataController;
@class ASTableNode;
@class ASRangeController;
@class ASElementMap;
@protocol ASTableDelegate;
@protocol ASTableDataSource;

NS_ASSUME_NONNULL_BEGIN

/**
 * Internal APIs for the platform-backed ASTableView runtime.
 */
@interface ASTableView (Internal)

@property (nonatomic, readonly) ASDataController *dataController;
@property (nonatomic, weak) ASTableNode *tableNode;
@property (nonatomic, readonly) ASRangeController *rangeController;
@property (nullable, nonatomic, weak) id<ASTableDelegate> asyncDelegate;
@property (nullable, nonatomic, weak) id<ASTableDataSource> asyncDataSource;
@property (nonatomic) BOOL inverted;
@property (nonatomic) CGFloat leadingScreensForBatching;
@property (nonatomic) BOOL automaticallyAdjustsContentOffset;
@property (nonatomic) ASEdgeInsets contentInset;
@property (nonatomic) CGPoint contentOffset;
#if AS_PLATFORM_MACOS
@property (nonatomic) BOOL allowsSelection;
@property (nonatomic) BOOL allowsSelectionDuringEditing;
@property (nonatomic) BOOL allowsMultipleSelectionDuringEditing;
#endif
@property (nullable, nonatomic, readonly) NSArray<NSIndexPath *> *indexPathsForVisibleRows;
@property (nullable, nonatomic, readonly) NSArray<NSIndexPath *> *indexPathsForSelectedRows;
@property (nullable, nonatomic, readonly) NSIndexPath *indexPathForSelectedRow;

- (void)setContentOffset:(CGPoint)contentOffset animated:(BOOL)animated;
- (void)reloadDataWithCompletion:(nullable void (^)(void))completion;
- (void)relayoutItems;
- (void)beginUpdates;
- (void)endUpdates;
- (void)endUpdatesAnimated:(BOOL)animated completion:(nullable void (^)(BOOL completed))completion;
- (void)waitUntilAllUpdatesAreCommitted;
- (void)insertSections:(NSIndexSet *)sections withRowAnimation:(ASTableViewRowAnimation)animation;
- (void)deleteSections:(NSIndexSet *)sections withRowAnimation:(ASTableViewRowAnimation)animation;
- (void)reloadSections:(NSIndexSet *)sections withRowAnimation:(ASTableViewRowAnimation)animation;
- (void)moveSection:(NSInteger)section toSection:(NSInteger)newSection;
- (void)insertRowsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths withRowAnimation:(ASTableViewRowAnimation)animation;
- (void)deleteRowsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths withRowAnimation:(ASTableViewRowAnimation)animation;
- (void)reloadRowsAtIndexPaths:(NSArray<NSIndexPath *> *)indexPaths withRowAnimation:(ASTableViewRowAnimation)animation;
- (void)moveRowAtIndexPath:(NSIndexPath *)indexPath toIndexPath:(NSIndexPath *)newIndexPath;
- (void)scrollToRowAtIndexPath:(NSIndexPath *)indexPath atScrollPosition:(ASTableViewScrollPosition)scrollPosition animated:(BOOL)animated;
- (void)selectRowAtIndexPath:(NSIndexPath *)indexPath animated:(BOOL)animated scrollPosition:(ASTableViewScrollPosition)scrollPosition;
- (void)deselectRowAtIndexPath:(NSIndexPath *)indexPath animated:(BOOL)animated;
- (nullable NSIndexPath *)indexPathForRowAtPoint:(CGPoint)point;
- (nullable NSArray<NSIndexPath *> *)indexPathsForRowsInRect:(CGRect)rect;
- (nullable NSIndexPath *)indexPathForNode:(ASCellNode *)cellNode;
- (CGRect)rectForRowAtIndexPath:(NSIndexPath *)indexPath;
- (NSArray<ASCellNode *> *)visibleNodes;
- (BOOL)isProcessingUpdates;
- (void)onDidFinishProcessingUpdates:(nullable void (^)(void))completion;

/**
 * Initializer.
 *
 * @param frame A rectangle specifying the initial location and size of the table view in its superview’s coordinates.
 * The frame of the table view changes as table cells are added and deleted.
 *
 * @param style A constant that specifies the style of the table view. See ASTableViewStyle for valid constants.
 *
 * @param dataControllerClass A controller class injected to and used to create a data controller for the table view.
 */
- (nullable instancetype)_initWithFrame:(CGRect)frame style:(ASTableViewStyle)style dataControllerClass:(nullable Class)dataControllerClass owningNode:(nullable ASTableNode *)tableNode;

/// Set YES and we'll log every time we call [super insertRows…] etc
@property (nonatomic) BOOL test_enableSuperUpdateCallLogging;

/**
 * Attempt to get the view-layer index path for the row with the given index path.
 *
 * @param indexPath The index path of the row.
 * @param wait If the item hasn't reached the view yet, this attempts to wait for updates to commit.
 */
- (nullable NSIndexPath *)convertIndexPathFromTableNode:(NSIndexPath *)indexPath waitingIfNeeded:(BOOL)wait;

/**
 * Attempt to get the node index path given the view-layer index path.
 *
 * @param indexPath The index path of the row.
 */
- (nullable NSIndexPath *)convertIndexPathToTableNode:(NSIndexPath *)indexPath;

/**
 * Attempt to get the node index paths given the view-layer index paths.
 *
 * @param indexPaths An array of index paths in the view space
 */
- (nullable NSArray<NSIndexPath *> *)convertIndexPathsToTableNode:(nullable NSArray<NSIndexPath *> *)indexPaths;

/// Convert a sectioned index path to the emulated flat AppKit row in the provided map.
- (NSInteger)flatRowForIndexPath:(nullable NSIndexPath *)indexPath inMap:(nullable ASElementMap *)map;

/// Convert an emulated flat AppKit row to a sectioned index path in the provided map.
- (nullable NSIndexPath *)indexPathForFlatRow:(NSInteger)row inMap:(nullable ASElementMap *)map;

/// Returns the width of the section index view on the right-hand side of the table, if one is present.
- (CGFloat)sectionIndexWidth;

@end

NS_ASSUME_NONNULL_END
