//
//  ASTestCase.mm
//  Texture
//
//  Copyright (c) Facebook, Inc. and its affiliates.  All rights reserved.
//  Changes after 4/13/2017 are: Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import "ASTestCase.h"
#import <objc/runtime.h>
#import <AsyncDisplayKit.h>
#import <OCMock/OCMock.h>
#import "OCMockObject+ASAdditions.h"

static __weak ASTestCase *currentTestCase;

#if TEXTURE_BUILT_WITH_SPM
// ---------------------------------------------------------------------------
// SPM resource-bundle shim  (compiled only when built via Swift Package Manager)
//
// When built with SPM, resources declared in a target are placed in a
// separate nested bundle – e.g. Texture_TextureTestSupport.bundle – rather
// than at the root of the .xctest bundle.  Test code written for the
// Xcode-project build uses [NSBundle bundleForClass:[self class]], which
// returns the outer .xctest bundle and therefore cannot find those nested
// resources.
//
// This category swizzles the two NSBundle resource-lookup entry points that
// our tests use so that, when the primary lookup on the receiver returns nil,
// it falls back to searching every *.bundle embedded directly inside the
// receiver's bundle.  The swizzles are installed exactly once at +load time.
//
// TestResources (shared test fixtures: images, plists, ASThrashTestRecordedCase)
// are bundled into Texture_TextureTestSupport.bundle via Package.swift, which
// declares them as resources of the TextureTestSupport library target.  That
// sub-bundle is then embedded in both TextureUnitTests.xctest and
// TextureSnapshotTests.xctest by the linker.
// ---------------------------------------------------------------------------
@interface NSBundle (ASTestSPMResourceFallback)
@end

@implementation NSBundle (ASTestSPMResourceFallback)

+ (void)load
{
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    // Swizzle -pathForResource:ofType:inDirectory:
    method_exchangeImplementations(
        class_getInstanceMethod([NSBundle class],
            @selector(pathForResource:ofType:inDirectory:)),
        class_getInstanceMethod([NSBundle class],
            @selector(as_spm_pathForResource:ofType:inDirectory:)));

    // Swizzle -URLForResource:withExtension:subdirectory:
    method_exchangeImplementations(
        class_getInstanceMethod([NSBundle class],
            @selector(URLForResource:withExtension:subdirectory:)),
        class_getInstanceMethod([NSBundle class],
            @selector(as_spm_URLForResource:withExtension:subdirectory:)));
  });
}

// Helper: URLs of every *.bundle embedded directly in this bundle.
- (NSArray<NSURL *> *)as_spm_subBundleURLs
{
  return [self URLsForResourcesWithExtension:@"bundle" subdirectory:nil] ?: @[];
}

// After swizzling, `as_spm_pathForResource:...` calls the *original* IMP.
- (nullable NSString *)as_spm_pathForResource:(nullable NSString *)name
                                       ofType:(nullable NSString *)ext
                                  inDirectory:(nullable NSString *)subpath
{
  NSString *result = [self as_spm_pathForResource:name ofType:ext inDirectory:subpath];
  if (result) return result;

  for (NSURL *url in [self as_spm_subBundleURLs]) {
    NSBundle *sub = [NSBundle bundleWithURL:url];
    if (!sub) continue;
    NSString *subResult = [sub as_spm_pathForResource:name ofType:ext inDirectory:subpath];
    if (subResult) return subResult;
  }
  return nil;
}

// After swizzling, `as_spm_URLForResource:...` calls the *original* IMP.
- (nullable NSURL *)as_spm_URLForResource:(nullable NSString *)name
                            withExtension:(nullable NSString *)ext
                             subdirectory:(nullable NSString *)subpath
{
  NSURL *result = [self as_spm_URLForResource:name withExtension:ext subdirectory:subpath];
  if (result) return result;

  for (NSURL *url in [self as_spm_subBundleURLs]) {
    NSBundle *sub = [NSBundle bundleWithURL:url];
    if (!sub) continue;
    NSURL *subResult = [sub as_spm_URLForResource:name withExtension:ext subdirectory:subpath];
    if (subResult) return subResult;
  }
  return nil;
}

@end
#endif // TEXTURE_BUILT_WITH_SPM

@implementation ASTestCase {
  ASWeakSet *registeredMockObjects;
}

- (void)setUp
{
  [super setUp];
  currentTestCase = self;
  registeredMockObjects = [ASWeakSet new];
}

- (void)tearDown
{
  [ASConfigurationManager test_resetWithConfiguration:nil];
  
  // Clear out all application windows. Note: the system will retain these sometimes on its
  // own but we'll do our best.
  for (UIWindow *window in [UIApplication sharedApplication].windows) {
    [window resignKeyWindow];
    window.hidden = YES;
    window.rootViewController = nil;
    for (UIView *view in window.subviews) {
      [view removeFromSuperview];
    }
  }
  
  // Set nil for all our subclasses' ivars. Use setValue:forKey: so memory is managed correctly.
  // This is important to do _inside_ the test-perform, so that we catch any issues caused by the
  // deallocation, and so that we're inside the @autoreleasepool for the test invocation.
  Class c = [self class];
  while (c != [ASTestCase class]) {
    unsigned int ivarCount;
    Ivar *ivars = class_copyIvarList(c, &ivarCount);
    for (unsigned int i = 0; i < ivarCount; i++) {
      Ivar ivar = ivars[i];
      NSString *key = [NSString stringWithCString:ivar_getName(ivar) encoding:NSUTF8StringEncoding];
      if (OCMIsObjectType(ivar_getTypeEncoding(ivar))) {
      	[self setValue:nil forKey:key];
      }
    }
    if (ivars) {
      free(ivars);
    }

    c = [c superclass];
  }

  for (OCMockObject *mockObject in registeredMockObjects) {
    OCMVerifyAll(mockObject);
    [mockObject stopMocking];

    // Invocations retain arguments, which may cause retain cycles.
    // Manually clear them all out.
    NSMutableArray *invocations = object_getIvar(mockObject, class_getInstanceVariable(OCMockObject.class, "invocations"));
    [invocations removeAllObjects];
  }

  // Go ahead and spin the run loop before finishing, so the system
  // unregisters/cleans up whatever possible.
  [NSRunLoop.mainRunLoop runMode:NSDefaultRunLoopMode beforeDate:NSDate.distantPast];
  
  [super tearDown];
}

- (void)invokeTest
{
  // This will call setup, run, then teardown.
  @autoreleasepool {
    [super invokeTest];
  }
}

+ (ASTestCase *)currentTestCase
{
  return currentTestCase;
}

@end

@implementation ASTestCase (OCMockObjectRegistering)

- (void)registerMockObject:(id)mockObject
{
  @synchronized (registeredMockObjects) {
    [registeredMockObjects addObject:mockObject];
  }
}

@end
