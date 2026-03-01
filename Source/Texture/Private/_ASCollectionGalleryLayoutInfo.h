//
//  _ASCollectionGalleryLayoutInfo.h
//  Texture
//
//  Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import "ASPlatformDefines.h"

@interface _ASCollectionGalleryLayoutInfo : NSObject

// Read-only properties
@property (nonatomic, readonly) CGSize itemSize;
@property (nonatomic, readonly) CGFloat minimumLineSpacing;
@property (nonatomic, readonly) CGFloat minimumInteritemSpacing;
@property (nonatomic, readonly) ASEdgeInsets sectionInset;

- (instancetype)initWithItemSize:(CGSize)itemSize
              minimumLineSpacing:(CGFloat)minimumLineSpacing
         minimumInteritemSpacing:(CGFloat)minimumInteritemSpacing
                    sectionInset:(ASEdgeInsets)sectionInset NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end
