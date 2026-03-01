//
//  _ASCollectionViewCell.h
//  Texture
//
//  Copyright (c) Facebook, Inc. and its affiliates.  All rights reserved.
//  Changes after 4/13/2017 are: Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import "ASPlatformDefines.h"
#import "ASBaseDefines.h"
#import "ASCellNode.h"

@class ASCollectionElement;

NS_ASSUME_NONNULL_BEGIN

AS_SUBCLASSING_RESTRICTED // Note: ASDynamicCastStrict is used on instances of this class based on this restriction.
#if AS_PLATFORM_MACOS
@interface _ASCollectionViewCell : NSView
#else
@interface _ASCollectionViewCell : UICollectionViewCell
#endif

@property (nonatomic, nullable) ASCollectionElement *element;
@property (nullable, nonatomic, readonly) ASCellNode *node;
@property (nonatomic, nullable) ASCollectionViewLayoutAttributes *layoutAttributes;

/**
 * Whether or not this cell is interested in cell node visibility events.
 * -cellNodeVisibilityEvent:inScrollView: should be called only if this property is YES.
 */
@property (nonatomic, readonly) BOOL consumesCellNodeVisibilityEvents;

- (void)cellNodeVisibilityEvent:(ASCellNodeVisibilityEvent)event inScrollView:(ASScrollView *)scrollView;

@end

NS_ASSUME_NONNULL_END
