//
//  ASLayoutManager.mm
//  Texture
//
//  Copyright (c) Facebook, Inc. and its affiliates.  All rights reserved.
//  Changes after 4/13/2017 are: Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import "ASLayoutManager.h"

@implementation ASLayoutManager

#if AS_PLATFORM_MACOS
- (void)showCGGlyphs:(const CGGlyph *)glyphs
           positions:(const NSPoint *)positions
               count:(NSUInteger)glyphCount
                font:(ASFont *)font
              matrix:(NSAffineTransform *)textMatrix
          attributes:(NSDictionary *)attributes
           inContext:(NSGraphicsContext *)graphicsContext
{
  // AppKit exposes the same hook, but with NSGraphicsContext / NSAffineTransform.
  ASColor *foregroundColor = attributes[NSForegroundColorAttributeName];
  if (foregroundColor != nil) {
    CGContextRef context = graphicsContext.CGContext;
    if (context != NULL) {
      CGContextSetFillColorWithColor(context, foregroundColor.CGColor);
    }
  }

  [super showCGGlyphs:glyphs
            positions:positions
                count:glyphCount
                 font:font
               matrix:textMatrix
           attributes:attributes
            inContext:graphicsContext];
}
#else
- (void)showCGGlyphs:(const CGGlyph *)glyphs
           positions:(const CGPoint *)positions
               count:(NSUInteger)glyphCount
                font:(ASFont *)font
              matrix:(CGAffineTransform)textMatrix
          attributes:(NSDictionary *)attributes
           inContext:(CGContextRef)graphicsContext
{

  // NSLayoutManager has a hard coded internal color for hyperlinks which ignores
  // NSForegroundColorAttributeName. To get around this, we force the fill color
  // in the current context to match NSForegroundColorAttributeName.
  ASColor *foregroundColor = attributes[NSForegroundColorAttributeName];
  
  if (foregroundColor)
  {
    CGContextSetFillColorWithColor(graphicsContext, foregroundColor.CGColor);
  }
  
  [super showCGGlyphs:glyphs
            positions:positions
                count:glyphCount
                 font:font
               matrix:textMatrix
           attributes:attributes
            inContext:graphicsContext];
}
#endif

@end
