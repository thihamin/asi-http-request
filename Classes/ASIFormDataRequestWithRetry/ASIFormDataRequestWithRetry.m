//
//  ASIHTTPRequestWithRetry.m
//  PostmatesCourier
//
//  Created by Thiha Min on 1/11/12.
//  Copyright (c) 2012 Postmates. All rights reserved.
//

#import "ASIFormDataRequestWithRetry.h"
#import "Reachability.h"

@interface ASIFormDataRequestWithRetry ()

@property (nonatomic, retain) NSDate *nextRetryDate;
@property (nonatomic) NSInteger delayedRetryCount;

- (void) scheduleRetryForRequest:(ASIHTTPRequest*)aRequest;
+ (ASIFormDataRequestWithRetry*) removeRequestWithUuid:(NSString*)uuid fromRequests:(NSMutableArray*)requests;
+ (ASIFormDataRequestWithRetry*) getRequestWithUuid:(NSString*)uuid fromRequests:(NSMutableArray*)requests;

+ (void) startTimer;
+ (void) stopTimer;
+ (void) timerFired:(NSTimer*)theTimer;

- (NSDate*) nextDateForDelayRetryCount:(NSInteger)aDelayRetryCount;

#pragma mark - methods to be used in test class
//these methods are for the test class to use
+ (ASIFormDataRequestWithRetry*) getQueuedRetryRequestWithUuid:(NSString*)uuid;
+ (NSArray*)getRequestsToRetry;
+ (void)setIntitialRetryInterval:(NSTimeInterval)anIntialRetryInterval;

#pragma mark -

+ (void) startReachbility;
+ (void) reachabilityChanged: (NSNotification* )note;

+ (NSString *)generateUuidString;

//+ (void)logFailureOfRequest:(ASIHTTPRequest*)aRequest;
//+ (void)logMaxFailureOfRequest:(ASIFormDataRequestWithRetry*)aRequest;



@end

@implementation ASIFormDataRequestWithRetry 

@synthesize nextRetryDate = _nextRetryDate;
@synthesize delayedRetryCount = _delayedRetryCount;
@synthesize requestUuid = _requestUuid;

static NSMutableArray *s_requestsToRetry;     // requests that should be retried in a future date
static NSMutableArray *s_executingRequests;   // copies of the requests that are currently executing (in ASIHTTPRequest's queue)
                                            // we are keeping copies here as ASIHTTPRequest is NSOperation, which can only be run one time
static NSInteger s_delayRetryMax = 12;  // maximum number of times to retry before giving up //FIXME: to increase this max value
static NSTimeInterval s_initialRetryInterval = 10; // this time will get double for each re-schedule
static NSTimer *s_retryTimer;                      // timer to check which requests are due to retry

// stop the timer if not reachable
// re-start the timer if reachable and there are requests to retry
static Reachability *s_reachability;   

static BOOL kVerboseLogging = NO;



#pragma mark -

- (void) startAsynchronousWithRetry {
    
    
    if ( ! self.requestUuid || [self.requestUuid isEqualToString:@""]) {
        self.requestUuid = [[self class] generateUuidString];        
    }
    
    //NSLog(@"startAsynchronousWithRetry: requestUuid=%@, object=%p", self.requestUuid, self);

    self.shouldContinueWhenAppEntersBackground = YES;  // finish the call when app goes to background
    
    self.numberOfTimesToRetryOnTimeout = 1;     // try one more time when request timeout
    
    self.delegate = self;
    
    
    if ( ! s_executingRequests) {
        s_executingRequests = [[NSMutableArray alloc] initWithCapacity:1];
    }
    
    // add a copy to excecutingRequests so that we can re-use later
    [s_executingRequests addObject:[[self copy] autorelease]];
    
    
    [self startAsynchronous]; // this will add the request to NSOperationQueue of ASIHTTPRequest

}


- (void)requestFinished:(ASIHTTPRequest *)aRequest
{

//    // Use when fetching text data
//    NSString *responseString = [aRequest responseString];
//    
//    // Use when fetching binary data
//    NSData *responseData = [aRequest responseData];

#ifdef DEBUG
    NSAssert([aRequest isKindOfClass:[ASIFormDataRequestWithRetry class]], @"request should be ASIFormDataRequestWithRetry");
#endif
    
    if ([aRequest isKindOfClass:[ASIFormDataRequestWithRetry class]]) {
        // remove the request from currently executing list
        ASIFormDataRequestWithRetry *finishedRequest = (ASIFormDataRequestWithRetry*)aRequest;
        if(kVerboseLogging) NSLog(@"ASIHTTPRequestWithRetry: requestFinished: requestUuid=%@", finishedRequest.requestUuid);
        
        ASIFormDataRequestWithRetry *storedRequest = [[self class] removeRequestWithUuid:finishedRequest.requestUuid fromRequests:s_executingRequests];
        
        //  retry for 500 and above error
        NSInteger internalServerErrorCode = 500;
        if(finishedRequest.responseStatusCode >= internalServerErrorCode){ // note: checking status code of finishedRequest
            
            [self scheduleRetryForRequest:storedRequest]; // note: using storedRequest; not finishedRequest
            
        }else{
            
            // stop timer if there is no request to retry
            if (nil == s_requestsToRetry || 0 == [s_requestsToRetry count]) {
                [[self class] stopTimer];
            }            
        }
        
        // log error
        if (finishedRequest.responseStatusCode != 200) {
            NSLog(@"finishedRequest url=%@", finishedRequest.url);
            NSLog(@"responseString=%@", finishedRequest.responseString);
            
            //[[self class] logFailureOfRequest:finishedRequest];
        }

    }

}

- (void)requestFailed:(ASIHTTPRequest *)aRequest {
//    NSError *error = [aRequest error];
    
    if ([aRequest isKindOfClass:[ASIFormDataRequestWithRetry class]]) {

        ASIFormDataRequestWithRetry *finishedRequest = (ASIFormDataRequestWithRetry*)aRequest;
        
        if(kVerboseLogging) NSLog(@"ASIHTTPRequestWithRetry: requestFailed: requestUuid=%@ error=%@", finishedRequest.requestUuid, finishedRequest.error);

        // remove the request copy from currently executing list and retry
        ASIFormDataRequestWithRetry *storedRequest = [[self class] removeRequestWithUuid:finishedRequest.requestUuid fromRequests:s_executingRequests];
        [self scheduleRetryForRequest:storedRequest]; // note: using storedRequest; not finishedRequest
    }
    
    //[[self class] logFailureOfRequest:aRequest];
    
}

- (void) scheduleRetryForRequest:(ASIFormDataRequestWithRetry*)retryRequest {
            
    // if maxinum number to retry has reached; log and return
    if (retryRequest.delayedRetryCount >= s_delayRetryMax) {
        
        NSLog(@"max retry count has been reached. url:%@", retryRequest.url);
        //[[self class] logMaxFailureOfRequest:retryRequest];
        
        return;
    }
    
    if ( ! s_requestsToRetry) {
        s_requestsToRetry = [[NSMutableArray alloc] initWithCapacity:1];
    }
    
    // note: we are using retryRequest (which is a initial copy of self) to populate its ivars
    retryRequest.delayedRetryCount += 1;
    retryRequest.nextRetryDate = [self nextDateForDelayRetryCount:retryRequest.delayedRetryCount];
    
    
    if (retryRequest) {
        [s_requestsToRetry addObject:retryRequest];            
    }else{
#ifdef DEBUG
        NSAssert(FALSE, @"retryRequest should not be nil");
#endif
        
    }
    
    
    [[self class] startTimer];
    
    [[self class] startReachbility];
    
}


+ (ASIFormDataRequestWithRetry*) removeRequestWithUuid:(NSString*)uuid fromRequests:(NSMutableArray*)requests{
    
    ASIFormDataRequestWithRetry *foundRequest = [[self class] getRequestWithUuid:uuid fromRequests:requests];
    
    [[foundRequest retain] autorelease];
    
    if (foundRequest) {
        [requests removeObject:foundRequest];
    }
    
    return foundRequest;
}

+ (ASIFormDataRequestWithRetry*) getRequestWithUuid:(NSString*)uuid fromRequests:(NSMutableArray*)requests{
    //NSLog(@"getRequestWithUuid=%@", uuid);
    
    ASIFormDataRequestWithRetry *foundRequest = nil;
    for (ASIFormDataRequestWithRetry *aRequest in requests){
        //NSLog(@"  aRequest.requestUuid=%@ object=%p", aRequest.requestUuid, aRequest);
        if ([aRequest.requestUuid isEqualToString:uuid]) {
            
#ifdef DEBUG
            NSAssert(nil == foundRequest, @"should not have more than one ASIFormDataRequestWithRetry object with the same requestUuid");
#endif
            foundRequest = aRequest;
        }
    }
    return foundRequest;
}

+ (ASIFormDataRequestWithRetry*) getQueuedRetryRequestWithUuid:(NSString*)uuid {
    //NSLog(@"getQueuedRetryRequestWithUuid: %@", uuid);
    ASIFormDataRequestWithRetry *foundRequest = [[self class] getRequestWithUuid:uuid fromRequests:s_requestsToRetry];
    return foundRequest;
}

// return the ASIFormDataRequestWithRetry objects that have been queued to retry
+ (NSArray*)getRequestsToRetry {
    return s_requestsToRetry;
}

+ (void)setIntitialRetryInterval:(NSTimeInterval)anIntialRetryInterval {
    s_initialRetryInterval = anIntialRetryInterval;
}

#pragma mark -

+ (void) startTimer {
    if (! s_retryTimer) {
        if(kVerboseLogging) NSLog(@"ASIFormDataRequestWithRetry: startTimer");
        
        s_retryTimer = [[NSTimer scheduledTimerWithTimeInterval:2.0 target:[self class] selector:@selector(timerFired:) userInfo:nil repeats:YES] retain]; // note: retaining here as it is static without @synthesize 
    }
}

+ (void) stopTimer {
    if(kVerboseLogging) NSLog(@"ASIFormDataRequestWithRetry: stopTimer");
    
    if ([s_retryTimer isValid]) {
        [s_retryTimer invalidate];
    }
    if (s_retryTimer) {
        [s_retryTimer release];
        s_retryTimer = nil;
    }
    
}


+ (void) timerFired:(NSTimer*)theTimer {
    NSLog(@"ASIFormDataRequest: timerFired. s_requestsToRetry's count=%d", [s_requestsToRetry count]);
    
    if (s_requestsToRetry && [s_requestsToRetry count] > 0) {
        
        // find the request(s) that are due for retry
        NSPredicate *predicate = [NSPredicate predicateWithFormat:@"nextRetryDate < %@", [NSDate date]]; // if next retry date is less than the current date
        NSArray *requestsToRetryNext = [s_requestsToRetry filteredArrayUsingPredicate:predicate];
        
        // remove the retrying request(s) from s_requestsToRetry list and retry
        if (requestsToRetryNext && [requestsToRetryNext count] > 0) {
        
            [s_requestsToRetry removeObjectsInArray:requestsToRetryNext];
            
            [requestsToRetryNext makeObjectsPerformSelector:@selector(startAsynchronousWithRetry)];
        }

    }
    
}

- (id)copyWithZone:(NSZone *)zone{
    ASIFormDataRequestWithRetry *newRequestWithRetry = [super copyWithZone:zone];
    [newRequestWithRetry setNextRetryDate:[self nextRetryDate]];
    [newRequestWithRetry setDelayedRetryCount:[self delayedRetryCount]];
    [newRequestWithRetry setRequestUuid:[self requestUuid]];
    return newRequestWithRetry;
}
 
- (NSDate*) nextDateForDelayRetryCount:(NSInteger)aDelayRetryCount {
    NSAssert(aDelayRetryCount > 0, @"delay retry count should be greater than zero");
    
    NSDate *nextDate = [[NSDate date] dateByAddingTimeInterval:((2^aDelayRetryCount - 1) * s_initialRetryInterval)];
    return nextDate;
}

#pragma mark - Reachability

+ (void) startReachbility {
    if ( ! s_reachability) {
        
        [[NSNotificationCenter defaultCenter] addObserver:[self class] selector:@selector(reachabilityChanged:) name:kReachabilityChangedNotification object:nil];
        s_reachability = [[Reachability reachabilityForInternetConnection] retain]; 
        [s_reachability startNotifier];
    }
    
}

/* This method is called whenever the network reachability changes */
+ (void) reachabilityChanged: (NSNotification* )note {
//    NSLog(@"The network reachability has changed %@", note);
    
    NetworkStatus netStatus = s_reachability.currentReachabilityStatus;
    
    
    if (netStatus == NotReachable){
        NSLog(@"NotReachable");
        
        [[self class] stopTimer];
    }else{
        NSLog(@"Reachable");
        if (s_requestsToRetry && [s_requestsToRetry count] > 0) {
            [[self class] startTimer];
        }
    }
}

#pragma mark - Helper Method

// return a new autoreleased Uuid string
// method is from http://blog.ablepear.com/2010/09/creating-guid-or-uuid-in-objective-c.html
+ (NSString *)generateUuidString {
    // create a new Uuid which you own
    CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
    
    // create a new CFStringRef (toll-free bridged to NSString)
    // that you own
    NSString *uuidString = (NSString *)CFUUIDCreateString(kCFAllocatorDefault, uuid);
    
    // transfer ownership of the string
    // to the autorelease pool
    [uuidString autorelease];
    
    // release the Uuid
    CFRelease(uuid);
    
    return uuidString;
}


//#pragma mark - Logging
//
//+ (void)logFailureOfRequest:(ASIHTTPRequest*)aRequest {
//    NSDictionary *params = [PostmatesAnalyticsHelper paramsToLogForRequest:aRequest];
//    [PostmatesAnalyticsReporter logEvent:@"request_with_retry_failure" withParameters:params timed:NO];
//    
//}
//
//+ (void)logMaxFailureOfRequest:(ASIFormDataRequestWithRetry*)aRequest {
//    NSDictionary *params = [PostmatesAnalyticsHelper paramsToLogForRequest:aRequest];
//    [PostmatesAnalyticsReporter logEvent:@"request_with_retry_failure_max" withParameters:params timed:NO];  // max count to retry has reached
//    
//}


- (void) dealloc {
//    NSLog(@"ASIHTTPRequestWithRetry: dealloc");
    
    [_nextRetryDate release];
    [_requestUuid release];
    
    [super dealloc];
}

@end
