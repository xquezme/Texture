//
//  ASSnapshotTestCase.mm
//  Texture
//
//  Copyright (c) Facebook, Inc. and its affiliates.  All rights reserved.
//  Changes after 4/13/2017 are: Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import "ASSnapshotTestCase.h"
#import <ASAvailability.h>
#import <ASDisplayNode+Beta.h>
#import <ASDisplayNodeExtras.h>
#import <ASDisplayNode+Subclasses.h>

NSOrderedSet *ASSnapshotTestCaseDefaultSuffixes(void)
{
  NSMutableOrderedSet *suffixesSet = [[NSMutableOrderedSet alloc] init];
  [suffixesSet addObject:@"_64"];
  return [suffixesSet copy];
}

@implementation ASSnapshotTestCase

- (void)setUp
{
  [super setUp];
#if TEXTURE_BUILT_WITH_SPM
  // When built via SPM, reference images live in the source tree at
  // Tests/ReferenceImages_64/, not inside the test bundle.  Derive the absolute
  // path from __FILE__ (the compile-time path of this source file) so we do not
  // depend on FB_REFERENCE_IMAGE_DIR being forwarded by xcodebuild to the
  // iOS Simulator test runner (it isn't, reliably).
  //
  // FBSnapshotTestCase appends "/ReferenceImages" + suffix (e.g. "_64") to
  // bundleResourcePath, so we point it at the Tests/ directory and it will
  // naturally find Tests/ReferenceImages_64/<ClassName>/<test>@2x.png.
  //
  //   __FILE__ = .../Tests/TextureTestSupport/ASSnapshotTestCase.mm
  //              → stringByDeletingLastPathComponent → .../Tests/TextureTestSupport
  //              → stringByDeletingLastPathComponent → .../Tests   ← bundleResourcePath
  {
    NSString *thisFile = @(__FILE__);
    NSString *testsDir = [thisFile.stringByDeletingLastPathComponent
                                   stringByDeletingLastPathComponent];
    self.bundleResourcePath = testsDir;
  }
#endif
  // To re-record snapshots, set self.recordMode = YES here (ad hoc) or set the
  // FB_RECORD_MODE=1 environment variable when running from Xcode's scheme editor.
  if ([NSProcessInfo.processInfo.environment[@"FB_RECORD_MODE"] boolValue]) {
    self.recordMode = YES;
  }
}

+ (void)hackilySynchronouslyRecursivelyRenderNode:(ASDisplayNode *)node
{
  // Disable asynchronous display for rendering snapshots since things like UITraitCollection are thread-local
  // so changes to them (`-[UITraitCollection performAsCurrentTraitCollection]`) aren't preserved across threads.
  // Since the goal of this method is to just to ensure a node is rendered before snapshotting, this should be reasonable default for all callers.
  ASTraitCollectionPropagateDown(node, ASPrimitiveTraitCollectionFromUITraitCollection(UITraitCollection.currentTraitCollection));
  node.displaysAsynchronously = NO;
  ASDisplayNodePerformBlockOnEveryNode(nil, node, YES, ^(ASDisplayNode * _Nonnull node) {
    [node.layer setNeedsDisplay];
  });
  [node recursivelyEnsureDisplaySynchronously:YES];
}

@end
