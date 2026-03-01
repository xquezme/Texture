//
//  ASGraphicsContext.h
//  Texture
//
//  Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import "ASBaseDefines.h"
#import "ASBlockTypes.h"
#import "ASPlatformDefines.h"
#import "ASTraitCollection.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * A wrapper for Texture's platform drawing APIs.
 * On iOS/tvOS with ASExperimentalDrawingGlobal enabled and iOS >= 10, this uses UIGraphicsRenderer.
 * Otherwise, it uses the legacy UIGraphicsBeginImageContext path.
 *
 * @param size The size of the context.
 * @param opaque Whether the context should be opaque or not.
 * @param scale The scale of the context. 0 uses main screen scale.
 * @param sourceImage If you are planning to render an ASImage into this context, provide it here and we will use its
 *   preferred renderer format on iOS/tvOS when using UIGraphicsImageRenderer.
 * @param isCancelled An optional block for canceling the drawing before forming the image. Only takes effect under
 *   the legacy code path, as UIGraphicsRenderer does not support cancellation.
 * @param work A block, wherein the current platform graphics context is set based on the arguments.
 *
 * @return The rendered image.
 */
ASDK_EXTERN ASImage *ASGraphicsCreateImageWithOptions(CGSize size, BOOL opaque, CGFloat scale, ASImage * _Nullable sourceImage, asdisplaynode_iscancelled_block_t NS_NOESCAPE _Nullable isCancelled, void (NS_NOESCAPE ^work)(void)) ASDISPLAYNODE_DEPRECATED_MSG("Use ASGraphicsCreateImageWithTraitCollectionAndOptions instead");

/**
* A wrapper for Texture's platform drawing APIs.
* On iOS/tvOS with ASExperimentalDrawingGlobal enabled and iOS >= 10, this uses UIGraphicsRenderer.
* Otherwise, it uses the legacy UIGraphicsBeginImageContext path.
*
* @param traitCollection Trait collection. The `work` block will be executed with this trait collection, so it will affect dynamic colors, etc.
* @param size The size of the context.
* @param opaque Whether the context should be opaque or not.
* @param scale The scale of the context. 0 uses main screen scale.
* @param sourceImage If you are planning to render an ASImage into this context, provide it here and we will use its
*   preferred renderer format on iOS/tvOS when using UIGraphicsImageRenderer.
* @param isCancelled An optional block for canceling the drawing before forming the image.
* @param work A block, wherein the current platform graphics context is set based on the arguments.
*
 * @return The rendered image.
*/
ASDK_EXTERN ASImage *ASGraphicsCreateImage(ASPrimitiveTraitCollection traitCollection, CGSize size, BOOL opaque, CGFloat scale, ASImage * _Nullable sourceImage, asdisplaynode_iscancelled_block_t _Nullable NS_NOESCAPE isCancelled, void (NS_NOESCAPE ^work)(void));

/**
* A wrapper for Texture's platform drawing APIs.
*
* @param traitCollection Trait collection. The `work` block will be executed with this trait collection, so it will affect dynamic colors, etc.
* @param size The size of the context.
* @param opaque Whether the context should be opaque or not.
* @param scale The scale of the context. 0 uses main screen scale.
* @param sourceImage If you are planning to render an ASImage into this context, provide it here and we will use its
*   preferred renderer format on iOS/tvOS when using UIGraphicsImageRenderer.
* @param work A block, wherein the current platform graphics context is set based on the arguments.
*
 * @return The rendered image.
*/
ASDK_EXTERN ASImage *ASGraphicsCreateImageWithTraitCollectionAndOptions(ASPrimitiveTraitCollection traitCollection, CGSize size, BOOL opaque, CGFloat scale, ASImage * _Nullable sourceImage, void (NS_NOESCAPE ^work)(void)) ASDISPLAYNODE_DEPRECATED_MSG("Use ASGraphicsCreateImage instead");

NS_ASSUME_NONNULL_END
