//
//  ASPagerNode+Beta.h
//  Texture
//
//  Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import "ASPagerNode.h"
#import "ASPlatformDefines.h"

@interface ASPagerNode (Beta)

#if !AS_PLATFORM_MACOS
- (instancetype)initUsingAsyncCollectionLayout;
#endif

@end
