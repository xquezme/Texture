//
//  _ASCollectionViewCell.mm
//  Texture
//
//  Copyright (c) Facebook, Inc. and its affiliates.  All rights reserved.
//  Changes after 4/13/2017 are: Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import <TargetConditionals.h>

#import "_ASCollectionViewCell.h"
#import "ASDisplayNode+Subclasses.h"

#import "ASCellNode+Internal.h"
#import "ASCollectionElement.h"
#import "ASInternalHelpers.h"

@implementation _ASCollectionViewCell

- (ASCellNode *)node
{
  return self.element.node;
}

- (void)setElement:(ASCollectionElement *)element
{
  ASDisplayNodeAssertMainThread();
  ASCellNode *node = element.node;
  if (node != nil) {
    node.layoutAttributes = _layoutAttributes;
  }
  _element = element;

#if !AS_PLATFORM_MACOS
  [node __setSelectedFromUIKit:self.selected];
  [node __setHighlightedFromUIKit:self.highlighted];
#endif
}

- (BOOL)consumesCellNodeVisibilityEvents
{
  ASCellNode *node = self.node;
  if (node == nil) {
    return NO;
  }
  return ASSubclassOverridesSelector([ASCellNode class], [node class], @selector(cellNodeVisibilityEvent:inScrollView:withCellFrame:));
}

- (void)cellNodeVisibilityEvent:(ASCellNodeVisibilityEvent)event inScrollView:(ASScrollView *)scrollView
{
  [self.node cellNodeVisibilityEvent:event inScrollView:scrollView withCellFrame:self.frame];
}

#if !AS_PLATFORM_MACOS
- (void)setSelected:(BOOL)selected
{
  [super setSelected:selected];
  [self.node __setSelectedFromUIKit:selected];
}

- (void)setHighlighted:(BOOL)highlighted
{
  [super setHighlighted:highlighted];
  [self.node __setHighlightedFromUIKit:highlighted];
}
#endif

- (void)setLayoutAttributes:(ASCollectionViewLayoutAttributes *)layoutAttributes
{
  _layoutAttributes = layoutAttributes;
  self.node.layoutAttributes = layoutAttributes;
}

- (void)prepareForReuse
{
  self.layoutAttributes = nil;

  // Need to clear element before UIKit calls setSelected:NO / setHighlighted:NO on its cells
  self.element = nil;
#if !AS_PLATFORM_MACOS
  [super prepareForReuse];
#endif
}

#if !AS_PLATFORM_MACOS
/**
 * In the initial case, this is called by UICollectionView during cell dequeueing, before
 *   we get a chance to assign a node to it, so we must be sure to set these layout attributes
 *   on our node when one is next assigned to us in @c setNode: . Since there may be cases when we _do_ already
 *   have our node assigned e.g. during a layout update for existing cells, we also attempt
 *   to update it now.
 */
- (void)applyLayoutAttributes:(ASCollectionViewLayoutAttributes *)layoutAttributes
{
  [super applyLayoutAttributes:layoutAttributes];
  self.layoutAttributes = layoutAttributes;
}
#endif

/**
 * Keep our node filling our content view.
 */
#if AS_PLATFORM_MACOS
- (void)layout
{
  [super layout];
  self.node.frame = self.bounds;
}
#else
- (void)layoutSubviews
{
  [super layoutSubviews];
  self.node.frame = self.contentView.bounds;
}
#endif

#if !AS_PLATFORM_MACOS
- (ASDisplayView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
  ASCellNode *node = self.node;
  ASDisplayView *nodeView = node.view;
  
  /**
   * The documentation for hitTest:withEvent: on an ASDisplayView explicitly states the fact that:
   * it ignores view objects that are hidden, that have disabled user interactions, or have an
   * alpha level less than 0.01.
   * To be able to determine if the collection view cell should skip going further down the tree
   * based on the states above we use a valid point within the cells bounds and check the
   * superclass hitTest:withEvent: implementation. If this returns a valid value we can go on with
   * checking the node as it's expected to not be in one of these states.
   */
  CGPoint originPointOnView = [self convertPoint:nodeView.bounds.origin fromView:nodeView];
  if (![super hitTest:originPointOnView withEvent:event]) {
    return nil;
  }

  CGPoint pointOnNode = [node.view convertPoint:point fromView:self];
  return [node hitTest:pointOnNode withEvent:event];
}

- (BOOL)pointInside:(CGPoint)point withEvent:(nullable UIEvent *)event
{
  CGPoint pointOnNode = [self.node.view convertPoint:point fromView:self];
  return [self.node pointInside:pointOnNode withEvent:event];
}
#endif

@end

/**
 * A category that makes _ASCollectionViewCell conform to IGListBindable.
 *
 * We don't need to do anything to bind the view model – the cell node
 * serves the same purpose.
 */
#if !AS_PLATFORM_MACOS && (__has_include(<IGListKit/IGListBindable.h>) || __has_include(<IGListBindable.h>))

#if __has_include(<IGListKit/IGListBindable.h>)
#import <IGListKit/IGListBindable.h>
#else
#import <IGListBindable.h>
#endif

@interface _ASCollectionViewCell (IGListBindable) <IGListBindable>
@end

@implementation _ASCollectionViewCell (IGListBindable)

- (void)bindViewModel:(id)viewModel
{
  // nop
}

@end

#endif
