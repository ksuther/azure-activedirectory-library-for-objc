// Copyright (c) Microsoft Corporation.
// All rights reserved.
//
// This code is licensed under the MIT License.
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files(the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and / or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions :
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

#import "ADAL_Internal.h"
#import "ADTestURLConnection.h"
#import "ADLogger.h"
#import "ADAuthenticationResult.h"
#import "NSDictionary+ADExtensions.h"
#import "ADOAuth2Constants.h"
#import "ADNetworkMock.h"


#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"
@implementation NSURLConnection (TestConnectionOverride)

- (id)initWithRequest:(NSURLRequest *)request
             delegate:(id)delegate
     startImmediately:(BOOL)startImmediately
{
    return (NSURLConnection*)[[ADTestURLConnection alloc] initWithRequest:request
                                                                 delegate:delegate
                                                         startImmediately:startImmediately];
}

- (id)initWithRequest:(NSURLRequest *)request
             delegate:(id)delegate
{
    return [self initWithRequest:request delegate:delegate startImmediately:YES];
}

@end
#pragma clang diagnostic pop

@implementation ADTestURLConnection

- (id)initWithRequest:(NSURLRequest*)request delegate:(id)delegate startImmediately:(BOOL)startImmediately
{
    if (!(self = [super init]))
    {
        return nil;
    }
    
    _delegate = delegate;
    SAFE_ARC_RETAIN(_delegate);
    _request = request;
    SAFE_ARC_RETAIN(_request);
    
    if (startImmediately)
    {
        [self start];
    }
    
    return self;
}

- (void)setDelegateQueue:(NSOperationQueue*)queue
{
    if (_delegateQueue == queue)
    {
        return;
    }
    SAFE_ARC_RELEASE(_delegateQueue);
    _delegateQueue = queue;
    SAFE_ARC_RETAIN(_delegateQueue);
}

- (void)dispatchIfNeed:(void (^)(void))block
{
    if (_delegateQueue) {
        [_delegateQueue addOperationWithBlock:block];
    }
    else
    {
        block();
    }
}

- (void)start
{
    ADTestURLResponse* response = [ADNetworkMock removeResponseForRequest:_request];
    
    if (!response)
    {
        // This class is used in the test target only. If you're seeing this outside the test target that means you linked in the file wrong
        // take it out!
        //
        // No unit tests are allowed to hit network. This is done to ensure reliability of the test code. Tests should run quickly and
        // deterministically. If you're hitting this assert that means you need to add an expected request and response to ADTestURLConnection
        // using the ADTestRequestReponse class and add it using -[ADTestURLConnection addExpectedRequestResponse:] if you have a single
        // request/response or -[ADTestURLConnection addExpectedRequestsAndResponses:] if you have a series of network requests that you need
        // to ensure happen in the proper order.
        //
        // Example:
        //
        // ADTestRequestResponse* response = [ADTestRequestResponse requestURLString:@"https://login.windows.net/common/discovery/instance?api-version=1.0&authorization_endpoint=https://login.windows.net/omercantest.onmicrosoft.com/oauth2/authorize&x-client-Ver=" ADAL_VERSION_STRING
        //                                                         responseURLString:@"https://idontknowwhatthisshouldbe.com"
        //                                                              responseCode:400
        //                                                          httpHeaderFields:@{}
        //                                                          dictionaryAsJSON:@{@"tenant_discovery_endpoint" : @"totally valid!"}];
        //
        //  [ADTestURLConnection addExpectedRequestResponse:response];
        //
        //
        //  Consult the ADTestRequestResponse class for a list of helper methods for formulating requests and responses.
        NSString* requestURLString = [[_request URL] absoluteString];
        NSAssert(response, @"did not find a matching response for %@", requestURLString);
        (void)requestURLString;
        
        AD_LOG_ERROR_F(@"No matching response found.", NSURLErrorNotConnectedToInternet, nil, @"request url = %@", [_request URL]);
        [self dispatchIfNeed:^{
            NSError* error = [NSError errorWithDomain:NSURLErrorDomain
                                                 code:NSURLErrorNotConnectedToInternet
                                             userInfo:nil];
            
            [_delegate connection:(NSURLConnection*)self
                 didFailWithError:error];
        }];
        
        return;
    }
    
    if (response->_error)
    {
        [self dispatchIfNeed:^{
            [_delegate connection:(NSURLConnection*)self
                 didFailWithError:response->_error];
        }];
        return;
    }
    
    if (response->_expectedRequestHeaders)
    {
        BOOL failed = NO;
        for (NSString* key in response->_expectedRequestHeaders)
        {
            NSString* value = [response->_expectedRequestHeaders objectForKey:key];
            NSString* requestValue = [[_request allHTTPHeaderFields] objectForKey:key];
            
            if (!requestValue)
            {
                AD_LOG_ERROR_F(@"Missing request header", AD_FAILED, nil, @"expected \"%@\" header", key);
                failed = YES;
            }
            
            if (![requestValue isEqualToString:value])
            {
                AD_LOG_ERROR_F(@"Mismatched request header", AD_FAILED, nil, @"On \"%@\" header, expected:\"%@\" actual:\"%@\"", key, value, requestValue);
                failed = YES;
            }
        }
        
        if (failed)
        {
            [self dispatchIfNeed:^{
                [_delegate connection:(NSURLConnection*)self
                     didFailWithError:[NSError errorWithDomain:NSURLErrorDomain
                                                          code:NSURLErrorNotConnectedToInternet
                                                      userInfo:nil]];
            }];
        }
    }
    
    if (response->_response)
    {
        [self dispatchIfNeed:^{
            [_delegate connection:(NSURLConnection*)self
               didReceiveResponse:response->_response];
        }];
    }
    
    if (response->_responseData)
    {
        [self dispatchIfNeed:^{
            [_delegate connection:(NSURLConnection*)self
                   didReceiveData:response->_responseData];
        }];
    }
    
    [self dispatchIfNeed:^{
        [_delegate connectionDidFinishLoading:(NSURLConnection*)self];
    }];
    
    return;
}

- (void)cancel
{
    
}

@end
