//
//  NSObject+BlockAdditions.m
//  PostmatesUser
//
//  Created by Thiha Min on 1/16/12.
//  Copyright (c) 2012 Postmates. All rights reserved.
//

#import "NSObject+BlockAdditions.h"

// methods are from
// http://petersteinberger.com/2010/10/how-to-mock-asihttprequest-with-ocmock-and-blocks/
// this is to simulate asynchronous request

void RunAfterDelay(NSTimeInterval delay, BasicBlock block) {
    [[[block copy] autorelease] performSelector:@selector(ps_callBlock) withObject:nil afterDelay:delay];
}

@implementation NSObject (BlockAdditions)

- (void)ps_callBlock {
    void (^block)(void) = (id)self;
    block();
}

@end
