//
//  HTTPResponseHandle.h
//  HTTPServerDemo
//
//  Created by yanghao on 2017/3/9.
//  Copyright © 2017年 justlike. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CFNetwork/CFNetwork.h>
#import "HTTPServer.h"

@interface HTTPResponseHandler : NSObject
{
	CFHTTPMessageRef request;
	NSString *requestMethod;
	NSDictionary *headerFields;
	NSFileHandle *fileHandle;
	HTTPServer *server;
	NSURL *url;
}

@property (nonatomic, strong) NSFileManager *fileManager;

+ (NSUInteger)priority;
+ (void)registerHandler:(Class)handlerClass;
+ (NSString *)pathForFile;


+ (HTTPResponseHandler *)handlerForRequest:(CFHTTPMessageRef)aRequest
								fileHandle:(NSFileHandle *)requestFileHandle
									server:(HTTPServer *)aServer;

- (id)initWithRequest:(CFHTTPMessageRef)aRequest
			   method:(NSString *)method
				  url:(NSURL *)requestURL
		 headerFields:(NSDictionary *)requestHeaderFields
		   fileHandle:(NSFileHandle *)requestFileHandle
			   server:(HTTPServer *)aServer;
- (void)startResponse;
- (void)endResponse;



@end
