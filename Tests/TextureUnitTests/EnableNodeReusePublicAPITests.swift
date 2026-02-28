//
//  EnableNodeReusePublicAPITests.swift
//  TextureUnitTests
//
//  Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

import Testing
@testable import AsyncDisplayKit

@Suite("enableNodeReuse public API")
@MainActor
struct EnableNodeReusePublicAPITests {

  // MARK: - ASCollectionNode

  @Test("ASCollectionNode.enableNodeReuse defaults to NO")
  func collectionNodeDefaultFalse() {
    let node = ASCollectionNode(collectionViewLayout: UICollectionViewFlowLayout())
    #expect(node.enableNodeReuse == false)
  }

  @Test("ASCollectionNode.enableNodeReuse can be set to YES before view loads")
  func collectionNodeSetBeforeViewLoad() {
    let node = ASCollectionNode(collectionViewLayout: UICollectionViewFlowLayout())
    node.enableNodeReuse = true
    #expect(node.enableNodeReuse == true)
  }

  @Test("ASCollectionNode.enableNodeReuse can be set to YES after view loads")
  func collectionNodeSetAfterViewLoad() {
    let node = ASCollectionNode(collectionViewLayout: UICollectionViewFlowLayout())
    _ = node.view  // trigger view load
    node.enableNodeReuse = true
    #expect(node.enableNodeReuse == true)
  }

  @Test("ASCollectionNode.enableNodeReuse round-trips false → true → false")
  func collectionNodeToggle() {
    let node = ASCollectionNode(collectionViewLayout: UICollectionViewFlowLayout())
    node.enableNodeReuse = true
    node.enableNodeReuse = false
    #expect(node.enableNodeReuse == false)
  }

  // MARK: - ASTableNode

  @Test("ASTableNode.enableNodeReuse defaults to NO")
  func tableNodeDefaultFalse() {
    let node = ASTableNode(style: .plain)
    #expect(node.enableNodeReuse == false)
  }

  @Test("ASTableNode.enableNodeReuse can be set to YES before view loads")
  func tableNodeSetBeforeViewLoad() {
    let node = ASTableNode(style: .plain)
    node.enableNodeReuse = true
    #expect(node.enableNodeReuse == true)
  }

  @Test("ASTableNode.enableNodeReuse can be set to YES after view loads")
  func tableNodeSetAfterViewLoad() {
    let node = ASTableNode(style: .plain)
    _ = node.view  // trigger view load
    node.enableNodeReuse = true
    #expect(node.enableNodeReuse == true)
  }

  @Test("ASTableNode.enableNodeReuse round-trips false → true → false")
  func tableNodeToggle() {
    let node = ASTableNode(style: .plain)
    node.enableNodeReuse = true
    node.enableNodeReuse = false
    #expect(node.enableNodeReuse == false)
  }
}
