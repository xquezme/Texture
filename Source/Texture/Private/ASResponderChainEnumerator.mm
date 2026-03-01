//
//  ASResponderChainEnumerator.mm
//  Texture
//
//  Copyright (c) Facebook, Inc. and its affiliates.  All rights reserved.
//  Changes after 4/13/2017 are: Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import "ASResponderChainEnumerator.h"
#import "ASAssert.h"

@implementation ASResponderChainEnumerator {
  ASResponder *_currentResponder;
}

- (instancetype)initWithResponder:(ASResponder *)responder
{
  ASDisplayNodeAssertMainThread();
  if (self = [super init]) {
    _currentResponder = responder;
  }
  return self;
}

#pragma mark - NSEnumerator

- (id)nextObject
{
  ASDisplayNodeAssertMainThread();
  id result = [_currentResponder nextResponder];
  _currentResponder = result;
  return result;
}

@end

#if AS_PLATFORM_MACOS
@implementation NSResponder (ASResponderChainEnumerator)
#else
@implementation UIResponder (ASResponderChainEnumerator)
#endif

- (ASResponderChainEnumerator *)asdk_responderChainEnumerator
{
  return [[ASResponderChainEnumerator alloc] initWithResponder:self];
}

@end
