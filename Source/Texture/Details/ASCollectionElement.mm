//
//  ASCollectionElement.mm
//  Texture
//
//  Copyright (c) Facebook, Inc. and its affiliates.  All rights reserved.
//  Changes after 4/13/2017 are: Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import "ASCollectionElement.h"
#import "ASCollectionElement+Private.h"
#import "ASCellNode+Internal.h"
#import "ASThread.h"

@interface ASCollectionElement ()

/// Required node block used to allocate a cell node. Nil after the first execution
/// unless preservesNodeBlock == YES.
@property (nonatomic) ASCellNodeBlock nodeBlock;

@end

@implementation ASCollectionElement {
  AS::Mutex _lock;
  ASCellNode *_node;

  // Pool reuse support
  BOOL _preservesNodeBlock;
  void (^_configureBlock)(ASCellNode *);

  // Layout cache — allows skipping re-measurement on pool dequeue when the
  // constrained size has not changed. Both fields are written atomically under _lock.
  CGSize _cachedLayoutSize;
  ASSizeRange _cachedConstrainedSize;
}

- (instancetype)initWithNodeModel:(id)nodeModel
                        nodeBlock:(ASCellNodeBlock)nodeBlock
         supplementaryElementKind:(NSString *)supplementaryElementKind
                  constrainedSize:(ASSizeRange)constrainedSize
                       owningNode:(id<ASRangeManagingNode>)owningNode
                  traitCollection:(ASPrimitiveTraitCollection)traitCollection
{
  NSAssert(nodeBlock != nil, @"Node block must not be nil");
  self = [super init];
  if (self) {
    _nodeModel = nodeModel;
    _nodeBlock = nodeBlock;
    _supplementaryElementKind = [supplementaryElementKind copy];
    _constrainedSize = constrainedSize;
    _owningNode = owningNode;
    _traitCollection = traitCollection;
  }
  return self;
}

- (ASCellNode *)node
{
  ASCellNode *newNode = nil;
  void (^configureCopy)(ASCellNode *) = nil;

  {
    AS::MutexLocker l(_lock);

    // Fast path: return existing node. This check MUST come first.
    // When preservesNodeBlock = YES, _nodeBlock is never nilled, so checking
    // _nodeBlock != nil alone would re-execute the block on every call — wrong.
    if (_node != nil) return _node;

    if (_nodeBlock == nil) return nil;

    ASCellNode *node = _nodeBlock();  // pool dequeue or alloc; runs under lock
    if (!_preservesNodeBlock) {
      _nodeBlock = nil;              // existing path: discard after first use
    }
    if (node == nil) {
      ASDisplayNodeFailAssert(@"Node block returned nil node!");
      node = [[ASCellNode alloc] init];
    }
    node.collectionElement = self;
    ASTraitCollectionPropagateDown(node, _traitCollection);
    node.nodeModel = _nodeModel;
    _node = node;
    newNode = node;
    configureCopy = _configureBlock;
  }

  // configureNode:atIndexPath: called OUTSIDE _lock to avoid lock-inversion.
  // In the pre-allocation path this runs on a background thread.
  // In the edge case where cellForItemAtIndexPath: calls element.node before
  // pre-allocation completes, this runs on the main thread. Implementations
  // must tolerate either thread.
  if (configureCopy) {
    configureCopy(newNode);
  }
  return newNode;
}

- (ASCellNode *)nodeIfAllocated
{
  AS::MutexLocker l(_lock);
  return _node;
}

- (void)setTraitCollection:(ASPrimitiveTraitCollection)traitCollection
{
  ASCellNode *nodeIfNeedsPropagation;

  {
    AS::MutexLocker l(_lock);
    if (! ASPrimitiveTraitCollectionIsEqualToASPrimitiveTraitCollection(_traitCollection, traitCollection)) {
      _traitCollection = traitCollection;
      nodeIfNeedsPropagation = _node;
    }
  }

  if (nodeIfNeedsPropagation != nil) {
    ASTraitCollectionPropagateDown(nodeIfNeedsPropagation, traitCollection);
  }
}

#pragma mark - ASCollectionElement (Private)

- (BOOL)preservesNodeBlock
{
  AS::MutexLocker l(_lock);
  return _preservesNodeBlock;
}

- (void)setPreservesNodeBlock:(BOOL)preservesNodeBlock
{
  AS::MutexLocker l(_lock);
  _preservesNodeBlock = preservesNodeBlock;
}

- (void (^)(ASCellNode *))configureBlock
{
  AS::MutexLocker l(_lock);
  return _configureBlock;
}

- (void)setConfigureBlock:(void (^)(ASCellNode *))configureBlock
{
  AS::MutexLocker l(_lock);
  _configureBlock = [configureBlock copy];
}

- (void)setCachedLayoutSize:(CGSize)size forConstrainedSize:(ASSizeRange)range
{
  AS::MutexLocker l(_lock);
  _cachedLayoutSize = size;
  _cachedConstrainedSize = range;
}

- (CGSize)cachedLayoutSizeForConstrainedSize:(ASSizeRange)constrainedSize
{
  AS::MutexLocker l(_lock);
  if (CGSizeEqualToSize(_cachedLayoutSize, CGSizeZero)) return CGSizeZero;
  if (!ASSizeRangeEqualToSizeRange(constrainedSize, _cachedConstrainedSize)) return CGSizeZero;
  return _cachedLayoutSize;
}

- (ASCellNode *)_evictNodeCapturingConstrainedSize:(ASSizeRange *)outConstrainedSize
{
  AS::MutexLocker l(_lock);
  if (_node == nil || !_preservesNodeBlock) return nil;
  ASCellNode *node = _node;
  // _constrainedSize is a nonatomic @property mutated without _lock in
  // relayoutNodes: (ASDataController). This read is safe because both that
  // mutation and this eviction run exclusively on the main thread.
  *outConstrainedSize = _constrainedSize;
  _node = nil;
  return node;
}

@end
