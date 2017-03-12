//
//  HTTPServer.m
//  HTTPServerDemo
//
//  Created by yanghao on 2017/3/9.
//  Copyright © 2017年 justlike. All rights reserved.
//

#import "HTTPServer.h"
#import <sys/socket.h>
#import <netinet/in.h>
#import <CFNetwork/CFNetwork.h>
#import "HTTPResponseHandler.h"

@interface HTTPServer ()
{
	NSFileHandle *listeningHandle;
	CFSocketRef socket;
	CFMutableDictionaryRef incomingRequests;
	NSMutableSet *responseHandlers;
}

@end


@implementation HTTPServer

+ (HTTPServer *)sharedHTTPServer
{
	static HTTPServer * httpServer;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		httpServer = [[HTTPServer alloc]init];
	});
	return httpServer;
}


- (instancetype)init{
	self = [super init];
	
	if (self) {
		incomingRequests =
		CFDictionaryCreateMutable(
								  kCFAllocatorDefault,
								  0,
								  &kCFTypeDictionaryKeyCallBacks,
								  &kCFTypeDictionaryValueCallBacks);
		responseHandlers = [[NSMutableSet alloc] init];
		
	}
	
	return self;
}


- (void)start
{
	//创建socket
	socket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM, IPPROTO_TCP, 0, NULL, NULL);
	
	if (!socket)
	{
		NSLog(@"Unable to create socket.");
		return;
	}
	
	int reuse = true;
	int fileDescriptor = CFSocketGetNative(socket);//返回与CFSocket对象关联的本机套接字。
	if (setsockopt(fileDescriptor, SOL_SOCKET, SO_REUSEADDR,
				   (void *)&reuse, sizeof(int)) != 0)//设置允许重用本地地址和端口
	{
		NSLog(@"Unable to set socket options.");
		return;
	}
	//定义sockaddr_in类型的变量，该变量将作为CFSocket的地址
	struct sockaddr_in Socketaddr;
	memset(&Socketaddr, 0, sizeof(Socketaddr));
	Socketaddr.sin_len = sizeof(Socketaddr);
	Socketaddr.sin_family = AF_INET;
	//设置该服务器监听本机任意可用的IP地址
	//设置服务器监听地址
	Socketaddr.sin_addr.s_addr = htonl(INADDR_ANY);
	//设置服务器监听端口
	Socketaddr.sin_port = htons(8088);
	//将IPv4的地址转换为CFDataRef
	CFDataRef address = CFDataCreate(kCFAllocatorDefault, (UInt8 *)&Socketaddr, sizeof(Socketaddr));
	//将CFSocket绑定到指定IP地址
	if(CFSocketSetAddress(socket, address) != kCFSocketSuccess) {
		NSLog(@"Unable to bind socket to address.");
		return ;
	}
	//使用socket作为fileDescriptor为套接字创建文件句柄。需要手动关闭
	listeningHandle = [[NSFileHandle alloc]initWithFileDescriptor:fileDescriptor closeOnDealloc:YES];
	
	//有客户端连接进来的监听函数（也可以是上面CFSocketCreate创建的回调函数）
	[[NSNotificationCenter defaultCenter]
		addObserver:self
		selector:@selector(receiveIncomingConnectionNotification:)
		name:NSFileHandleConnectionAcceptedNotification
		object:nil];
	
	//在后台接受套接字连接（仅适用于流式套接字），并为通信通道的“近”（客户端）端创建文件句柄。
	[listeningHandle acceptConnectionInBackgroundAndNotify];
	
}

//
// stopReceivingForFileHandle:close:
//
// If a file handle is accumulating the header for a new connection, this
// method will close the handle, stop listening to it and release the
// accumulated memory.
//
// Parameters:
//    incomingFileHandle - the file handle for the incoming request
//    closeFileHandle - if YES, the file handle will be closed, if no it is
//		assumed that an HTTPResponseHandler will close it when done.
//
- (void)stopReceivingForFileHandle:(NSFileHandle *)incomingFileHandle
							 close:(BOOL)closeFileHandle
{
	if (closeFileHandle)
	{
		[incomingFileHandle closeFile];
	}
	//关闭客户端的请求数据监听
	[[NSNotificationCenter defaultCenter]
		removeObserver:self
		name:NSFileHandleDataAvailableNotification
		object:incomingFileHandle];
	//移除接收数据文件句柄
	CFDictionaryRemoveValue(incomingRequests, (__bridge const void *)(incomingFileHandle));
}

//
// stop
//
// Stops the server.
//
- (void)stop
{
	//移除客户端连接监听
	[[NSNotificationCenter defaultCenter]
		removeObserver:self
		name:NSFileHandleConnectionAcceptedNotification
		object:nil];
	
	[responseHandlers removeAllObjects];
	
	[listeningHandle closeFile];
	listeningHandle = nil;
	
	for (NSFileHandle *incomingFileHandle in
		 [(__bridge NSDictionary *)incomingRequests copy])
	{
		[self stopReceivingForFileHandle:incomingFileHandle close:YES];
	}
	
	if (socket)
	{
		CFSocketInvalidate(socket);
		CFRelease(socket);
		socket = nil;
	}
	
}


#pragma  mark - kvo
//
// receiveIncomingConnectionNotification:
//
// Receive the notification for a new incoming request. This method starts
// receiving data from the incoming request's file handle and creates a
// new CFHTTPMessageRef to store the incoming data..
//
// Parameters:
//    notification - the new connection notification
//
- (void)receiveIncomingConnectionNotification:(NSNotification *)notification
{
	NSDictionary *userInfo = [notification userInfo];
	NSFileHandle *incomingFileHandle =
	[userInfo objectForKey:NSFileHandleNotificationFileHandleItem];
	
	if(incomingFileHandle)
	{
		//存入一个空消息对象
		CFDictionaryAddValue(
							 incomingRequests,
							 (__bridge const void *)(incomingFileHandle),
							 (__bridge const void *)((__bridge id)CFHTTPMessageCreateEmpty(kCFAllocatorDefault, TRUE)));
		//客户端发送的请求数据，当文件句柄确定数据当前可用于在文件或通信信道中读取时，发布此通知。
		[[NSNotificationCenter defaultCenter]
			addObserver:self
			selector:@selector(receiveIncomingDataNotification:)
			name:NSFileHandleDataAvailableNotification
			object:incomingFileHandle];
		//准备接收客户端的请求数据，当数据可用时，此方法在当前线程上发布通知。您必须从具有活动运行循环的线程调用此方法。异步检查以查看数据是否可用。
		[incomingFileHandle waitForDataInBackgroundAndNotify];
	}
	
	[listeningHandle acceptConnectionInBackgroundAndNotify];
}
//
// receiveIncomingDataNotification:
//
// Receive new data for an incoming connection.
//
// Once enough data is received to fully parse the HTTP headers,
// a HTTPResponseHandler will be spawned to generate a response.
//
// Parameters:
//    notification - data received notification
//
- (void)receiveIncomingDataNotification:(NSNotification *)notification
{
	NSFileHandle *incomingFileHandle = [notification object];
	NSData *data = [incomingFileHandle availableData];//可用数据
	if ([data length] == 0)
	{
		[self stopReceivingForFileHandle:incomingFileHandle close:NO];
		return;
	}
	/*消息对象*/
	CFHTTPMessageRef incomingRequest =
	(CFHTTPMessageRef)CFDictionaryGetValue(incomingRequests, (__bridge const void *)(incomingFileHandle));
	if (!incomingRequest)
	{
		[self stopReceivingForFileHandle:incomingFileHandle close:YES];
		return;
	}
	/*此函数将由newBytes指定的数据附加到通过调用CFHTTPMessageCreateEmpty创建的指定消息对象。数据是从客户端或服务器接收的传入的串行化HTTP请求或响应。在附加数据时，此函数对其进行反序列化，删除消息可能包含的任何基于HTTP的格式，并将消息存储在消息对象中。然后，您可以分别调用CFHTTPMessageCopyVersion，CFHTTPMessageCopyBody，CFHTTPMessageCopyHeaderFieldValue和CFHTTPMessageCopyAllHeaderFields来获取消息的HTTP版本，消息的正文，特定的头字段和所有的消息头。
	 如果消息是请求，您还可以分别调用CFHTTPMessageCopyRequestURL和CFHTTPMessageCopyRequestMethod来获取消息的请求URL和请求方法。
	 如果消息是响应，您还可以分别调用CFHTTPMessageGetResponseStatusCode和CFHTTPMessageCopyResponseStatusLine来获取消息的状态代码和状态行。*/
	if (!CFHTTPMessageAppendBytes(
								  incomingRequest,
								  [data bytes],
								  [data length]))
	{
		[self stopReceivingForFileHandle:incomingFileHandle close:YES];
		return;
	}
	//调用CFHTTPMessageAppendBytes后，调用此函数以查看消息头是否完成。
	if(CFHTTPMessageIsHeaderComplete(incomingRequest))
	{
		HTTPResponseHandler *handler =
		[HTTPResponseHandler
		 handlerForRequest:incomingRequest
		 fileHandle:incomingFileHandle
		 server:self];
		
		[responseHandlers addObject:handler];
		[self stopReceivingForFileHandle:incomingFileHandle close:NO];
		
		[handler startResponse];
		return;
	}
	
	[incomingFileHandle waitForDataInBackgroundAndNotify];
}

//
// closeHandler:
//
// Shuts down a response handler and removes it from the set of handlers.
//
// Parameters:
//    aHandler - the handler to shut down.
//
- (void)closeHandler:(HTTPResponseHandler *)aHandler
{
	[aHandler endResponse];
	[responseHandlers removeObject:aHandler];
}

@end
