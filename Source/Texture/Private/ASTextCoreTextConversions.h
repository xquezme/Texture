//
//  ASTextCoreTextConversions.h
//  Texture
//
//  Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#pragma once

#import <CoreText/CoreText.h>

#import "ASPlatformDefines.h"

NS_INLINE NSTextAlignment ASTextAlignmentFromCTTextAlignment(CTTextAlignment alignment) {
  return (NSTextAlignment)alignment;
}

NS_INLINE CTTextAlignment ASTextAlignmentToCTTextAlignment(NSTextAlignment alignment) {
  return (CTTextAlignment)alignment;
}
