//
//  ASCollectionElementPoolTests.swift
//  TextureUnitTests
//
//  Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

import Testing
@testable import AsyncDisplayKit

// MARK: - Helpers

// ASCollectionNode conforms to ASRangeManagingNode and is the canonical owner.
private func makeOwningNode() -> ASCollectionNode {
  ASCollectionNode(collectionViewLayout: UICollectionViewFlowLayout())
}

private func makeElement(
  owningNode: ASCollectionNode? = nil,
  nodeBlock: @escaping ASCellNodeBlock = { ASCellNode() },
  constrainedSize: ASSizeRange = ASSizeRangeMake(
    CGSize(width: 100, height: 44),
    CGSize(width: 100, height: 44)
  )
) -> ASCollectionElement {
  let owner = owningNode ?? makeOwningNode()
  return ASCollectionElement(
    nodeModel: nil,
    nodeBlock: nodeBlock,
    supplementaryElementKind: nil,
    constrainedSize: constrainedSize,
    owning: owner,
    traitCollection: ASPrimitiveTraitCollectionMakeDefault()
  )
}

// MARK: - Suite

@Suite("ASCollectionElement (Private) pool extensions")
@MainActor
struct ASCollectionElementPoolTests {

  // MARK: - preservesNodeBlock

  @Test("preservesNodeBlock defaults to NO")
  func preservesNodeBlockDefaultFalse() {
    let element = makeElement()
    #expect(element.preservesNodeBlock == false)
  }

  @Test("preservesNodeBlock can be set to YES")
  func setPreservesNodeBlock() {
    let element = makeElement()
    element.preservesNodeBlock = true
    #expect(element.preservesNodeBlock == true)
  }

  @Test("preservesNodeBlock=NO nils the nodeBlock after first -node access")
  func nodeBlockNilledAfterFirstAccess() {
    var blockCallCount = 0
    let element = makeElement(nodeBlock: {
      blockCallCount += 1
      return ASCellNode()
    })
    element.preservesNodeBlock = false
    _ = element.node  // first call: executes block
    blockCallCount = 0
    // Subsequent calls hit fast path (cached _node) without re-executing block
    let node1 = element.node
    let node2 = element.node
    #expect(node1 === node2)          // same cached object
    #expect(blockCallCount == 0)      // block was NOT called again
  }

  @Test("preservesNodeBlock=YES keeps nodeBlock after first -node access")
  func nodeBlockPreservedWhenFlagSet() {
    // Verify by evicting the node and re-accessing: a new node should be vended.
    var blockCallCount = 0
    let element = makeElement(nodeBlock: {
      blockCallCount += 1
      return ASCellNode()
    })
    element.preservesNodeBlock = true
    let first = element.node          // block called once
    #expect(blockCallCount == 1)

    // Evict the cached node
    var captured = ASSizeRange()
    let evicted = element._evictNodeCapturingConstrainedSize(&captured)
    #expect(evicted === first)

    // Re-access: block should be called again (nodeBlock was preserved)
    let second = element.node
    #expect(blockCallCount == 2)
    #expect(second !== first)         // brand-new node
  }

  // MARK: - configureBlock

  @Test("configureBlock defaults to nil")
  func configureBlockDefaultNil() {
    let element = makeElement()
    #expect(element.configureBlock == nil)
  }

  @Test("configureBlock can be set")
  func setConfigureBlock() {
    let element = makeElement()
    element.configureBlock = { _ in }
    #expect(element.configureBlock != nil)
  }

  @Test("configureBlock is called on -node when set")
  func configureBlockCalledOnNodeAccess() {
    let element = makeElement()
    var configuredNode: ASCellNode? = nil
    element.configureBlock = { node in configuredNode = node }
    let node = element.node
    #expect(configuredNode === node)
  }

  @Test("configureBlock is not called again on repeated -node access (fast path)")
  func configureBlockNotCalledOnFastPath() {
    let element = makeElement()
    var callCount = 0
    element.configureBlock = { _ in callCount += 1 }
    _ = element.node   // first: executes block + configure
    _ = element.node   // second: fast path, no configure
    #expect(callCount == 1)
  }

  // MARK: - Layout size cache

  @Test("cachedLayoutSizeForConstrainedSize returns CGSizeZero on cache miss")
  func layoutCacheMiss() {
    let element = makeElement()
    let range = ASSizeRangeMake(
      CGSize(width: 100, height: 44),
      CGSize(width: 100, height: 44)
    )
    #expect(element.cachedLayoutSize(forConstrainedSize: range) == .zero)
  }

  @Test("cachedLayoutSizeForConstrainedSize returns stored size on cache hit")
  func layoutCacheHit() {
    let element = makeElement()
    let range = ASSizeRangeMake(
      CGSize(width: 100, height: 44),
      CGSize(width: 100, height: 44)
    )
    let size = CGSize(width: 100, height: 44)
    element.setCachedLayoutSize(size, forConstrainedSize: range)
    #expect(element.cachedLayoutSize(forConstrainedSize: range) == size)
  }

  @Test("cachedLayoutSizeForConstrainedSize returns CGSizeZero for different range")
  func layoutCacheRangeMismatch() {
    let element = makeElement()
    let rangeA = ASSizeRangeMake(
      CGSize(width: 100, height: 44),
      CGSize(width: 100, height: 44)
    )
    let rangeB = ASSizeRangeMake(
      CGSize(width: 200, height: 44),
      CGSize(width: 200, height: 44)
    )
    element.setCachedLayoutSize(CGSize(width: 100, height: 44), forConstrainedSize: rangeA)
    #expect(element.cachedLayoutSize(forConstrainedSize: rangeB) == .zero)
  }

  @Test("setCachedLayoutSize overwrites a previous entry")
  func layoutCacheOverwrite() {
    let element = makeElement()
    let range = ASSizeRangeMake(
      CGSize(width: 100, height: 44),
      CGSize(width: 100, height: 44)
    )
    element.setCachedLayoutSize(CGSize(width: 100, height: 44), forConstrainedSize: range)
    let newSize = CGSize(width: 100, height: 88)
    element.setCachedLayoutSize(newSize, forConstrainedSize: range)
    #expect(element.cachedLayoutSize(forConstrainedSize: range) == newSize)
  }

  // MARK: - _evictNodeCapturingConstrainedSize

  @Test("_evictNode returns nil when no node has been allocated")
  func evictNilWhenNoNode() {
    let element = makeElement()
    element.preservesNodeBlock = true
    var captured = ASSizeRange()
    #expect(element._evictNodeCapturingConstrainedSize(&captured) == nil)
  }

  @Test("_evictNode returns nil when preservesNodeBlock is NO")
  func evictNilWhenPreservesFlagFalse() {
    let element = makeElement()
    element.preservesNodeBlock = false
    _ = element.node  // allocate a node
    var captured = ASSizeRange()
    #expect(element._evictNodeCapturingConstrainedSize(&captured) == nil)
  }

  @Test("_evictNode returns the allocated node and clears nodeIfAllocated")
  func evictReturnsNodeAndClearsIt() {
    let element = makeElement()
    element.preservesNodeBlock = true
    let allocatedNode = element.node  // trigger allocation
    var captured = ASSizeRange()
    let evicted = element._evictNodeCapturingConstrainedSize(&captured)
    #expect(evicted === allocatedNode)
    #expect(element.nodeIfAllocated == nil)
  }

  @Test("_evictNode captures the element's constrainedSize")
  func evictCapturesConstrainedSize() {
    let range = ASSizeRangeMake(
      CGSize(width: 320, height: 60),
      CGSize(width: 320, height: 60)
    )
    let element = makeElement(constrainedSize: range)
    element.preservesNodeBlock = true
    _ = element.node
    var captured = ASSizeRange()
    _ = element._evictNodeCapturingConstrainedSize(&captured)
    #expect(ASSizeRangeEqualToSizeRange(captured, range))
  }

  @Test("calling _evictNode twice returns nil on second call")
  func evictTwiceSecondIsNil() {
    let element = makeElement()
    element.preservesNodeBlock = true
    _ = element.node
    var captured = ASSizeRange()
    _ = element._evictNodeCapturingConstrainedSize(&captured)
    #expect(element._evictNodeCapturingConstrainedSize(&captured) == nil)
  }
}
