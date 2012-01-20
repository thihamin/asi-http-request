//
//  NSObject+BlockAdditions.h
//  PostmatesUser
//
//  Created by Thiha Min on 1/16/12.
//  Copyright (c) 2012 Postmates. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void (^BasicBlock)(void);

@interface NSObject (BlockAdditions)

void RunAfterDelay(NSTimeInterval delay, BasicBlock block);

- (void)ps_callBlock;

@end
