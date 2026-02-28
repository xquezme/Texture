//
//  ASCellNodeReusePoolTests.swift
//  TextureUnitTests
//
//  Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

import Testing
@testable import AsyncDisplayKit

@Suite("ASCellNodeReusePool")
struct ASCellNodeReusePoolTests {

  // MARK: - Init

  @Test("default maxSizePerIdentifier is 10")
  func defaultMaxSize() {
    let pool = ASCellNodeReusePool()
    #expect(pool.maxSizePerIdentifier == 10)
  }

  // MARK: - Dequeue

  @Test("dequeue on empty pool returns nil")
  func dequeueEmptyReturnsNil() {
    let pool = ASCellNodeReusePool()
    #expect(pool.dequeueNode(withIdentifier: "cell") == nil)
  }

  @Test("dequeue with unknown identifier returns nil")
  func dequeueUnknownIdentifier() {
    let pool = ASCellNodeReusePool()
    let node = ASCellNode()
    pool.enqueue(node, identifier: "a")
    #expect(pool.dequeueNode(withIdentifier: "b") == nil)
  }

  // MARK: - Enqueue / Dequeue round-trip

  @Test("enqueue then dequeue returns the same node")
  func enqueueDequeueRoundTrip() {
    let pool = ASCellNodeReusePool()
    let node = ASCellNode()
    pool.enqueue(node, identifier: "cell")
    #expect(pool.dequeueNode(withIdentifier: "cell") === node)
  }

  @Test("dequeue after single enqueue leaves pool empty")
  func dequeueExhaustsPool() {
    let pool = ASCellNodeReusePool()
    let node = ASCellNode()
    pool.enqueue(node, identifier: "cell")
    _ = pool.dequeueNode(withIdentifier: "cell")
    #expect(pool.dequeueNode(withIdentifier: "cell") == nil)
  }

  @Test("LIFO: last enqueued node is dequeued first")
  func lifoOrder() {
    let pool = ASCellNodeReusePool()
    let first = ASCellNode()
    let second = ASCellNode()
    pool.enqueue(first, identifier: "cell")
    pool.enqueue(second, identifier: "cell")
    // LIFO → second should come out first
    let dequeued = pool.dequeueNode(withIdentifier: "cell")
    #expect(dequeued === second)
    // first should be next
    let next = pool.dequeueNode(withIdentifier: "cell")
    #expect(next === first)
  }

  // MARK: - Identifier isolation

  @Test("nodes for different identifiers do not cross-contaminate")
  func identifierIsolation() {
    let pool = ASCellNodeReusePool()
    let nodeA = ASCellNode()
    let nodeB = ASCellNode()
    pool.enqueue(nodeA, identifier: "a")
    pool.enqueue(nodeB, identifier: "b")
    #expect(pool.dequeueNode(withIdentifier: "a") === nodeA)
    #expect(pool.dequeueNode(withIdentifier: "b") === nodeB)
  }

  // MARK: - Cap enforcement

  @Test("nodes exceeding maxSizePerIdentifier are dropped on enqueue")
  func capEnforcement() {
    let pool = ASCellNodeReusePool()
    pool.maxSizePerIdentifier = 2
    let n1 = ASCellNode()
    let n2 = ASCellNode()
    let n3 = ASCellNode()  // This one should be dropped
    pool.enqueue(n1, identifier: "cell")
    pool.enqueue(n2, identifier: "cell")
    pool.enqueue(n3, identifier: "cell")  // cap == 2, dropped
    // LIFO: n2 first, then n1
    #expect(pool.dequeueNode(withIdentifier: "cell") === n2)
    #expect(pool.dequeueNode(withIdentifier: "cell") === n1)
    #expect(pool.dequeueNode(withIdentifier: "cell") == nil)  // n3 was dropped
  }

  @Test("maxSizePerIdentifier of 0 drops every node")
  func capZeroDropsAll() {
    let pool = ASCellNodeReusePool()
    pool.maxSizePerIdentifier = 0
    pool.enqueue(ASCellNode(), identifier: "cell")
    #expect(pool.dequeueNode(withIdentifier: "cell") == nil)
  }

  @Test("setting maxSizePerIdentifier to 1 allows exactly one node")
  func capOne() {
    let pool = ASCellNodeReusePool()
    pool.maxSizePerIdentifier = 1
    let kept = ASCellNode()
    let dropped = ASCellNode()
    pool.enqueue(kept, identifier: "cell")
    pool.enqueue(dropped, identifier: "cell")
    #expect(pool.dequeueNode(withIdentifier: "cell") === kept)
    #expect(pool.dequeueNode(withIdentifier: "cell") == nil)
  }

  // MARK: - Drain

  @Test("drain empties all nodes from all identifiers")
  func drainEmptiesPool() {
    let pool = ASCellNodeReusePool()
    pool.enqueue(ASCellNode(), identifier: "a")
    pool.enqueue(ASCellNode(), identifier: "b")
    pool.drain()
    #expect(pool.dequeueNode(withIdentifier: "a") == nil)
    #expect(pool.dequeueNode(withIdentifier: "b") == nil)
  }

  @Test("drain on already-empty pool does not crash")
  func drainEmpty() {
    let pool = ASCellNodeReusePool()
    pool.drain()  // must not crash
  }

  @Test("enqueue after drain works normally")
  func enqueueAfterDrain() {
    let pool = ASCellNodeReusePool()
    pool.enqueue(ASCellNode(), identifier: "cell")
    pool.drain()
    let fresh = ASCellNode()
    pool.enqueue(fresh, identifier: "cell")
    #expect(pool.dequeueNode(withIdentifier: "cell") === fresh)
  }

  // MARK: - Memory warning

  @Test("memory warning notification drains the pool")
  func memoryWarningDrainsPool() {
    let pool = ASCellNodeReusePool()
    pool.enqueue(ASCellNode(), identifier: "cell")
    NotificationCenter.default.post(
      name: UIApplication.didReceiveMemoryWarningNotification,
      object: nil
    )
    #expect(pool.dequeueNode(withIdentifier: "cell") == nil)
  }

  // MARK: - Concurrency

  @Test("concurrent enqueue/dequeue does not crash or corrupt state")
  func concurrentAccess() async {
    let pool = ASCellNodeReusePool()
    pool.maxSizePerIdentifier = 50
    let identifier = "concurrent"

    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<50 {
        group.addTask {
          pool.enqueue(ASCellNode(), identifier: identifier)
        }
        group.addTask {
          _ = pool.dequeueNode(withIdentifier: identifier)
        }
      }
    }
    // If we got here without crashing, the test passes.
    // Additionally verify pool is in a valid state.
    pool.drain()
    #expect(pool.dequeueNode(withIdentifier: identifier) == nil)
  }
}
