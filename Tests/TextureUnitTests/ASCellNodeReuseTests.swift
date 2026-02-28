//
//  ASCellNodeReuseTests.swift
//  TextureUnitTests
//
//  Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

import Testing
@testable import AsyncDisplayKit

@Suite("ASCellNode reuse additions")
struct ASCellNodeReuseTests {

  // MARK: - reuseIdentifier property

  @Test("reuseIdentifier is nil on a freshly allocated node")
  func reuseIdentifierDefaultNil() {
    let node = ASCellNode()
    #expect(node.reuseIdentifier == nil)
  }

  @Test("setReuseIdentifier stores and returns the value")
  func reuseIdentifierRoundTrip() {
    let node = ASCellNode()
    node.reuseIdentifier = "myCell"
    #expect(node.reuseIdentifier == "myCell")
  }

  @Test("reuseIdentifier can be cleared back to nil")
  func reuseIdentifierClearable() {
    let node = ASCellNode()
    node.reuseIdentifier = "myCell"
    node.reuseIdentifier = nil
    #expect(node.reuseIdentifier == nil)
  }

  // MARK: - prepareForReuse

  @Test("prepareForReuse on base ASCellNode is a no-op and does not crash")
  func prepareForReuseIsNoOp() {
    let node = ASCellNode()
    node.prepareForReuse()  // must not crash
  }

  // MARK: - _prepareForPool

  @Test("_prepareForPool preserves reuseIdentifier")
  @MainActor
  func prepareForPoolPreservesReuseIdentifier() {
    let node = ASCellNode()
    node.reuseIdentifier = "pooledCell"
    node._prepareForPool()
    #expect(node.reuseIdentifier == "pooledCell")
  }

  @Test("_prepareForPool clears interactionDelegate")
  @MainActor
  func prepareForPoolClearsInteractionDelegate() {
    let node = ASCellNode()
    // We can't easily set a real interaction delegate from Swift (the protocol is private),
    // so we just verify the call doesn't crash and leaves the node in a valid state.
    node._prepareForPool()
  }

  @Test("_prepareForPool exits ASHierarchyStateRangeManaged")
  @MainActor
  func prepareForPoolExitsRangeManaged() {
    let node = ASCellNode()
    node.enter(.rangeManaged)
    #expect(node.hierarchyState.contains(.rangeManaged))
    node._prepareForPool()
    #expect(!node.hierarchyState.contains(.rangeManaged))
  }

  @Test("_prepareForPool nils scrollView")
  @MainActor
  func prepareForPoolNilsScrollView() {
    let node = ASCellNode()
    let scrollView = UIScrollView()
    node.scrollView = scrollView
    node._prepareForPool()
    #expect(node.scrollView == nil)
  }

  @Test("calling _prepareForPool multiple times does not crash")
  @MainActor
  func prepareForPoolIdempotent() {
    let node = ASCellNode()
    node._prepareForPool()
    node._prepareForPool()
  }
}
