//
//  ASPlatformDefines.mm
//  Texture
//
//  Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import "ASPlatformDefines.h"

#if AS_PLATFORM_MACOS

@interface ASDisplayLink ()
{
  __weak id _target;
  SEL _selector;
  NSTimer *_timer;
  CFTimeInterval _timestamp;
  CFTimeInterval _targetTimestamp;
  CFTimeInterval _duration;
}
@end

@implementation ASDisplayLink

+ (instancetype)displayLinkWithTarget:(id)target selector:(SEL)selector
{
  ASDisplayLink *displayLink = [[self alloc] init];
  displayLink->_target = target;
  displayLink->_selector = selector;
  displayLink->_duration = (1.0 / 60.0);
  return displayLink;
}

- (BOOL)isPaused
{
  return _timer != nil && [_timer.fireDate timeIntervalSinceNow] > 0.0;
}

- (void)setPaused:(BOOL)paused
{
  if (_timer == nil) {
    return;
  }
  _timer.fireDate = paused ? [NSDate distantFuture] : [NSDate distantPast];
}

- (CFTimeInterval)duration
{
  return _duration;
}

- (CFTimeInterval)timestamp
{
  return _timestamp;
}

- (CFTimeInterval)targetTimestamp
{
  return _targetTimestamp;
}

- (void)addToRunLoop:(NSRunLoop *)runLoop forMode:(NSString *)mode
{
  if (_timer != nil) {
    return;
  }

  _timer = [NSTimer timerWithTimeInterval:_duration target:self selector:@selector(_timerFired:) userInfo:nil repeats:YES];
  [runLoop addTimer:_timer forMode:mode];
}

- (void)removeFromRunLoop:(NSRunLoop *)runLoop forMode:(NSString *)mode
{
  (void)runLoop;
  (void)mode;
  [_timer invalidate];
  _timer = nil;
}

- (void)invalidate
{
  [_timer invalidate];
  _timer = nil;
}

- (void)_timerFired:(NSTimer *)timer
{
  (void)timer;
  id target = _target;
  if (target == nil || ![target respondsToSelector:_selector]) {
    [self invalidate];
    return;
  }

  CFTimeInterval now = CACurrentMediaTime();
  if (_timestamp == 0) {
    _timestamp = now - _duration;
  } else {
    _timestamp = now;
  }
  _targetTimestamp = _timestamp + _duration;

  NSMethodSignature *signature = [target methodSignatureForSelector:_selector];
  if (signature.numberOfArguments <= 2) {
    void (*func)(id, SEL) = (void (*)(id, SEL))[target methodForSelector:_selector];
    func(target, _selector);
  } else {
    void (*func)(id, SEL, id) = (void (*)(id, SEL, id))[target methodForSelector:_selector];
    func(target, _selector, self);
  }
}

@end

#endif

@implementation NSIndexPath (ASCollectionConveniences)

#if AS_PLATFORM_MACOS
+ (NSIndexPath *)indexPathForItem:(NSInteger)item inSection:(NSInteger)section
{
  NSUInteger indexes[] = { (NSUInteger)section, (NSUInteger)item };
  return [NSIndexPath indexPathWithIndexes:indexes length:2];
}

- (NSInteger)item
{
  return self.length > 1 ? [self indexAtPosition:1] : NSNotFound;
}

- (NSInteger)row
{
  return self.item;
}

- (NSInteger)section
{
  return self.length > 0 ? [self indexAtPosition:0] : NSNotFound;
}
#endif

+ (NSIndexPath *)as_indexPathForItem:(NSInteger)item inSection:(NSInteger)section
{
  return [self indexPathForItem:item inSection:section];
}

- (NSInteger)as_item
{
  return self.item;
}

- (NSInteger)as_section
{
  return self.section;
}

@end
