//
//  UICollectionViewLayout+ASConvenience.mm
//  Texture
//
//  Copyright (c) Facebook, Inc. and its affiliates.  All rights reserved.
//  Changes after 4/13/2017 are: Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import "UICollectionViewLayout+ASConvenience.h"

#import "ASPlatformDefines.h"

#import "ASCollectionViewFlowLayoutInspector.h"

#if AS_PLATFORM_MACOS
 @implementation NSCollectionViewLayout (ASLayoutInspectorProviding)
#else
 @implementation UICollectionViewLayout (ASLayoutInspectorProviding)
#endif

- (id<ASCollectionViewLayoutInspecting>)asdk_layoutInspector
{
  ASCollectionViewFlowLayout *flow = ASDynamicCast(self, ASCollectionViewFlowLayout);
  if (flow != nil) {
    return [[ASCollectionViewFlowLayoutInspector alloc] initWithFlowLayout:flow];
  } else {
    return [[ASCollectionViewLayoutInspector alloc] init];
  }
}

@end
