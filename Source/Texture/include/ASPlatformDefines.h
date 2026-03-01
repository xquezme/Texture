//
//  ASPlatformDefines.h
//  Texture
//
//  Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#pragma once

#import <TargetConditionals.h>
#if TARGET_OS_OSX
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <CoreText/CoreText.h>
#import <QuartzCore/QuartzCore.h>
#define AS_PLATFORM_MACOS 1
#define AS_PLATFORM_IOS 0
#define AS_PLATFORM_TVOS 0

typedef NSView ASDisplayView;
typedef NSViewController ASDisplayViewController;
typedef NSScrollView ASScrollView;
typedef NSColor ASColor;
typedef NSImage ASImage;
typedef NSFont ASFont;
typedef NSBezierPath ASBezierPath;
typedef NSGestureRecognizer ASGestureRecognizer;
typedef NSResponder ASResponder;
typedef NSCollectionViewLayout ASCollectionViewLayout;
typedef NSCollectionViewFlowLayout ASCollectionViewFlowLayout;
typedef NSCollectionViewLayoutAttributes ASCollectionViewLayoutAttributes;
typedef NSCollectionViewScrollPosition ASCollectionViewScrollPosition;
typedef NS_ENUM(NSInteger, ASTableViewStyle) {
  ASTableViewStylePlain = 0,
  ASTableViewStyleGrouped = 1,
  ASTableViewStyleInsetGrouped = 2,
};
typedef NS_ENUM(NSInteger, ASTableViewRowAnimation) {
  ASTableViewRowAnimationNone = 0,
  ASTableViewRowAnimationFade = 1,
  ASTableViewRowAnimationAutomatic = 100,
};
typedef NS_OPTIONS(NSUInteger, ASTableViewScrollPosition) {
  ASTableViewScrollPositionNone = 0,
  ASTableViewScrollPositionTop = 1 << 0,
  ASTableViewScrollPositionMiddle = 1 << 1,
  ASTableViewScrollPositionBottom = 1 << 2,
};
typedef NSEdgeInsets ASEdgeInsets;
#define ASEdgeInsetsMake(top, left, bottom, right) NSEdgeInsetsMake((top), (left), (bottom), (right))
static const ASEdgeInsets ASEdgeInsetsZero = {0, 0, 0, 0};
#define NSStringFromCGRect(rect) NSStringFromRect((rect))
#define NSStringFromCGPoint(point) NSStringFromPoint((point))
#define NSStringFromCGSize(size) NSStringFromSize((size))

@interface ASDisplayLink : NSObject
+ (instancetype _Nonnull)displayLinkWithTarget:(id _Nonnull)target selector:(SEL _Nonnull)selector;
@property (getter=isPaused) BOOL paused;
@property (nonatomic, readonly) CFTimeInterval duration;
@property (nonatomic, readonly) CFTimeInterval timestamp;
@property (nonatomic, readonly) CFTimeInterval targetTimestamp;
- (void)addToRunLoop:(NSRunLoop * _Nonnull)runLoop forMode:(NSString * _Nonnull)mode;
- (void)removeFromRunLoop:(NSRunLoop * _Nonnull)runLoop forMode:(NSString * _Nonnull)mode;
- (void)invalidate;
@end
#else
#import <UIKit/UIKit.h>
#define AS_PLATFORM_MACOS 0
#define AS_PLATFORM_IOS TARGET_OS_IOS
#define AS_PLATFORM_TVOS TARGET_OS_TV

typedef UIView ASDisplayView;
typedef UIViewController ASDisplayViewController;
typedef UIScrollView ASScrollView;
typedef UIColor ASColor;
typedef UIImage ASImage;
typedef UIFont ASFont;
typedef UIBezierPath ASBezierPath;
typedef UIGestureRecognizer ASGestureRecognizer;
typedef UIResponder ASResponder;
typedef UICollectionViewLayout ASCollectionViewLayout;
typedef UICollectionViewFlowLayout ASCollectionViewFlowLayout;
typedef UICollectionViewLayoutAttributes ASCollectionViewLayoutAttributes;
typedef UICollectionViewScrollPosition ASCollectionViewScrollPosition;
typedef UITableViewStyle ASTableViewStyle;
#define ASTableViewStylePlain UITableViewStylePlain
#define ASTableViewStyleGrouped UITableViewStyleGrouped
#ifdef UITableViewStyleInsetGrouped
#define ASTableViewStyleInsetGrouped UITableViewStyleInsetGrouped
#else
#define ASTableViewStyleInsetGrouped UITableViewStyleGrouped
#endif
typedef UITableViewRowAnimation ASTableViewRowAnimation;
#define ASTableViewRowAnimationNone UITableViewRowAnimationNone
#define ASTableViewRowAnimationFade UITableViewRowAnimationFade
#define ASTableViewRowAnimationAutomatic UITableViewRowAnimationAutomatic
typedef UITableViewScrollPosition ASTableViewScrollPosition;
#define ASTableViewScrollPositionNone UITableViewScrollPositionNone
#define ASTableViewScrollPositionTop UITableViewScrollPositionTop
#define ASTableViewScrollPositionMiddle UITableViewScrollPositionMiddle
#define ASTableViewScrollPositionBottom UITableViewScrollPositionBottom
typedef UIEdgeInsets ASEdgeInsets;
#define ASEdgeInsetsMake(top, left, bottom, right) UIEdgeInsetsMake((top), (left), (bottom), (right))
#define ASEdgeInsetsZero UIEdgeInsetsZero
typedef UIRectCorner ASRectCorner;
typedef UIViewContentMode ASDisplayViewContentMode;
#define ASRectCornerTopLeft UIRectCornerTopLeft
#define ASRectCornerTopRight UIRectCornerTopRight
#define ASRectCornerBottomLeft UIRectCornerBottomLeft
#define ASRectCornerBottomRight UIRectCornerBottomRight
#define ASRectCornerAllCorners UIRectCornerAllCorners
typedef CADisplayLink ASDisplayLink;
#endif

#if AS_PLATFORM_MACOS
typedef NS_OPTIONS(NSUInteger, ASRectCorner) {
  ASRectCornerTopLeft = 1 << 0,
  ASRectCornerTopRight = 1 << 1,
  ASRectCornerBottomLeft = 1 << 2,
  ASRectCornerBottomRight = 1 << 3,
  ASRectCornerAllCorners = NSUIntegerMax,
};
#endif

@interface NSIndexPath (ASCollectionConveniences)
+ (NSIndexPath * _Nonnull)as_indexPathForItem:(NSInteger)item inSection:(NSInteger)section;
@property (nonatomic, readonly) NSInteger as_item;
@property (nonatomic, readonly) NSInteger as_section;
@end

static inline CGRect ASRectInsetWithEdgeInsets(CGRect rect, ASEdgeInsets insets) {
  rect.origin.x += insets.left;
  rect.origin.y += insets.top;
  rect.size.width -= (insets.left + insets.right);
  rect.size.height -= (insets.top + insets.bottom);
  return rect;
}

static inline BOOL ASEdgeInsetsEqualToEdgeInsets(ASEdgeInsets lhs, ASEdgeInsets rhs) {
#if AS_PLATFORM_MACOS
  return NSEdgeInsetsEqual(lhs, rhs);
#else
  return UIEdgeInsetsEqualToEdgeInsets(lhs, rhs);
#endif
}

static inline CGRect ASRectFromNSValue(NSValue * _Nonnull value) {
#if AS_PLATFORM_MACOS
  return value.rectValue;
#else
  return value.CGRectValue;
#endif
}

static inline CGSize ASSizeFromNSValue(NSValue * _Nonnull value) {
#if AS_PLATFORM_MACOS
  return value.sizeValue;
#else
  return value.CGSizeValue;
#endif
}

static inline CGPoint ASPointFromNSValue(NSValue * _Nonnull value) {
#if AS_PLATFORM_MACOS
  return value.pointValue;
#else
  return value.CGPointValue;
#endif
}

static inline BOOL ASDisplayViewIsRightToLeft(ASDisplayView * _Nonnull view) {
#if AS_PLATFORM_MACOS
  return view.userInterfaceLayoutDirection == NSUserInterfaceLayoutDirectionRightToLeft;
#else
  return [ASDisplayView userInterfaceLayoutDirectionForSemanticContentAttribute:view.semanticContentAttribute] == UIUserInterfaceLayoutDirectionRightToLeft;
#endif
}
