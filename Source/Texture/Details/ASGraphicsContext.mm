//
//  ASGraphicsContext.mm
//  Texture
//
//  Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import "ASGraphicsContext.h"
#import "ASAssert.h"
#import "ASConfigurationInternal.h"
#import "ASInternalHelpers.h"
#import "ASAvailability.h"


#if AS_PLATFORM_MACOS
  #define ASPerformBlockWithTraitCollection(work, traitCollection) \
    do { \
      (void)(traitCollection); \
      work(); \
    } while (0)
#else
  #define ASPerformBlockWithTraitCollection(work, traitCollection) \
        UITraitCollection *uiTraitCollection = ASPrimitiveTraitCollectionToUITraitCollection(traitCollection); \
        [uiTraitCollection performAsCurrentTraitCollection:^{ \
          work(); \
        }];

  NS_INLINE void ASConfigureExtendedRange(UIGraphicsImageRendererFormat *format)
  {
      // nop. We always use automatic range on iOS >= 12.
  }
#endif

ASImage *ASGraphicsCreateImageWithOptions(CGSize size, BOOL opaque, CGFloat scale, ASImage *sourceImage,
                                          asdisplaynode_iscancelled_block_t NS_NOESCAPE isCancelled,
                                          void (^NS_NOESCAPE work)())
{
  return ASGraphicsCreateImage(ASPrimitiveTraitCollectionMakeDefault(), size, opaque, scale, sourceImage, isCancelled, work);
}

ASImage *ASGraphicsCreateImage(ASPrimitiveTraitCollection traitCollection, CGSize size, BOOL opaque, CGFloat scale, ASImage * sourceImage, asdisplaynode_iscancelled_block_t NS_NOESCAPE isCancelled, void (NS_NOESCAPE ^work)()) {
  if (size.width <= 0 || size.height <= 0) {
    return nil;
  }
  
#if AS_PLATFORM_MACOS
  (void)opaque;
  (void)sourceImage;

  CGFloat effectiveScale = scale > 0.0 ? scale : 1.0;
  NSInteger pixelsWide = MAX((NSInteger)(size.width * effectiveScale), 1);
  NSInteger pixelsHigh = MAX((NSInteger)(size.height * effectiveScale), 1);
  NSBitmapImageRep *imageRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL
                                                                        pixelsWide:pixelsWide
                                                                        pixelsHigh:pixelsHigh
                                                                     bitsPerSample:8
                                                                   samplesPerPixel:4
                                                                          hasAlpha:YES
                                                                          isPlanar:NO
                                                                    colorSpaceName:NSDeviceRGBColorSpace
                                                                       bytesPerRow:0
                                                                      bitsPerPixel:0];
  if (imageRep == nil) {
    return nil;
  }

  imageRep.size = NSSizeFromCGSize(size);
  NSGraphicsContext *graphicsContext = [NSGraphicsContext graphicsContextWithBitmapImageRep:imageRep];
  [NSGraphicsContext saveGraphicsState];
  [NSGraphicsContext setCurrentContext:graphicsContext];

  CGContextRef currentContext = graphicsContext.CGContext;
  if (currentContext != NULL) {
    CGContextScaleCTM(currentContext, effectiveScale, effectiveScale);
  }

  ASPerformBlockWithTraitCollection(work, traitCollection);
  [NSGraphicsContext restoreGraphicsState];

  if (isCancelled != nil && isCancelled()) {
    return nil;
  }

  NSImage *image = [[NSImage alloc] initWithSize:NSSizeFromCGSize(size)];
  [image addRepresentation:imageRep];
  return image;
#else
  if (ASActivateExperimentalFeature(ASExperimentalDrawingGlobal)) {
    // If they used default scale, reuse one of two preferred formats.
    static UIGraphicsImageRendererFormat *defaultFormat;
    static UIGraphicsImageRendererFormat *opaqueFormat;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      defaultFormat = [UIGraphicsImageRendererFormat preferredFormat];
      opaqueFormat = [UIGraphicsImageRendererFormat preferredFormat];
      opaqueFormat.opaque = YES;
      ASConfigureExtendedRange(defaultFormat);
      ASConfigureExtendedRange(opaqueFormat);
    });

    UIGraphicsImageRendererFormat *format;
    if (sourceImage) {
      if (sourceImage.renderingMode == UIImageRenderingModeAlwaysTemplate) {
        // Template images will be black and transparent, so if we use
        // sourceImage.imageRenderFormat it will assume a grayscale color space.
        // This is not good because a template image should be able to tint to any color,
        // so we'll just use the default here.
        format = [UIGraphicsImageRendererFormat preferredFormat];
      } else {
        format = sourceImage.imageRendererFormat;
      }
      // We only want the private bits (color space and bits per component) from the image.
      // We have our own ideas about opacity and scale.
      format.opaque = opaque;
      format.scale = scale;
    } else if (scale == 0 || scale == ASScreenScale()) {
      format = opaque ? opaqueFormat : defaultFormat;
    } else {
      format = [UIGraphicsImageRendererFormat preferredFormat];
      if (opaque) format.opaque = YES;
      format.scale = scale;
      ASConfigureExtendedRange(format);
    }
    
    // Avoid using the imageWithActions: method because it does not support cancellation at the
    // last moment i.e. before actually creating the resulting image.
    __block ASImage *image;
    NSError *error;
    [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format]
        runDrawingActions:^(UIGraphicsImageRendererContext *rendererContext) {
          ASDisplayNodeCAssert(UIGraphicsGetCurrentContext(), @"Should have a context!");
          ASPerformBlockWithTraitCollection(work, traitCollection);
        }
        completionActions:^(UIGraphicsImageRendererContext *rendererContext) {
          if (isCancelled == nil || !isCancelled()) {
            image = rendererContext.currentImage;
          }
        }
        error:&error];
    if (error) {
      NSCAssert(NO, @"Error drawing: %@", error);
    }
    return image;
  }

  // Bad OS or experiment flag. Use UIGraphics* API.
  UIGraphicsBeginImageContextWithOptions(size, opaque, scale);
  ASPerformBlockWithTraitCollection(work, traitCollection)
  ASImage *image = nil;
  if (isCancelled == nil || !isCancelled()) {
    image = UIGraphicsGetImageFromCurrentImageContext();
  }
  UIGraphicsEndImageContext();
  return image;
#endif
}

ASImage *ASGraphicsCreateImageWithTraitCollectionAndOptions(ASPrimitiveTraitCollection traitCollection, CGSize size, BOOL opaque, CGFloat scale, ASImage * sourceImage, void (NS_NOESCAPE ^work)()) {
  return ASGraphicsCreateImage(traitCollection, size, opaque, scale, sourceImage, nil, work);
}
