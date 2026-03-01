//
//  ASCollectionViewFlowLayoutInspector.h
//  Texture
//
//  Copyright (c) Facebook, Inc. and its affiliates.  All rights reserved.
//  Changes after 4/13/2017 are: Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import "ASCollectionViewLayoutInspector.h"

NS_ASSUME_NONNULL_BEGIN

@class ASCollectionView;

/**
 * A layout inspector implementation specific for the sizing behavior of ASCollectionViewFlowLayout.
 */
AS_SUBCLASSING_RESTRICTED
@interface ASCollectionViewFlowLayoutInspector : NSObject <ASCollectionViewLayoutInspecting>

@property (nonatomic, weak, readonly) ASCollectionViewFlowLayout *layout;

- (instancetype)init NS_UNAVAILABLE;
- (instancetype)initWithFlowLayout:(ASCollectionViewFlowLayout *)flowLayout NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
