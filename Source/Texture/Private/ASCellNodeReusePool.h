//
//  ASCellNodeReusePool.h
//  Texture
//
//  Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#pragma once

#import <Foundation/Foundation.h>
#import "ASBaseDefines.h"

NS_ASSUME_NONNULL_BEGIN

@class ASCellNode;

/**
 * Thread-safe pool of reusable ASCellNode objects, keyed by reuse identifier.
 *
 * Nodes are enqueued when they exit the preload range and dequeued when they
 * re-enter the preload range. Both operations are thread-safe.
 *
 * The pool size per identifier is bounded by maxSizePerIdentifier (default: 10).
 * Nodes that exceed the cap are released immediately.
 */
AS_SUBCLASSING_RESTRICTED
@interface ASCellNodeReusePool : NSObject

/**
 * Maximum number of nodes to keep per reuse identifier. Default: 10.
 * Nodes exceeding this cap on enqueue are released immediately.
 */
@property (nonatomic) NSUInteger maxSizePerIdentifier;

/**
 * Dequeue a node with the given identifier, or return nil if none are available.
 * Thread-safe; may be called from any thread.
 */
- (nullable ASCellNode *)dequeueNodeWithIdentifier:(NSString *)identifier;

/**
 * Enqueue a node with the given identifier.
 * Thread-safe; may be called from any thread.
 */
- (void)enqueueNode:(ASCellNode *)node identifier:(NSString *)identifier;

/**
 * Release all pooled nodes. Must be called on the main thread.
 * Called on memory warning, bounds change, and owning view dealloc.
 */
- (void)drain;

@end

NS_ASSUME_NONNULL_END
