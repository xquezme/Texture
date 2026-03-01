//
//  ASButtonNode+Private.h
//  Texture
//
//  Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import "ASButtonNode.h"
#import "ASTextNode.h"
#import "ASImageNode.h"
#import "ASStackLayoutDefines.h"

@interface ASButtonNode () {
#if !AS_PLATFORM_MACOS
  NSAttributedString *_normalAttributedTitle;
  NSAttributedString *_highlightedAttributedTitle;
  NSAttributedString *_selectedAttributedTitle;
  NSAttributedString *_selectedHighlightedAttributedTitle;
  NSAttributedString *_disabledAttributedTitle;

  ASImage *_normalImage;
  ASImage *_highlightedImage;
  ASImage *_selectedImage;
  ASImage *_selectedHighlightedImage;
  ASImage *_disabledImage;

  ASImage *_normalBackgroundImage;
  ASImage *_highlightedBackgroundImage;
  ASImage *_selectedBackgroundImage;
  ASImage *_selectedHighlightedBackgroundImage;
  ASImage *_disabledBackgroundImage;
#endif

  CGFloat _contentSpacing;
  ASEdgeInsets _contentEdgeInsets;
  ASTextNode *_titleNode;
  ASImageNode *_imageNode;
  ASImageNode *_backgroundImageNode;

  BOOL _laysOutHorizontally;
  ASVerticalAlignment _contentVerticalAlignment;
  ASHorizontalAlignment _contentHorizontalAlignment;
  ASButtonNodeImageAlignment _imageAlignment;
}

@end
