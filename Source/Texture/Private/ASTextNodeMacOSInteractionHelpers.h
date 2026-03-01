#import "ASPlatformDefines.h"

@protocol ASTextNodeUserInteractionEnabling <NSObject>
- (BOOL)userInteractionEnabled;
- (void)setUserInteractionEnabled:(BOOL)userInteractionEnabled;
@end

static inline NSArray<NSString *> *ASTextNodeNormalizedLinkAttributeNames(NSArray<NSString *> *linkAttributeNames)
{
  return linkAttributeNames ?: @[];
}

static inline BOOL ASTextNodeShouldAutoEnableUserInteraction(id<ASTextNodeDelegate> delegate,
                                                             NSArray<NSString *> *linkAttributeNames,
                                                             BOOL alwaysHandleTruncationTokenTap)
{
  BOOL handlesLinkInteraction = (delegate != nil)
                             && ([delegate respondsToSelector:@selector(textNode:tappedLinkAttribute:value:atPoint:textRange:)]
                                 || [delegate respondsToSelector:@selector(textNode:longPressedLinkAttribute:value:atPoint:textRange:)]);
  BOOL handlesTruncationInteraction = (delegate != nil)
                                   && [delegate respondsToSelector:@selector(textNodeTappedTruncationToken:)];
  BOOL hasInteractiveLinks = (linkAttributeNames.count > 0) && handlesLinkInteraction;
  BOOL hasInteractiveTruncation = alwaysHandleTruncationTokenTap && handlesTruncationInteraction;
  return (hasInteractiveLinks || hasInteractiveTruncation);
}

static inline void ASTextNodeApplyAutoEnableUserInteractionIfNeeded(id node,
                                                                    id<ASTextNodeDelegate> delegate,
                                                                    NSArray<NSString *> *linkAttributeNames,
                                                                    BOOL alwaysHandleTruncationTokenTap)
{
  id<ASTextNodeUserInteractionEnabling> interactionNode = (id<ASTextNodeUserInteractionEnabling>)node;
  if (ASTextNodeShouldAutoEnableUserInteraction(delegate, linkAttributeNames, alwaysHandleTruncationTokenTap) && ![interactionNode userInteractionEnabled]) {
    [interactionNode setUserInteractionEnabled:YES];
  }
}

#if AS_PLATFORM_MACOS

#import <AppKit/AppKit.h>

static NSString *const ASTextNodeInteractiveItemRangeKey = @"range";
static NSString *const ASTextNodeInteractiveItemAttributeNameKey = @"attributeName";
static NSString *const ASTextNodeInteractiveItemAttributeValueKey = @"attributeValue";

typedef struct {
  BOOL isForwardTab;
  BOOL isReverseTab;
  BOOL isEscape;
  BOOL isActivationKey;
} ASTextNodeMacOSKeyCommand;

typedef void (^ASTextNodeMacOSInteractionVoidBlock)(void);

static inline BOOL ASTextNodeMacOSInteractionObjectIsEqual(id lhs, id rhs)
{
  return lhs == rhs || [lhs isEqual:rhs];
}

static inline ASTextNodeMacOSKeyCommand ASTextNodeMacOSParseKeyCommand(NSEvent *event)
{
  NSString *characters = event.characters;
  NSString *charactersIgnoringModifiers = event.charactersIgnoringModifiers;
  unichar character = (characters.length > 0 ? [characters characterAtIndex:0] : 0);
  unichar unmodifiedCharacter = (charactersIgnoringModifiers.length > 0 ? [charactersIgnoringModifiers characterAtIndex:0] : 0);

  BOOL isReverseTab = (character == NSBackTabCharacter)
                   || (unmodifiedCharacter == NSTabCharacter && (event.modifierFlags & NSEventModifierFlagShift) == NSEventModifierFlagShift);
  BOOL isForwardTab = (character == NSTabCharacter || character == '\t') && !isReverseTab;
  BOOL isEscape = (character == 0x1B || unmodifiedCharacter == 0x1B);
  BOOL isActivationKey = (character == ' ' || character == '\r' || character == '\n' || character == NSEnterCharacter);

  return (ASTextNodeMacOSKeyCommand){
    .isForwardTab = isForwardTab,
    .isReverseTab = isReverseTab,
    .isEscape = isEscape,
    .isActivationKey = isActivationKey,
  };
}

static inline NSArray<NSDictionary<NSString *, id> *> *ASTextNodeMacOSInteractiveItemsForNavigation(NSAttributedString *attributedText,
                                                                                                     NSArray<NSString *> *linkAttributeNames,
                                                                                                     NSRange visibleRange,
                                                                                                     NSRange truncationMessageRange,
                                                                                                     NSString *truncationTokenAttributeName)
{
  if (attributedText.length == 0 || visibleRange.length == 0) {
    return @[];
  }

  visibleRange = NSIntersectionRange(visibleRange, NSMakeRange(0, attributedText.length));
  if (visibleRange.length == 0) {
    return @[];
  }

  NSMutableArray<NSDictionary<NSString *, id> *> *items = [[NSMutableArray alloc] init];
  NSUInteger index = visibleRange.location;
  NSUInteger maxIndex = NSMaxRange(visibleRange);
  while (index < maxIndex) {
    BOOL foundInteractiveRange = NO;
    for (NSString *attributeName in linkAttributeNames) {
      NSRange effectiveRange = NSMakeRange(0, 0);
      id value = [attributedText attribute:attributeName atIndex:index longestEffectiveRange:&effectiveRange inRange:visibleRange];
      if (value == nil) {
        continue;
      }

      NSRange clampedRange = NSIntersectionRange(effectiveRange, visibleRange);
      if (clampedRange.length == 0) {
        continue;
      }

      [items addObject:@{
        ASTextNodeInteractiveItemRangeKey: [NSValue valueWithRange:clampedRange],
        ASTextNodeInteractiveItemAttributeNameKey: attributeName,
        ASTextNodeInteractiveItemAttributeValueKey: value,
      }];
      index = NSMaxRange(clampedRange);
      foundInteractiveRange = YES;
      break;
    }

    if (!foundInteractiveRange) {
      index += 1;
    }
  }

  if (truncationMessageRange.location != NSNotFound && truncationMessageRange.length > 0) {
    [items addObject:@{
      ASTextNodeInteractiveItemRangeKey: [NSValue valueWithRange:truncationMessageRange],
      ASTextNodeInteractiveItemAttributeNameKey: truncationTokenAttributeName,
    }];
    [items sortUsingComparator:^NSComparisonResult(NSDictionary<NSString *, id> * _Nonnull lhs, NSDictionary<NSString *, id> * _Nonnull rhs) {
      NSRange lhsRange = [lhs[ASTextNodeInteractiveItemRangeKey] rangeValue];
      NSRange rhsRange = [rhs[ASTextNodeInteractiveItemRangeKey] rangeValue];
      if (lhsRange.location < rhsRange.location) {
        return NSOrderedAscending;
      }
      if (lhsRange.location > rhsRange.location) {
        return NSOrderedDescending;
      }
      return NSOrderedSame;
    }];
  }

  return items;
}

static inline NSInteger ASTextNodeMacOSNextInteractiveItemIndex(NSArray<NSDictionary<NSString *, id> *> *items,
                                                                NSRange currentRange,
                                                                NSString *currentAttributeName,
                                                                id currentAttributeValue,
                                                                BOOL forward)
{
  if (items.count == 0) {
    return NSNotFound;
  }

  NSInteger currentIndex = NSNotFound;
  for (NSUInteger index = 0; index < items.count; index++) {
    NSDictionary<NSString *, id> *item = items[index];
    NSRange itemRange = [item[ASTextNodeInteractiveItemRangeKey] rangeValue];
    if (!NSEqualRanges(itemRange, currentRange)) {
      continue;
    }

    NSString *itemAttributeName = item[ASTextNodeInteractiveItemAttributeNameKey];
    id itemAttributeValue = item[ASTextNodeInteractiveItemAttributeValueKey];
    BOOL itemMatches = [itemAttributeName isEqualToString:currentAttributeName];
    if (itemAttributeValue != nil || currentAttributeValue != nil) {
      itemMatches = itemMatches && ASTextNodeMacOSInteractionObjectIsEqual(itemAttributeValue, currentAttributeValue);
    }
    if (itemMatches) {
      currentIndex = (NSInteger)index;
      break;
    }
  }

  if (currentIndex == NSNotFound) {
    return forward ? 0 : (NSInteger)items.count - 1;
  }

  if (forward) {
    return (currentIndex + 1) % (NSInteger)items.count;
  }

  return (currentIndex - 1 + (NSInteger)items.count) % (NSInteger)items.count;
}

static inline void ASTextNodeMacOSUpdateCursorForInteractiveText(BOOL hasInteractiveText, BOOL *isHoveringInteractiveText)
{
  if (hasInteractiveText != *isHoveringInteractiveText) {
    *isHoveringInteractiveText = hasInteractiveText;
    if (hasInteractiveText) {
      [[NSCursor pointingHandCursor] set];
    } else {
      [[NSCursor arrowCursor] set];
    }
  }
}

static inline void ASTextNodeMacOSResetTrackingArea(NSTrackingArea * __strong *trackingArea, NSView *view, id owner)
{
  if (*trackingArea != nil && view != nil) {
    [view removeTrackingArea:*trackingArea];
  }

  *trackingArea = nil;

  if (view == nil) {
    return;
  }

  *trackingArea = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                               options:NSTrackingActiveAlways | NSTrackingInVisibleRect | NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved
                                                 owner:owner
                                              userInfo:nil];
  [view addTrackingArea:*trackingArea];
}

static inline void ASTextNodeMacOSForwardUnhandledKeyEvent(NSView *view, NSEvent *event)
{
  NSResponder *nextResponder = view.nextResponder;
  if (nextResponder != nil) {
    [nextResponder keyDown:event];
  } else {
    NSBeep();
  }
}

static inline void ASTextNodeMacOSClearKeyboardFocusState(NSString * __strong *keyboardFocusedLinkAttributeName,
                                                          id __strong *keyboardFocusedLinkAttributeValue,
                                                          NSRange *keyboardFocusRange)
{
  *keyboardFocusedLinkAttributeName = nil;
  *keyboardFocusedLinkAttributeValue = nil;
  *keyboardFocusRange = NSMakeRange(0, 0);
}

static inline void ASTextNodeMacOSClearKeyboardFocusAndRestoreHighlight(NSString * __strong *keyboardFocusedLinkAttributeName,
                                                                        id __strong *keyboardFocusedLinkAttributeValue,
                                                                        NSRange *keyboardFocusRange,
                                                                        BOOL isHoveringInteractiveText,
                                                                        ASTextNodeMacOSInteractionVoidBlock updateActiveHighlight,
                                                                        ASTextNodeMacOSInteractionVoidBlock clearHighlight)
{
  ASTextNodeMacOSClearKeyboardFocusState(keyboardFocusedLinkAttributeName, keyboardFocusedLinkAttributeValue, keyboardFocusRange);

  if (isHoveringInteractiveText) {
    updateActiveHighlight();
  } else {
    clearHighlight();
  }
}

#endif
