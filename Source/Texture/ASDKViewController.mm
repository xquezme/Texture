//
//  ASDKViewController.mm
//  Texture
//
//  Copyright (c) Facebook, Inc. and its affiliates.  All rights reserved.
//  Changes after 4/13/2017 are: Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import "ASDKViewController.h"
#import "ASDisplayNode+FrameworkPrivate.h"
#import "ASInternalHelpers.h"
#import "ASTraitCollection.h"

#if !AS_PLATFORM_MACOS
#import "ASLog.h"
#import "ASRangeControllerUpdateRangeProtocol+Beta.h"
#import "ASConfigurationInternal.h"
#endif

@implementation ASDKViewController
{
  BOOL _ensureDisplayed;
  BOOL _automaticallyAdjustRangeModeBasedOnViewEvents;
  BOOL _parentManagesVisibilityDepth;
  NSInteger _visibilityDepth;
  ASEdgeInsets _fallbackAdditionalSafeAreaInsets;
#if !AS_PLATFORM_MACOS
  BOOL _selfConformsToRangeModeProtocol;
  BOOL _nodeConformsToRangeModeProtocol;
#endif
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-designated-initializers"

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
  if (!(self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])) {
    return nil;
  }

  [self _initializeInstance];

  return self;
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder
{
  if (!(self = [super initWithCoder:aDecoder])) {
    return nil;
  }

  [self _initializeInstance];

  return self;
}

#pragma clang diagnostic pop

- (instancetype)initWithNode:(ASDisplayNode *)node
{
  if (!(self = [super initWithNibName:nil bundle:nil])) {
    return nil;
  }

  _node = node;
  [self _initializeInstance];

  return self;
}

- (instancetype)init
{
  if (!(self = [super initWithNibName:nil bundle:nil])) {
    return nil;
  }

  [self _initializeInstance];

  return self;
}

- (void)_initializeInstance
{
  _fallbackAdditionalSafeAreaInsets = ASEdgeInsetsZero;

  if (_node == nil) {
    return;
  }

  _node.viewControllerRoot = YES;

#if !AS_PLATFORM_MACOS
  _selfConformsToRangeModeProtocol = [self conformsToProtocol:@protocol(ASRangeControllerUpdateRangeProtocol)];
  _nodeConformsToRangeModeProtocol = [_node conformsToProtocol:@protocol(ASRangeControllerUpdateRangeProtocol)];
  _automaticallyAdjustRangeModeBasedOnViewEvents = _selfConformsToRangeModeProtocol || _nodeConformsToRangeModeProtocol;
#endif

  if (_node.nodeLoaded) {
    [self view];
  } else {
    __weak __typeof__(self) weakSelf = self;
    [_node onDidLoad:^(__kindof ASDisplayNode * _Nonnull node) {
      if ([weakSelf isViewLoaded] == NO) {
        [weakSelf view];
      }
    }];
  }
}

- (void)loadView
{
#if AS_PLATFORM_MACOS
  if (_node == nil) {
    self.view = [[ASDisplayView alloc] initWithFrame:NSZeroRect];
    return;
  }

  ASDisplayNodeAssertTrue(!_node.layerBacked);
  self.view = _node.view;
  [self propagateNewTraitCollection:[self _currentPrimitiveTraitCollection]];
#else
  // Apple applies a frame and autoresizing masks we need. Allocating a view is not
  // nearly as expensive as adding and removing it from a hierarchy, and fortunately
  // we can avoid that here. Enabling layerBacking on a single node in the hierarchy
  // will have a greater performance benefit than the impact of this transient view.
  [super loadView];

  if (_node == nil) {
    return;
  }

  ASDisplayNodeAssertTrue(!_node.layerBacked);

  ASDisplayView *view = self.view;
  CGRect frame = view.frame;
  UIViewAutoresizing autoresizingMask = view.autoresizingMask;

  // We have what we need, so now create and assign the view we actually want.
  view = _node.view;
  _node.frame = frame;
  _node.autoresizingMask = autoresizingMask;
  self.view = view;

  // Ensure that self.node has a valid trait collection before a subclass's viewDidLoad.
  // Any subnodes added in viewDidLoad will then inherit the proper environment.
  ASPrimitiveTraitCollection traitCollection = [self primitiveTraitCollectionForUITraitCollection:self.traitCollection];
  [self propagateNewTraitCollection:traitCollection];
#endif
}

#pragma mark - View Lifecycle

#if AS_PLATFORM_MACOS

- (void)viewWillAppear
{
  [super viewWillAppear];

  _ensureDisplayed = YES;
  [self.view layoutSubtreeIfNeeded];

  if (_parentManagesVisibilityDepth == NO) {
    [self setVisibilityDepth:0];
  }
}

- (void)viewDidDisappear
{
  [super viewDidDisappear];

  if (_parentManagesVisibilityDepth == NO) {
    [self setVisibilityDepth:1];
  }
}

- (void)viewDidLayout
{
  [super viewDidLayout];

  ASPrimitiveTraitCollection traitCollection = [self _currentPrimitiveTraitCollection];
  traitCollection.containerSize = self.view.bounds.size;
  [self propagateNewTraitCollection:traitCollection];

  if (_ensureDisplayed && self.neverShowPlaceholders) {
    _ensureDisplayed = NO;
    [_node recursivelyEnsureDisplaySynchronously:YES];
  }
}

#else

- (void)viewWillLayoutSubviews
{
  [super viewWillLayoutSubviews];

  // Before layout, make sure that our trait collection containerSize actually matches the size of our bounds.
  // If not, we need to update the traits and propagate them.
  CGSize boundsSize = self.view.bounds.size;
  if (CGSizeEqualToSize(self.node.primitiveTraitCollection.containerSize, boundsSize) == NO) {
    [ASDisplayView performWithoutAnimation:^{
      ASPrimitiveTraitCollection traitCollection = [self primitiveTraitCollectionForUITraitCollection:self.traitCollection];
      traitCollection.containerSize = boundsSize;

      // this method will call measure
      [self propagateNewTraitCollection:traitCollection];
    }];
  } else {
    // Call layoutThatFits: to let the node prepare for a layout that will happen shortly in the layout pass of the view.
    // If the node's constrained size didn't change between the last layout pass it's a no-op
    [_node layoutThatFits:[self nodeConstrainedSize]];
  }
}

- (void)viewDidLayoutSubviews
{
  if (_ensureDisplayed && self.neverShowPlaceholders) {
    _ensureDisplayed = NO;
    [_node recursivelyEnsureDisplaySynchronously:YES];
  }
  [super viewDidLayoutSubviews];
}

- (void)_updateNodeFallbackSafeArea
{
  ASEdgeInsets safeArea = ASEdgeInsetsMake(self.topLayoutGuide.length, 0, self.bottomLayoutGuide.length, 0);
  ASEdgeInsets additionalInsets = self.additionalSafeAreaInsets;

  safeArea = ASConcatInsets(safeArea, additionalInsets);

  _node.fallbackSafeAreaInsets = safeArea;
}

ASVisibilityDidMoveToParentViewController;

- (void)viewWillAppear:(BOOL)animated
{
  as_activity_create_for_scope("ASDKViewController will appear");
  os_log_debug(ASNodeLog(), "View controller %@ will appear", self);

  [super viewWillAppear:animated];

  _ensureDisplayed = YES;

  // A layout pass is forced this early to get nodes like ASCollectionNode, ASTableNode etc.
  // into the hierarchy before UIKit applies the scroll view inset adjustments, if automatic subnode management
  // is enabled. Otherwise the insets would not be applied.
  [_node.view layoutIfNeeded];

  if (_parentManagesVisibilityDepth == NO) {
    [self setVisibilityDepth:0];
  }
}

#endif

ASVisibilitySetVisibilityDepth;

#if AS_PLATFORM_MACOS

- (NSInteger)visibilityDepth
{
  return _visibilityDepth;
}

#else

ASVisibilityViewDidDisappearImplementation;
ASVisibilityDepthImplementation;

#endif

- (void)visibilityDepthDidChange
{
#if !AS_PLATFORM_MACOS
  ASLayoutRangeMode rangeMode = ASLayoutRangeModeForVisibilityDepth(self.visibilityDepth);
#if ASEnableVerboseLogging
  NSString *rangeModeString;
  switch (rangeMode) {
    case ASLayoutRangeModeMinimum:
      rangeModeString = @"Minimum";
      break;

    case ASLayoutRangeModeFull:
      rangeModeString = @"Full";
      break;

    case ASLayoutRangeModeVisibleOnly:
      rangeModeString = @"Visible Only";
      break;

    case ASLayoutRangeModeLowMemory:
      rangeModeString = @"Low Memory";
      break;

    default:
      break;
  }
  as_log_verbose(ASNodeLog(), "Updating visibility of %@ to: %@ (visibility depth: %zd)", self, rangeModeString, self.visibilityDepth);
#endif
  [self updateCurrentRangeModeWithModeIfPossible:rangeMode];
#endif
}

#pragma mark - Automatic range mode

- (BOOL)automaticallyAdjustRangeModeBasedOnViewEvents
{
  return _automaticallyAdjustRangeModeBasedOnViewEvents;
}

- (void)setAutomaticallyAdjustRangeModeBasedOnViewEvents:(BOOL)automaticallyAdjustRangeModeBasedOnViewEvents
{
#if !AS_PLATFORM_MACOS
  if (automaticallyAdjustRangeModeBasedOnViewEvents != _automaticallyAdjustRangeModeBasedOnViewEvents) {
    if (automaticallyAdjustRangeModeBasedOnViewEvents && _selfConformsToRangeModeProtocol == NO && _nodeConformsToRangeModeProtocol == NO) {
      NSLog(@"Warning: automaticallyAdjustRangeModeBasedOnViewEvents set to YES in %@, but range mode updating is not possible because neither view controller nor node %@ conform to ASRangeControllerUpdateRangeProtocol.", self, _node);
    }
  }
#endif
  _automaticallyAdjustRangeModeBasedOnViewEvents = automaticallyAdjustRangeModeBasedOnViewEvents;
}

#if !AS_PLATFORM_MACOS

- (void)updateCurrentRangeModeWithModeIfPossible:(ASLayoutRangeMode)rangeMode
{
  if (!_automaticallyAdjustRangeModeBasedOnViewEvents) {
    return;
  }

  if (_selfConformsToRangeModeProtocol) {
    id<ASRangeControllerUpdateRangeProtocol> rangeUpdater = (id<ASRangeControllerUpdateRangeProtocol>)self;
    [rangeUpdater updateCurrentRangeWithMode:rangeMode];
  }

  if (_nodeConformsToRangeModeProtocol) {
    id<ASRangeControllerUpdateRangeProtocol> rangeUpdater = (id<ASRangeControllerUpdateRangeProtocol>)_node;
    [rangeUpdater updateCurrentRangeWithMode:rangeMode];
  }
}

#endif

#pragma mark - Layout Helpers

- (ASSizeRange)nodeConstrainedSize
{
  return ASSizeRangeMake(self.view.bounds.size);
}

- (ASInterfaceState)interfaceState
{
  return _node.interfaceState;
}

- (ASEdgeInsets)additionalSafeAreaInsets
{
#if AS_PLATFORM_MACOS
  return _fallbackAdditionalSafeAreaInsets;
#else
  return super.additionalSafeAreaInsets;
#endif
}

- (void)setAdditionalSafeAreaInsets:(ASEdgeInsets)additionalSafeAreaInsets
{
#if AS_PLATFORM_MACOS
  _fallbackAdditionalSafeAreaInsets = additionalSafeAreaInsets;
  _node.fallbackSafeAreaInsets = additionalSafeAreaInsets;
#else
  [super setAdditionalSafeAreaInsets:additionalSafeAreaInsets];
#endif
}

#pragma mark - ASTraitEnvironment

- (void)propagateNewTraitCollection:(ASPrimitiveTraitCollection)traitCollection
{
  ASPrimitiveTraitCollection oldTraitCollection = self.node.primitiveTraitCollection;

  if (ASPrimitiveTraitCollectionIsEqualToASPrimitiveTraitCollection(traitCollection, oldTraitCollection) == NO) {
#if !AS_PLATFORM_MACOS
    as_activity_scope_verbose(as_activity_create("Propagate ASDKViewController trait collection", AS_ACTIVITY_CURRENT, OS_ACTIVITY_FLAG_DEFAULT));
    os_log_debug(ASNodeLog(), "Propagating new traits for %@: %@", self, NSStringFromASPrimitiveTraitCollection(traitCollection));
#endif
    ASTraitCollectionPropagateDown(self.node, traitCollection);

    // Once we've propagated all the traits, layout this node.
    // Remeasure the node with the latest constrained size – old constrained size may be incorrect.
    [_node layoutThatFits:[self nodeConstrainedSize]];
  }
}

#if AS_PLATFORM_MACOS

- (ASPrimitiveTraitCollection)_currentPrimitiveTraitCollection
{
  CGSize windowSize = self.view.bounds.size;
  if (self.overrideDisplayTraitsWithWindowSize) {
    ASTraitCollection *asyncTraitCollection = self.overrideDisplayTraitsWithWindowSize(windowSize);
    return asyncTraitCollection.primitiveTraitCollection;
  }

  ASPrimitiveTraitCollection traitCollection = ASPrimitiveTraitCollectionMakeDefault();
  traitCollection.containerSize = windowSize;
  return traitCollection;
}

#else

- (ASPrimitiveTraitCollection)primitiveTraitCollectionForUITraitCollection:(UITraitCollection *)traitCollection
{
  if (self.overrideDisplayTraitsWithTraitCollection) {
    ASTraitCollection *asyncTraitCollection = self.overrideDisplayTraitsWithTraitCollection(traitCollection);
    return [asyncTraitCollection primitiveTraitCollection];
  }

  ASDisplayNodeAssertMainThread();
  ASPrimitiveTraitCollection asyncTraitCollection = ASPrimitiveTraitCollectionFromUITraitCollection(traitCollection);
  asyncTraitCollection.containerSize = self.view.frame.size;
  return asyncTraitCollection;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
  [super traitCollectionDidChange:previousTraitCollection];

  ASPrimitiveTraitCollection traitCollection = [self primitiveTraitCollectionForUITraitCollection:self.traitCollection];
  traitCollection.containerSize = self.view.bounds.size;
  [self propagateNewTraitCollection:traitCollection];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
- (void)didRotateFromInterfaceOrientation:(UIInterfaceOrientation)fromInterfaceOrientation
{
  [super didRotateFromInterfaceOrientation:fromInterfaceOrientation];

  ASPrimitiveTraitCollection traitCollection = _node.primitiveTraitCollection;
  traitCollection.containerSize = self.view.bounds.size;
  [self propagateNewTraitCollection:traitCollection];
}
#pragma clang diagnostic pop

#endif

@end
