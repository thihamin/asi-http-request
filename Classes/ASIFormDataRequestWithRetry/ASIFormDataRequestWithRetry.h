//
//  ASIHTTPRequestWithRetry.h
//  PostmatesCourier
//
//  Created by Thiha Min on 1/11/12.
//  Copyright (c) 2012 Postmates. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "ASIFormDataRequest.h"


/*
 This class adds 'retry' funtionality to the ASIFormDataRequest class.  
 The caller will create the ASIFormDataRequestWithRetry object and call startAsynchronousWithRetry.
 When the request fails, this class will reschedule the request to try after a delay.  The delay time will be double with each failure.
 The class gives up the request to retry when maximum retry count is reached.  
 
 When timeout occurs, the request is retried one more time before putting the request in the queue to retry after a delay.
 This is to increase the chance of success when timeout.  If internet connection is not reachable, the retry will be paused.
 
 This class is intended as best effort retry for the calls that do not require response right away.
 
 
 NOTE: As of 20120119 version, the caller must *not* set delegate of this class as the delegate methods are used internally for rescheduling the request.
 This class retries on http 500 error but ignore lower error codes such as 400.
 
 Usage:
     ASIFormDataRequestWithRetry *request = [ASIFormDataRequestWithRetry requestWithURL:url];
     
     // ... set post values
     
     [request startAsynchronousWithRetry]
 
 
 */

@interface ASIFormDataRequestWithRetry : ASIFormDataRequest


@property (nonatomic, copy) NSString *requestUuid;  // note: ASIHTTPRequest has requestID which is used for debugging persistent connection
                                                    // delcaring another id here so that we can use it for separate purpose.
                                                    // another choice will be to use 'tag' of asihttprequest


- (void) startAsynchronousWithRetry;


@end
