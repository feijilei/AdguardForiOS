/**
    This file is part of Adguard for iOS (https://github.com/AdguardTeam/AdguardForiOS).
    Copyright © 2015 Performix LLC. All rights reserved.

    Adguard for iOS is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Adguard for iOS is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Adguard for iOS.  If not, see <http://www.gnu.org/licenses/>.
*/
#import "ACommons/ACLang.h"
#import "ABECFilter.h"
#import "ABECConstants.h"
#import "ASDFilterObjects.h"
#import "ABECRequest.h"
#import "ABECFilterParsers.h"

/////////////////////////////////////////////////////////////////////
#pragma mark - ABECFilterClient Constants
/////////////////////////////////////////////////////////////////////

#define FILTERID_PARAM                  @"filterid"

NSString *ABECPlatformKey               = @"ABECPlatformKey";

NSString *ABECFilterParserKey           = @"ABECFilterParserKey";
NSString *ABECFilterVersionParserKey    = @"ABECFIlterVersionParserKey";
NSString *ABECFilterMetaParserKey       = @"ABECFilterMetaParserKey";
NSString *ABECFilterGroupMetaParserKey  = @"ABECFilterGroupMetaParserKey";

NSString *ABECFilterUrlKey              = @"ABECFilterUrlKey";
NSString *ABECFIlterVersionUrlKey       = @"ABECFIlterVersionUrlKey";
NSString *ABECFilterMetaUrlKey          = @"ABECFILTERMetaUrlKey";
NSString *ABECFilterGroupMetaUrlKey     = @"ABECFilterGroupMetaUrlKey";

NSString *ABECFilterError = @"ABECFilterError";

static NSDictionary *ABECFilterSettings;

void settings(){
    
    ABECFilterSettings = @{
                           
                           // Settings for iOS
                           ABEC_PLATFORM_IOS:
                               @{
                                   ABECPlatformKey: ABEC_PLATFORM_IOS,
                                   
                                   ABECFilterParserKey:          [PlainFilterParser class],
                                   ABECFilterVersionParserKey:   [JSONVersionParser class],
                                   ABECFilterMetaParserKey:      [JSONMetadataParser class],
                                   ABECFilterGroupMetaParserKey: [JSONGroupParser class],
                                   
#if DEBUG
                                   ABECFilterUrlKey:            @"http://testmobile.adtidy.org/api/1.0/getiosfilter.html?key=KPQ8695OH49KFCWC9EMX95OH49KFF50S",
                                   ABECFIlterVersionUrlKey:     @"http://testmobile.adtidy.org/api/1.0/checkfilterversions.html?key=KPQ8695OH49KFCWC9EMX95OH49KFF50S",
                                   ABECFilterMetaUrlKey:        @"http://testmobile.adtidy.org/api/1.0/getfiltersmeta.html?key=KPQ8695OH49KFCWC9EMX95OH49KFF50S",
                                   ABECFilterGroupMetaUrlKey:   @"http://testmobile.adtidy.org/api/1.0/getgroupsmeta.html?key=KPQ8695OH49KFCWC9EMX95OH49KFF50S"
#else
                                   ABECFilterUrlKey:            @"http://mobile.adtidy.org/api/1.0/getiosfilter.html?key=KPQ8695OH49KFCWC9EMX95OH49KFF50S",
                                   ABECFIlterVersionUrlKey:     @"http://mobile.adtidy.org/api/1.0/checkfilterversions.html?key=KPQ8695OH49KFCWC9EMX95OH49KFF50S",
                                   ABECFilterMetaUrlKey:        @"http://mobile.adtidy.org/api/1.0/getfiltersmeta.html?key=KPQ8695OH49KFCWC9EMX95OH49KFF50S",
                                   ABECFilterGroupMetaUrlKey:   @"http://mobile.adtidy.org/api/1.0/getgroupsmeta.html?key=KPQ8695OH49KFCWC9EMX95OH49KFF50S"
#endif
                                   }
                           };

}

/////////////////////////////////////////////////////////////////////
#pragma mark - ABECFilterClient
/////////////////////////////////////////////////////////////////////

@implementation ABECFilterClient{
    
    NSString *_platform;
    NSURL *filterMetaUrl;
    NSURL *groupMetaUrl;
    NSURL *filterVersionUrl;
    NSURL *filterUrl;
    
    NSArray *_asyncFilterVersions;
    ASDFilter *_asyncFilter;
    NSUInteger _asyncFiltersCount;
    NSUInteger _asyncCurrentFiltersCount;
    BOOL _handleBackground;
    BOOL _asyncInProgress;
}

static ABECFilterClient *ABECFilterSingleton;

/////////////////////////////////////////////////////////////////////
#pragma mark Init and Class methods
/////////////////////////////////////////////////////////////////////

+ (ABECFilterClient *)singleton{
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        ABECFilterSingleton = [ABECFilterClient alloc];
        ABECFilterSingleton = [ABECFilterSingleton init];
    });
    
    return ABECFilterSingleton;
    
}

- (id)init{
    
    return [self initWithPlatform:ABEC_DEFAULT_PLATFORM];
}

- (id)initWithPlatform:(NSString *)platform{
    
    self = [super init];
    if (self) {

        _platform = platform;
        NSDictionary *settings = ABECFilterSettings[_platform];
        
        filterUrl = [NSURL URLWithString:settings[ABECFilterUrlKey]];
        filterVersionUrl = [NSURL URLWithString:settings[ABECFIlterVersionUrlKey]];
        filterMetaUrl = [NSURL URLWithString:settings[ABECFilterMetaUrlKey]];
        groupMetaUrl = [NSURL URLWithString:settings[ABECFilterGroupMetaUrlKey]];
        
        _asyncInProgress = YES;
        _handleBackground = NO;
        _updateTimeout = 0;
    }
    
    return self;
}

+ (void)initialize{
    
    if (self == [ABECFilterClient class]) {
        
        settings();
    }
}

+ (NSString *)reachabilityHost:(NSString *)platform{
    
    NSDictionary *settings = ABECFilterSettings[platform];

    // we will be use host from "get filter url" for checking reachability
    return [[NSURL URLWithString:settings[ABECFilterUrlKey]] host];
}

+ (NSString *)reachabilityHost{
    
    return [ABECFilterClient reachabilityHost:ABEC_DEFAULT_PLATFORM];
}

/////////////////////////////////////////////////////////////////////
#pragma mark Properties and public methods
/////////////////////////////////////////////////////////////////////

- (NSArray *)filterVersionListForApp:(NSString *)applicationId filterIds:(id<NSFastEnumeration>)filterIds{

    
    NSURLRequest *sURLRequest = [self requestForFilterVersionListForApp:applicationId filterIds:filterIds];
    if (!sURLRequest) {
        return nil;
    }
    
    NSURLResponse *response;
    NSError *error;
    
    NSData *data = [NSURLConnection sendSynchronousRequest:sURLRequest returningResponse:&response error:&error];

    return [self filterVersionFromData:data response:response error:error];
}

- (NSURLRequest *)requestForApp:(NSString *)applicationId affiliateId:(NSString *)affiliateId filterId:(NSUInteger)filterId{
    
    if (!applicationId || !affiliateId)
        return nil;
    
    return [[ABECRequest
            getRequestForURL:filterUrl
            parameters:@{
                         @"app_id": applicationId,
                         @"webmaster_id": affiliateId,
                         FILTERID_PARAM: [NSString stringWithFormat:@"%lu", (unsigned long)filterId]
                         }] copy];

}

- (ASDFilter *)filterForApp:(NSString *)applicationId affiliateId:(NSString *)affiliateId filterId:(NSUInteger)filterId{

    if (!applicationId || !affiliateId)
        return nil;
    
    ABECRequest *sURLRequest = [self requestForApp:applicationId affiliateId:affiliateId filterId:filterId];
    
    NSURLResponse *response;
    NSError *error;
    
    NSData *data = [NSURLConnection sendSynchronousRequest:sURLRequest returningResponse:&response error:&error];
    
    return [self filterForData:data response:response filterId:@(filterId) error:error];
}

- (NSArray *)filterMetadataListForApp:(NSString *)applicationId {
    
    if (!applicationId)
        return nil;
    
    ABECRequest *sURLRequest = [ABECRequest getRequestForURL:filterMetaUrl parameters:nil];
    NSURLResponse *response;
    NSError *error;
    
    NSData *data = [NSURLConnection sendSynchronousRequest:sURLRequest returningResponse:&response error:&error];
    
    // here we check for any returned NSError from the server, "and" we also check for any http response errors
    if (error != nil)
        DDLogError(@"Error loading filters metadata info:%@", [error localizedDescription]);
    
    else {
        // check for any response errors
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if ((([httpResponse statusCode]/100) == 2)) {
            
            
            // parse response data
            id<MetadataParserProtocol> metadataParser = [self parserForKey:ABECFilterMetaParserKey];
            
            if (![metadataParser parseWithData:data]) {
                
                DDLogError(@"Error when loading filters metadata info. Can't parse XML.");
                DDLogErrorTrace();
                return nil;
            }
            
            return [metadataParser metadataList];
        }
        else {
            
            DDLogError(@"Http Error when loading filters metadata info. Http Status:%li", (long)[httpResponse statusCode]);
            DDLogErrorTrace();
        }
    }
    
    return nil;
}


- (NSArray *)groupMetadataListForApp:(NSString *)applicationId {
    
    if (!applicationId)
        return nil;
    
    ABECRequest *sURLRequest = [ABECRequest getRequestForURL:groupMetaUrl parameters:nil];
    NSURLResponse *response;
    NSError *error;
    
    NSData *data = [NSURLConnection sendSynchronousRequest:sURLRequest returningResponse:&response error:&error];
    
    // here we check for any returned NSError from the server, "and" we also check for any http response errors
    if (error != nil)
        DDLogError(@"Error loading filter groups metadata info:%@", [error localizedDescription]);
        
        else {
            // check for any response errors
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            if ((([httpResponse statusCode]/100) == 2)) {
                
                
                // parse response data
                id<GroupParserProtocol> groupParser = [self parserForKey:ABECFilterGroupMetaParserKey];
                
                if (![groupParser parseWithData:data]) {
                    
                    DDLogError(@"Error when loading filter groups info. Can't parse XML.");
                    DDLogErrorTrace();
                    return nil;
                }
                
                return [groupParser groupList];
            }
            else{
             
                DDLogError(@"Http Error when loading filter groups info. Http Status:%li", (long)[httpResponse statusCode]);
                DDLogErrorTrace();
            }
        }
    
    return nil;
}

/////////////////////////////////////////////////////////////////////
#pragma mark  Async support methods
- (void)setupWithSessionId:(NSString *)sessionId updateTimeout:(NSTimeInterval)updateTimeout delegate:(id<ABECFilterAsyncDelegateProtocol>)delegate inProgress:(BOOL)inProgress {

    @synchronized(ABECFilterSingleton) {

        DDLogDebug(@"(ABECFilterClient) setupWithSessionId:delegate: %@ inProgress: %@", delegate, (inProgress ? @"YES" : @"NO"));

        self.sessionId = sessionId;
        self.delegate = delegate;
        self.updateTimeout = updateTimeout;
        _asyncInProgress = inProgress;
        [self backgroundSession];
    }
}

- (void)handleBackgroundWithSessionId:(NSString *)sessionId updateTimeout:(NSTimeInterval)updateTimeout delegate:(id<ABECFilterAsyncDelegateProtocol>)delegate {
    DDLogDebug(@"(ABECFilterClient) handleBackgroundWithSessionId:delegate: %@", delegate);

    [self setupWithSessionId:sessionId updateTimeout:updateTimeout delegate:delegate inProgress:YES];
    _handleBackground = YES;
    return;
}

- (NSError *)asyncFilterVersionListForApp:(NSString *)applicationId filterIds:(id<NSFastEnumeration>)filterIds {

    @synchronized (ABECFilterSingleton) {
        
        NSError *error = [self checkConditionForAsync];
        if (error) {
            return error;
        }
        
        _asyncFilterVersions = nil;
        
        NSURLRequest *sURLRequest = [self requestForFilterVersionListForApp:applicationId filterIds:filterIds];
        if (!sURLRequest) {
            return [NSError errorWithDomain:ABECFilterError code:ABECFILTER_ERROR_PARAMETERS userInfo:nil];
        }
        
        NSURLSessionDownloadTask *currentTask = [[self backgroundSession] downloadTaskWithRequest:sURLRequest];
        [currentTask resume];
        _asyncInProgress = YES;
        
        return nil;
    }
}

- (NSError *)asyncFilterForApp:(NSString *)applicationId affiliateId:(NSString *)affiliateId filterIds:(NSArray <NSNumber *>*)filterIds {

    @synchronized (ABECFilterSingleton) {
        
        NSError *error = [self checkConditionForAsync];
        if (error) {
            return error;
        }

        _asyncFilter = nil;
        _asyncFiltersCount = filterIds.count;

        for (NSNumber *filterId in filterIds) {
            NSURLRequest *sURLRequest = [self requestForApp:applicationId affiliateId:affiliateId filterId:[filterId integerValue]];
            if (!sURLRequest) {
                return [NSError errorWithDomain:ABECFilterError code:ABECFILTER_ERROR_PARAMETERS userInfo:nil];
            }
            
            NSURLSessionDownloadTask *currentTask = [[self backgroundSession] downloadTaskWithRequest:sURLRequest];
            [currentTask resume];
        }

        _asyncInProgress = YES;
        
        return nil;
    }
}

/////////////////////////////////////////////////////////////////////
#pragma mark  Download session delegate methods

- (void)URLSession:(NSURLSession *)session downloadTask:(NSURLSessionDownloadTask *)downloadTask didFinishDownloadingToURL:(NSURL *)downloadURL {

    DDLogDebug(@"(ABECFilterClient) URLSession:downloadTask:didFinishDownloadingToURL:. Request URL: %@", [[downloadTask originalRequest] URL]);
    [self processDownloadTask:downloadTask error:nil downloadURL:downloadURL];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {

    DDLogDebug(@"(ABECFilterClient) URLSession:task:didCompleteWithError: %@. Request URL: %@", error, [[task originalRequest] URL]);
    [self processDownloadTask:(NSURLSessionDownloadTask *)task error:error downloadURL:nil];
}

- (void)URLSessionDidFinishEventsForBackgroundURLSession:(NSURLSession *)session {
    
    DDLogDebug(@"(ABECFilterClient) URLSessionDidFinishEventsForBackgroundURLSession:");
    
    _handleBackground = NO;
    [self unlockAsync];
}

- (void)URLSession:(NSURLSession *)session didBecomeInvalidWithError:(NSError *)error {
    
    DDLogDebug(@"(ABECFilterClient) URLSession:didBecomeInvalidWithError: %@", error);
    
    [self unlockAsync];
}
/////////////////////////////////////////////////////////////////////
#pragma mark Private methods
/////////////////////////////////////////////////////////////////////

- (id)parserForKey:(NSString *)key{
    
    NSDictionary *settings = ABECFilterSettings[_platform];
    id theClass = settings[key];
    if (!theClass) {
        
        [[NSException argumentException:key] raise];
    }
    
    return [theClass new];
}

- (NSURLRequest *)requestForFilterVersionListForApp:(NSString *)applicationId filterIds:(id<NSFastEnumeration>)filterIds {
    
    if (!(applicationId && filterIds))
        return nil;
    
    NSMutableString *parameters = [NSMutableString
                                   stringWithFormat:@"%@app_id=%@",
                                   ([NSString isNullOrEmpty:[filterVersionUrl query]]
                                    ? @"?"
                                    : @"&"),
                                   applicationId];
    BOOL emptyFilterIds = YES;
    for (NSNumber *filterId in filterIds) {
        
        [parameters appendFormat:@"&filterid=%@", filterId];
        emptyFilterIds = NO;
    }
    if (emptyFilterIds) return nil;
    
    NSURL *url = [NSURL URLWithString:[[filterVersionUrl absoluteString] stringByAppendingString:parameters]];
    
    return [[ABECRequest getRequestForURL:url parameters:nil] copy];
}

- (NSArray *)filterVersionFromData:(NSData *)data response:(NSURLResponse *)response error:(NSError *)error {
    
    // here we check for any returned NSError from the server, "and" we also check for any http response errors
    if (error != nil)
        DDLogError(@"Error loading filters version info:%@", [error localizedDescription]);
    
    else {
        // check for any response errors
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if ((([httpResponse statusCode]/100) == 2)) {
            
            // parse response data
            id<VersionParserProtocol> versionParser = [self parserForKey:ABECFilterVersionParserKey];
            
            if ([versionParser parseWithData:data]) {
                
                return [versionParser versionList];
            }
            else{
                
                DDLogError(@"Error loading filters version info: Can't parse XML.");
                DDLogErrorTrace();
                return nil;
            }
        }
        else {
            
            DDLogError(@"Http Error when loading filter version info. Http Status:%li", (long)[httpResponse statusCode]);
            DDLogErrorTrace();
        }
    }
    
    return nil;
}

- (ASDFilter *)filterForData:(NSData *)data response:(NSURLResponse *)response filterId:(NSNumber *)filterId error:(NSError *)error{
    
    // here we check for any returned NSError from the server, "and" we also check for any http response errors
    if (error != nil)
        DDLogError(@"Error loading filter rules:%@", [error localizedDescription]);
    
    else {
        // check for any response errors
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if ((([httpResponse statusCode]/100) == 2)) {
            
            
            id<FilterParserProtocol> filterParser = [self parserForKey:ABECFilterParserKey];
            
            filterParser.filterId = filterId;
            
            if (![filterParser parseWithData:data]) {
                
                DDLogError(@"Error when loading filter rules (filterId = %lu). Can't parse XML.", [filterId unsignedLongValue]);
                DDLogErrorTrace();
                return nil;
            }
            
            ASDFilter *filter = [filterParser filter];
            
            return filter;
        }
        else {
            
            DDLogError(@"Http Error when loading filter rules (filterId = %lu). Http Status:%li", (unsigned long)filterId, [httpResponse statusCode]);
            DDLogErrorTrace();
        }
    }
    
    return nil;
    
}

- (NSURLSession *)backgroundSession
{
    static NSURLSession *session = nil;
    static dispatch_once_t onceToken;
    
    if ([NSString isNullOrEmpty:self.sessionId] || !self.updateTimeout) {
        return nil;
    }
    
    dispatch_once(&onceToken, ^{
        NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:self.sessionId];
        configuration.networkServiceType = NSURLNetworkServiceTypeBackground;
        configuration.timeoutIntervalForRequest = ABEC_BACKEND_READ_TIMEOUT;
        configuration.timeoutIntervalForResource = self.updateTimeout;

        session = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:nil];
    });
    return session;
}

- (void)unlockAsync {
    @synchronized(ABECFilterSingleton) {
        
        _asyncInProgress = NO;
    }
}

- (NSError *)checkConditionForAsync {
    if (_asyncInProgress) {
        
        DDLogError(@"(ABECFilterClient) Error: async operation in progress");
        return [NSError errorWithDomain:ABECFilterError code:ABECFILTER_ERROR_ASYNC_INPROGRESS userInfo:nil];
    }

    if (!(self.delegate && self.sessionId && self.updateTimeout)) {
        DDLogError(@"(ABECFilterClient) Async operations can't be performed. You need setup it before.");
        return [NSError errorWithDomain:ABECFilterError code:ABECFILTER_ERROR_ASYNC_NOTINIT userInfo:nil];
    }
    
    return nil;
}

- (void)processDownloadTask:(NSURLSessionDownloadTask *)downloadTask error:(NSError *)error downloadURL:(NSURL *)downloadURL {
    
    NSURL *requestUrl = [[downloadTask originalRequest] URL];
    if ([[requestUrl absoluteString] hasPrefix:[filterVersionUrl absoluteString]]) {
        
        // was filter version request
        
        DDLogDebug(@"(ABECFilterClient) processDownloadTask:error:downloadURL:. Version list.");
        
        if (error) {
            DDLogError(@"(ABECFilterClient) ASync. Error loading filter versions info:%@", [error localizedDescription]);
        }

        if (downloadURL) {
            
            //call finished download
            
            NSData *data = [NSData dataWithContentsOfURL:downloadURL];
            if (data) {

                _asyncFilterVersions = [self filterVersionFromData:data response:[downloadTask response] error:nil];
            }
        }
        else {
            
            // call from task complated
            
            [self unlockAsync];
            [self.delegate filterClient:self filterVersionList:_asyncFilterVersions];
            _asyncFilterVersions = nil;
        }
        
    } else if ([[requestUrl absoluteString] hasPrefix:[filterUrl absoluteString]]) {
        
        //was filter request

        DDLogDebug(@"(ABECFilterClient) processDownloadTask:error:downloadURL:. Filters.");
        
        NSNumber *filterId = [self filterIdFromRequestUrl:requestUrl];
        if (!filterId) {
            return;
        }
        
        if (error) {
            DDLogError(@"(ABECFilterClient) ASync. Error loading filter data:%@", [error localizedDescription]);
        }
        
        if (downloadURL) {

            //call finished download
            NSData *data = [NSData dataWithContentsOfURL:downloadURL];
            if (data) {
                
                _asyncFilter = [self filterForData:data response:[downloadTask response] filterId:filterId error:nil];
            }
        }
        else {
            
            // call from task complated

            if (_asyncFiltersCount <= (++_asyncCurrentFiltersCount)) {
                [self unlockAsync];
            }
            
            [self.delegate filterClient:self filterId:filterId filter:_asyncFilter];
            _asyncFilter = nil;
        }
    }
}

- (NSNumber *)filterIdFromRequestUrl:(NSURL *)requestUrl {

    NSURLComponents *components = [NSURLComponents componentsWithURL:requestUrl resolvingAgainstBaseURL:NO];
    NSNumber *filterId;
    for (NSURLQueryItem *item in components.queryItems) {
        
        if ([item.name isEqualToString:FILTERID_PARAM]) {
            filterId = @([item.value integerValue]);
            break;
        }
    }
    return filterId;
}

@end
