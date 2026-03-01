//
//  UIResponder+AsyncDisplayKit.m
//  Texture
//
//  Copyright (c) Facebook, Inc. and its affiliates.  All rights reserved.
//  Changes after 4/13/2017 are: Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import "UIResponder+AsyncDisplayKit.h"

#import "ASAssert.h"
#import "ASResponderChainEnumerator.h"

#if AS_PLATFORM_MACOS
 @implementation NSResponder (AsyncDisplayKit)
#else
 @implementation UIResponder (AsyncDisplayKit)
#endif

- (__kindof ASDisplayViewController *)asdk_associatedViewController
{
  ASDisplayNodeAssertMainThread();

  for (ASResponder *responder in [self asdk_responderChainEnumerator]) {
    ASDisplayViewController *vc = ASDynamicCast(responder, ASDisplayViewController);
    if (vc) {
      return vc;
    }
  }
  return nil;
}

@end
