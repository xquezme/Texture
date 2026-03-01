//
//  ASTabBarController.h
//  Texture
//
//  Copyright (c) Facebook, Inc. and its affiliates.  All rights reserved.
//  Changes after 4/13/2017 are: Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import "ASPlatformDefines.h"

#import "ASVisibilityProtocols.h"

NS_ASSUME_NONNULL_BEGIN

#if !AS_PLATFORM_MACOS

/**
 * ASTabBarController
 *
 * @discussion ASTabBarController is a drop in replacement for UITabBarController
 * which implements the memory efficiency improving @c ASManagesChildVisibilityDepth protocol.
 *
 * @see ASManagesChildVisibilityDepth
 */
@interface ASTabBarController : UITabBarController <ASManagesChildVisibilityDepth>

@end

#endif

NS_ASSUME_NONNULL_END
