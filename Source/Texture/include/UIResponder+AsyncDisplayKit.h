//
//  UIResponder+AsyncDisplayKit.h
//  Texture
//
//  Copyright (c) Facebook, Inc. and its affiliates.  All rights reserved.
//  Changes after 4/13/2017 are: Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import "ASPlatformDefines.h"

NS_ASSUME_NONNULL_BEGIN

#if AS_PLATFORM_MACOS
 @interface NSResponder (AsyncDisplayKit)
#else
 @interface UIResponder (AsyncDisplayKit)
#endif

/**
 * The nearest view controller above this responder, if one exists.
 *
 * This property must be accessed on the main thread.
 */
@property (nonatomic, nullable, readonly) __kindof ASDisplayViewController *asdk_associatedViewController NS_SWIFT_UI_ACTOR;

@end

NS_ASSUME_NONNULL_END
