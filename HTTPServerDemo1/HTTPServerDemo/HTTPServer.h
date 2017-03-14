//
//  HTTPServer.h
//  HTTPServerDemo
//
//  Created by yanghao on 2017/3/9.
//  Copyright © 2017年 justlike. All rights reserved.
//

#import <Foundation/Foundation.h>


@class HTTPResponseHandler;

@interface HTTPServer : NSObject

+ (HTTPServer *)sharedHTTPServer;

- (void)start;
- (void)stop;

- (void)closeHandler:(HTTPResponseHandler *)aHandler;

@end
