//
//  UIImage+ASConvenience.mm
//  Texture
//
//  Copyright (c) Facebook, Inc. and its affiliates.  All rights reserved.
//  Changes after 4/13/2017 are: Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import "UIImage+ASConvenience.h"
#import "ASGraphicsContext.h"

#pragma mark - ASDKFastImageNamed

#if AS_PLATFORM_MACOS
 @implementation NSImage (ASDKFastImageNamed)
#else
 @implementation UIImage (ASDKFastImageNamed)
#endif

#if AS_PLATFORM_MACOS
static ASImage *cachedImageNamed(NSString *imageName) NS_RETURNS_RETAINED
{
  static NSCache *imageCache = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    imageCache = [[NSCache alloc] init];
  });

  ASImage *image = nil;
  if (imageName.length > 0) {
    image = [imageCache objectForKey:imageName];
    if (image == nil) {
      image = [ASImage imageNamed:imageName];
      if (image != nil) {
        [imageCache setObject:image forKey:imageName];
      }
    }
  }
  return image;
}
#else
static ASImage *cachedImageNamed(NSString *imageName, UITraitCollection *traitCollection) NS_RETURNS_RETAINED
{
  static NSCache *imageCache = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    // Because NSCache responds to memory warnings, we do not need an explicit limit.
    // all of these objects contain compressed image data and are relatively small
    // compared to the backing stores of text and image views.
    imageCache = [[NSCache alloc] init];
  });

  ASImage *image = nil;
  if ([imageName length] > 0) {
    NSString *imageKey = imageName;
    if (traitCollection) {
      char imageKeyBuffer[256];
      snprintf(imageKeyBuffer, sizeof(imageKeyBuffer), "%s|%ld|%ld|%ld", imageName.UTF8String, (long)traitCollection.horizontalSizeClass, (long)traitCollection.verticalSizeClass, (long)traitCollection.userInterfaceStyle);
      imageKey = [NSString stringWithUTF8String:imageKeyBuffer];
    }

    image = [imageCache objectForKey:imageKey];
    if (!image) {
      image =  [ASImage imageNamed:imageName inBundle:nil compatibleWithTraitCollection:traitCollection];
      if (image) {
        [imageCache setObject:image forKey:imageKey];
      }
    }
  }
  return image;
}
#endif

+ (ASImage *)as_imageNamed:(NSString *)imageName NS_RETURNS_RETAINED
{
#if AS_PLATFORM_MACOS
  return cachedImageNamed(imageName);
#else
  return cachedImageNamed(imageName, nil);
#endif
}

#if !AS_PLATFORM_MACOS
+ (ASImage *)as_imageNamed:(NSString *)imageName compatibleWithTraitCollection:(UITraitCollection *)traitCollection NS_RETURNS_RETAINED
{
  return cachedImageNamed(imageName, traitCollection);
}
#endif

@end

#pragma mark - ASDKResizableRoundedRects

#if AS_PLATFORM_MACOS
 @implementation NSImage (ASDKResizableRoundedRects)
#else
 @implementation UIImage (ASDKResizableRoundedRects)
#endif

+ (ASImage *)as_resizableRoundedImageWithCornerRadius:(CGFloat)cornerRadius
                                          cornerColor:(ASColor *)cornerColor
                                            fillColor:(ASColor *)fillColor NS_RETURNS_RETAINED
{
  return [self as_resizableRoundedImageWithCornerRadius:cornerRadius
                                            cornerColor:cornerColor
                                              fillColor:fillColor
                                            borderColor:nil
                                            borderWidth:1.0
                                         roundedCorners:ASRectCornerAllCorners
                                                  scale:0.0];
}

+ (ASImage *)as_resizableRoundedImageWithCornerRadius:(CGFloat)cornerRadius
                                          cornerColor:(ASColor *)cornerColor
                                            fillColor:(ASColor *)fillColor
                                      traitCollection:(ASPrimitiveTraitCollection) traitCollection NS_RETURNS_RETAINED
{
  return [self as_resizableRoundedImageWithCornerRadius:cornerRadius
                                            cornerColor:cornerColor
                                              fillColor:fillColor
                                            borderColor:nil
                                            borderWidth:1.0
                                         roundedCorners:ASRectCornerAllCorners
                                                  scale:0.0
                                        traitCollection:traitCollection];
}

+ (ASImage *)as_resizableRoundedImageWithCornerRadius:(CGFloat)cornerRadius
                                          cornerColor:(ASColor *)cornerColor
                                            fillColor:(ASColor *)fillColor
                                          borderColor:(ASColor *)borderColor
                                          borderWidth:(CGFloat)borderWidth
                                      traitCollection:(ASPrimitiveTraitCollection) traitCollection NS_RETURNS_RETAINED {
  return [self as_resizableRoundedImageWithCornerRadius:cornerRadius
                                            cornerColor:cornerColor
                                              fillColor:fillColor
                                            borderColor:borderColor
                                            borderWidth:borderWidth
                                         roundedCorners:ASRectCornerAllCorners
                                                  scale:0.0
                                        traitCollection:traitCollection];
}


+ (ASImage *)as_resizableRoundedImageWithCornerRadius:(CGFloat)cornerRadius
                                          cornerColor:(ASColor *)cornerColor
                                            fillColor:(ASColor *)fillColor
                                          borderColor:(ASColor *)borderColor
                                          borderWidth:(CGFloat)borderWidth NS_RETURNS_RETAINED
{
  return [self as_resizableRoundedImageWithCornerRadius:cornerRadius
                                            cornerColor:cornerColor
                                              fillColor:fillColor
                                            borderColor:borderColor
                                            borderWidth:borderWidth
                                         roundedCorners:ASRectCornerAllCorners
                                                  scale:0.0];
}

+ (ASImage *)as_resizableRoundedImageWithCornerRadius:(CGFloat)cornerRadius
                                          cornerColor:(ASColor *)cornerColor
                                            fillColor:(ASColor *)fillColor
                                          borderColor:(ASColor *)borderColor
                                          borderWidth:(CGFloat)borderWidth
                                       roundedCorners:(ASRectCorner)roundedCorners
                                                scale:(CGFloat)scale NS_RETURNS_RETAINED {

  return [self as_resizableRoundedImageWithCornerRadius:cornerRadius
                                            cornerColor:cornerColor
                                              fillColor:fillColor
                                            borderColor:borderColor
                                            borderWidth:borderWidth
                                         roundedCorners:roundedCorners
                                                  scale:scale
                                        traitCollection:ASPrimitiveTraitCollectionMakeDefault()];
}


+ (ASImage *)as_resizableRoundedImageWithCornerRadius:(CGFloat)cornerRadius
                                          cornerColor:(ASColor *)cornerColor
                                            fillColor:(ASColor *)fillColor
                                          borderColor:(ASColor *)borderColor
                                          borderWidth:(CGFloat)borderWidth
                                       roundedCorners:(ASRectCorner)roundedCorners
                                                scale:(CGFloat)scale
                                      traitCollection:(ASPrimitiveTraitCollection) traitCollection NS_RETURNS_RETAINED
{
  static NSCache *__pathCache = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    __pathCache = [[NSCache alloc] init];
    // ASBezierPath objects are fairly small and these are equally sized. 20 should be plenty for many different parameters.
    __pathCache.countLimit = 20;
  });
  
  // Treat clear background color as no background color
  if ([cornerColor isEqual:[ASColor clearColor]]) {
    cornerColor = nil;
  }
  
  CGFloat dimension = (cornerRadius * 2) + 1;
  CGRect bounds = CGRectMake(0, 0, dimension, dimension);
  
  typedef struct {
    ASRectCorner corners;
    CGFloat radius;
  } PathKey;
  PathKey key = { roundedCorners, cornerRadius };
  NSValue *pathKeyObject = [[NSValue alloc] initWithBytes:&key objCType:@encode(PathKey)];

  CGSize cornerRadii = CGSizeMake(cornerRadius, cornerRadius);
#if AS_PLATFORM_MACOS
  NSBezierPath *path = [__pathCache objectForKey:pathKeyObject];
  if (path == nil) {
    path = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:cornerRadii.width yRadius:cornerRadii.height];
    [__pathCache setObject:path forKey:pathKeyObject];
  }
#else
  ASBezierPath *path = [__pathCache objectForKey:pathKeyObject];
  if (path == nil) {
    path = [ASBezierPath bezierPathWithRoundedRect:bounds byRoundingCorners:roundedCorners cornerRadii:cornerRadii];
    [__pathCache setObject:path forKey:pathKeyObject];
  }
#endif
  
  // We should probably check if the background color has any alpha component but that
  // might be expensive due to needing to check mulitple color spaces.
  ASImage *result = ASGraphicsCreateImage(traitCollection, bounds.size, cornerColor != nil, scale, nil, nil, ^{
    BOOL contextIsClean = YES;
    if (cornerColor) {
      contextIsClean = NO;
      [cornerColor setFill];
#if AS_PLATFORM_MACOS
      NSRectFill(bounds);
#else
      // Copy "blend" mode is extra fast because it disregards any value currently in the buffer and overrides directly.
      UIRectFillUsingBlendMode(bounds, kCGBlendModeCopy);
#endif
    }

#if AS_PLATFORM_MACOS
    (void)contextIsClean;
    [fillColor setFill];
    [path fill];
#else
    BOOL canUseCopy = contextIsClean || (CGColorGetAlpha(fillColor.CGColor) == 1);
    [fillColor setFill];
    [path fillWithBlendMode:(canUseCopy ? kCGBlendModeCopy : kCGBlendModeNormal) alpha:1];
#endif

    if (borderColor) {
      [borderColor setStroke];

      // Inset border fully inside filled path (not halfway on each side of path)
      CGRect strokeRect = CGRectInset(bounds, borderWidth / 2.0, borderWidth / 2.0);

      // It is rarer to have a stroke path, and our cache key only handles rounded rects for the exact-stretchable
      // size calculated by cornerRadius, so we won't bother caching this path.  Profiling validates this decision.
#if AS_PLATFORM_MACOS
      NSBezierPath *strokePath = [NSBezierPath bezierPathWithRoundedRect:strokeRect
                                                                 xRadius:cornerRadii.width
                                                                 yRadius:cornerRadii.height];
#else
      ASBezierPath *strokePath = [ASBezierPath bezierPathWithRoundedRect:strokeRect
                                                       byRoundingCorners:roundedCorners
                                                             cornerRadii:cornerRadii];
#endif
      [strokePath setLineWidth:borderWidth];
#if AS_PLATFORM_MACOS
      [strokePath stroke];
#else
      BOOL canUseCopy = (CGColorGetAlpha(borderColor.CGColor) == 1);
      [strokePath strokeWithBlendMode:(canUseCopy ? kCGBlendModeCopy : kCGBlendModeNormal) alpha:1];
#endif
    }
  });
  
#if !AS_PLATFORM_MACOS
  UIEdgeInsets capInsets = UIEdgeInsetsMake(cornerRadius, cornerRadius, cornerRadius, cornerRadius);
  result = [result resizableImageWithCapInsets:capInsets resizingMode:UIImageResizingModeStretch];
#endif
  
  return result;
}

@end
