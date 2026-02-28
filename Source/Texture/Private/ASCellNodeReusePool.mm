//
//  ASCellNodeReusePool.mm
//  Texture
//
//  Copyright (c) Pinterest, Inc.  All rights reserved.
//  Licensed under Apache 2.0: http://www.apache.org/licenses/LICENSE-2.0
//

#import "ASCellNodeReusePool.h"
#import "ASCellNode.h"
#import "ASThread.h"

@implementation ASCellNodeReusePool {
  AS::Mutex _mutex;
  NSMutableDictionary<NSString *, NSMutableArray<ASCellNode *> *> *_pool;
}

- (instancetype)init
{
  self = [super init];
  if (self) {
    _pool = [NSMutableDictionary dictionary];
    _maxSizePerIdentifier = 10;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(drain)
                                                 name:UIApplicationDidReceiveMemoryWarningNotification
                                               object:nil];
  }
  return self;
}

- (void)dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (nullable ASCellNode *)dequeueNodeWithIdentifier:(NSString *)identifier
{
  AS::MutexLocker l(_mutex);
  NSMutableArray<ASCellNode *> *nodes = _pool[identifier];
  if (nodes.count == 0) return nil;
  ASCellNode *node = nodes.lastObject;
  [nodes removeLastObject];
  return node;
}

- (void)enqueueNode:(ASCellNode *)node identifier:(NSString *)identifier
{
  AS::MutexLocker l(_mutex);
  NSMutableArray<ASCellNode *> *nodes = _pool[identifier];
  if (nodes == nil) {
    nodes = [NSMutableArray array];
    _pool[identifier] = nodes;
  }
  if (nodes.count < _maxSizePerIdentifier) {
    [nodes addObject:node];
  }
  // Nodes exceeding the cap fall out of scope here and are released.
}

- (void)drain
{
  AS::MutexLocker l(_mutex);
  [_pool removeAllObjects];
}

@end
