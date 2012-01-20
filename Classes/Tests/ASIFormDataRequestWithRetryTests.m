//
//  ASIFormDataRequestWithRetryTests.m
//  PostmatesUser
//
//  Created by Thiha Min on 1/13/12.
//  Copyright (c) 2012 Postmates. All rights reserved.
//

#import "ASIFormDataRequestWithRetryTests.h"

#import <UIKit/UIKit.h>
#import <OCMock/OCMock.h>
#import "ASIFormDataRequestWithRetry.h"
#import "NSObject+BlockAdditions.h"

// expose private methods for testing
@interface ASIFormDataRequestWithRetry ()

+ (ASIFormDataRequestWithRetry*) getQueuedRetryRequestWithUuid:(NSString*)uuid;
+ (NSArray*)getRequestsToRetry;
+ (void)setIntitialRetryInterval:(NSTimeInterval)anIntialRetryInterval;

@end


@interface ASIFormDataRequestWithRetryTests ()

- (void) setFailureReturnForRequest:(ASIFormDataRequestWithRetry*)aRequest requestRetryCount:(NSInteger*)requestRetryCount;
- (void) setSuccessReturnForRequest:(ASIFormDataRequestWithRetry*)aRequest requestRetryCount:(NSInteger*)requestRetryCount;

- (ASIFormDataRequestWithRetry*)getFormDataRequestWithRetry;

@end

@implementation ASIFormDataRequestWithRetryTests


- (void)setUp {
    
    NSTimeInterval initialRetryInterval = 4; // set the initial retry interval to 4 sec
    [ASIFormDataRequestWithRetry setIntitialRetryInterval:initialRetryInterval];
    
}

// set failure return for startAsynchronous
- (void) setFailureReturnForRequest:(ASIFormDataRequestWithRetry*)aRequest requestRetryCount:(NSInteger*)requestRetryCount{
    // mock startAsynchronousWithRetry
    id mock = [OCMockObject partialMockForObject:aRequest];     // note: we need to mock the instance object (not class object)
    // in order to replace 'startAsynchronous' method with the stub block
    
    // mock error to requestWithRetry
    [[[mock stub] andDo:^(NSInvocation *invocation) {
        
        RunAfterDelay(0.1, ^{
            //NSLog(@"ASIFormDataRequestWithRetryTests: stub Do failure method called: isMainThread:%@", [NSThread isMainThread] ? @"YES" : @"NO");
            NSLog(@"ASIFormDataRequestWithRetryTests: stub Do failure method called. requestUuid=%@", aRequest.requestUuid);
            
            // set as timeout error
            NSError *ASIRequestTimedOutError = [[NSError alloc] initWithDomain:NetworkRequestErrorDomain code:ASIRequestTimedOutErrorType userInfo:[NSDictionary dictionaryWithObjectsAndKeys:@"The request timed out",NSLocalizedDescriptionKey,nil]];
            
            aRequest.error = ASIRequestTimedOutError;
            
            if(aRequest.delegate){    
                [aRequest.delegate requestFailed:aRequest];
            }
            
            (*requestRetryCount) += 1;
            
            
        });
        
    }] startAsynchronous];
}

// set success return for startAsynchronous
- (void) setSuccessReturnForRequest:(ASIFormDataRequestWithRetry*)aRequest requestRetryCount:(NSInteger*)requestRetryCount{
    id mock2 = [OCMockObject partialMockForObject:aRequest];
    
    [[[mock2 stub] andDo:^(NSInvocation *invocation) {
        
        RunAfterDelay(0.1, ^{
            //NSLog(@"ASIFormDataRequestWithRetryTests: stub Do success method called isMainThread:%@", [NSThread isMainThread] ? @"YES" : @"NO");
            
            NSLog(@"ASIFormDataRequestWithRetryTests: stub Do success method called. requestUuid=%@", [aRequest requestUuid]);
            
            //requestWithRetry2.responseStatusCode = PMKResponseStatusCodeSuccess; // cannot assign it as ASI has responseStatusCode as readonly
            if(aRequest.delegate){    
                [aRequest.delegate requestFinished:aRequest];
            }
            
            (*requestRetryCount) += 1;
            
            
        });
        
    }] startAsynchronous];
    
}

- (ASIFormDataRequestWithRetry*)getFormDataRequestWithRetry {
    
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"www.postmates.com/some_end_point"]];
    
    ASIFormDataRequestWithRetry *requestWithRetry = [ASIFormDataRequestWithRetry requestWithURL:url];
    
    return requestWithRetry;
}


//  Test whether the request is rescheduled after one failure
//  Steps:
//  mock startAsynchronous and return error
//  call startAsynchronous
//
//  mock startAsynchronous and return success
//  next startAsynchronous call will be made by the timer
// 
//  check whether there are anything to retry
- (void)testRequestWithOneRetry {
    
    __block NSInteger requestRetryCount = 0;
    
    ASIFormDataRequestWithRetry *requestWithRetry = [self getFormDataRequestWithRetry];
    
    // mock failure return
    [self setFailureReturnForRequest:requestWithRetry requestRetryCount:&requestRetryCount];
    
    [requestWithRetry startAsynchronousWithRetry];
    
    
    NSRunLoop *currentRunLoop = [NSRunLoop currentRunLoop];
    while ((requestRetryCount < 1) && [currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]]);
    
    NSLog(@"requestRetryCount=%d", requestRetryCount);
    
    // get the retry request object from the queue
    // and mock success
    ASIFormDataRequestWithRetry *requestWithRetry2 = [[ASIFormDataRequestWithRetry class] getQueuedRetryRequestWithUuid:requestWithRetry.requestUuid];
    
    GHAssertNotNil(requestWithRetry2, @"requestWithRetry2 should not be nil");
    
    [self setSuccessReturnForRequest:requestWithRetry2 requestRetryCount:&requestRetryCount];
    
    NSDate *loopUntil = [NSDate dateWithTimeIntervalSinceNow:1];
    while ((requestRetryCount < 2) && [currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:loopUntil]){
        loopUntil = [NSDate dateWithTimeIntervalSinceNow:1];
    }
    
    NSLog(@"requestRetryCount=%d", requestRetryCount);
    NSArray *requestsToRetry = [ASIFormDataRequestWithRetry getRequestsToRetry];
    
    GHAssertTrue((requestsToRetry == nil || [requestsToRetry count] == 0) , @"requestsToRetry's count must be zero when we reach to this point");
    
}


// Test two requests at the same time
// first request succeeds after one retry
// second request succeeds after two retries
- (void) testTwoRequestsWithRetry {
    
    // create 2 requests
    ASIFormDataRequestWithRetry *requestWithRetry1 = [self getFormDataRequestWithRetry];
    ASIFormDataRequestWithRetry *requestWithRetry2 = [self getFormDataRequestWithRetry];
    
    NSInteger request1RetryCount = 0;
    NSInteger request2RetryCount = 0;
    
    // stub both requests with failure
    [self setFailureReturnForRequest:requestWithRetry1 requestRetryCount:&request1RetryCount];
    [self setFailureReturnForRequest:requestWithRetry2 requestRetryCount:&request2RetryCount];
    
    // starts the requests
    [requestWithRetry1 startAsynchronousWithRetry];
    [requestWithRetry2 startAsynchronousWithRetry];
    
    // wait until both requests fail
    NSRunLoop *currentRunLoop = [NSRunLoop currentRunLoop];
    NSDate *loopUntil = [NSDate dateWithTimeIntervalSinceNow:1];
    //[currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.0]];
    while ((request1RetryCount < 1 || request2RetryCount < 1) && [currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:loopUntil]){
        loopUntil = [NSDate dateWithTimeIntervalSinceNow:1];
    }
    
    NSLog(@"testTwoRequests -- step 2");
    GHAssertTrue([[ASIFormDataRequestWithRetry getRequestsToRetry] count] == 2, @"should have two requests queued to retry");
    
    // stub request1 with success
    // stub request2 with failure
    requestWithRetry1 = [[ASIFormDataRequestWithRetry class] getQueuedRetryRequestWithUuid:requestWithRetry1.requestUuid];
    requestWithRetry2 = [[ASIFormDataRequestWithRetry class] getQueuedRetryRequestWithUuid:requestWithRetry2.requestUuid];
    GHAssertNotNil(requestWithRetry1, @"requestWithRetry1 should be in the queue");
    GHAssertNotNil(requestWithRetry2, @"requestWithRetry2 should be in the queue");
    [self setSuccessReturnForRequest:requestWithRetry1 requestRetryCount:&request1RetryCount];
    [self setFailureReturnForRequest:requestWithRetry2 requestRetryCount:&request2RetryCount];
    
    // wait until retry count reach to 2 for both requests
    loopUntil = [NSDate dateWithTimeIntervalSinceNow:1];
    while ((request1RetryCount < 2 || request2RetryCount < 2) && [currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:loopUntil]){
        //NSLog(@"request1RetryCount=%d request2RetryCount=%d", request1RetryCount, request2RetryCount);
        loopUntil = [NSDate dateWithTimeIntervalSinceNow:1];
    } 
    
    NSLog(@"testTwoRequests -- step 3");
    GHAssertTrue([[ASIFormDataRequestWithRetry getRequestsToRetry] count] == 1, @"should have one request queued to retry");
    
    // stub request2 with success
    requestWithRetry2 = [[ASIFormDataRequestWithRetry class] getQueuedRetryRequestWithUuid:requestWithRetry2.requestUuid];
    GHAssertNotNil(requestWithRetry2, @"requestWithRetry2 should be in the queue");
    [self setSuccessReturnForRequest:requestWithRetry2 requestRetryCount:&request2RetryCount];
    
    // wait until retry count reach to 3 on request2
    loopUntil = [NSDate dateWithTimeIntervalSinceNow:1];
    while (request2RetryCount < 3 && [currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:loopUntil]){
        //NSLog(@"request2RetryCount=%d", request2RetryCount);
        loopUntil = [NSDate dateWithTimeIntervalSinceNow:1];
    } 
    
    GHAssertTrue((([ASIFormDataRequestWithRetry getRequestsToRetry] == nil) || ([[ASIFormDataRequestWithRetry getRequestsToRetry] count] == 0)), 
                 @"should have two requests queued to retry");
    
}

//TODO: Test whether the timer restarts when internet is reachable and there are requests to retry

@end
