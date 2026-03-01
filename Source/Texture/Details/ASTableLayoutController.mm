//
//  ASTableLayoutController.mm
//  Texture
//
//  Copyright (c) Facebook, Inc. and its affiliates.  All rights reserved.
//  Changes after 4/13/2017 are: Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import "ASTableLayoutController.h"

#import "ASPlatformDefines.h"
#import "ASTableView.h"
#import "ASTableViewInternal.h"

#import "ASAssert.h"
#import "ASElementMap.h"

@interface ASTableLayoutController()
@end

@implementation ASTableLayoutController

- (instancetype)initWithTableView:(ASTableView *)tableView
{
  if (!(self = [super init])) {
    return nil;
  }
  _tableView = tableView;
  return self;
}

#pragma mark - ASLayoutController

- (NSHashTable<ASCollectionElement *> *)elementsForScrolling:(ASScrollDirection)scrollDirection rangeMode:(ASLayoutRangeMode)rangeMode rangeType:(ASLayoutRangeType)rangeType map:(ASElementMap *)map
{
  CGRect bounds = _tableView.bounds;

  ASRangeTuningParameters tuningParameters = [self tuningParametersForRangeMode:rangeMode rangeType:rangeType];
  CGRect rangeBounds = CGRectExpandToRangeWithScrollableDirections(bounds, tuningParameters, ASScrollDirectionVerticalDirections, scrollDirection);
#if AS_PLATFORM_MACOS
  NSRange rows = [_tableView rowsInRect:rangeBounds];
  NSHashTable<ASCollectionElement *> *result = [NSHashTable weakObjectsHashTable];
  if (rows.location == NSNotFound || rows.length == 0) {
    return result;
  }
  NSUInteger rowEnd = NSMaxRange(rows);
  for (NSUInteger row = rows.location; row < rowEnd; row++) {
    NSIndexPath *indexPath = [_tableView indexPathForFlatRow:(NSInteger)row inMap:map];
    if (indexPath == nil) {
      continue;
    }
    ASCollectionElement *element = [map elementForItemAtIndexPath:indexPath];
    if (element != nil) {
      [result addObject:element];
    }
  }
  return result;
#else
  NSArray *array = [_tableView indexPathsForRowsInRect:rangeBounds];
  return ASPointerTableByFlatMapping(array, NSIndexPath *indexPath, [map elementForItemAtIndexPath:indexPath]);
#endif
}

- (void)allElementsForScrolling:(ASScrollDirection)scrollDirection rangeMode:(ASLayoutRangeMode)rangeMode displaySet:(NSHashTable<ASCollectionElement *> *__autoreleasing  _Nullable *)displaySet preloadSet:(NSHashTable<ASCollectionElement *> *__autoreleasing  _Nullable *)preloadSet map:(ASElementMap *)map
{
  if (displaySet == NULL || preloadSet == NULL) {
    return;
  }

  *displaySet = [self elementsForScrolling:scrollDirection rangeMode:rangeMode rangeType:ASLayoutRangeTypeDisplay map:map];
  *preloadSet = [self elementsForScrolling:scrollDirection rangeMode:rangeMode rangeType:ASLayoutRangeTypePreload map:map];
  return;
}

@end
