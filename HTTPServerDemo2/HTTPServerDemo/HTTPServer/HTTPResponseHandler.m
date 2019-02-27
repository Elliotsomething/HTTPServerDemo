//
//  HTTPResponseHandle.m
//  HTTPServerDemo
//
//  Created by yanghao on 2017/3/9.
//  Copyright © 2017年 justlike. All rights reserved.
//

#import "HTTPResponseHandler.h"
#import <objc/runtime.h>
#import "NSFileHandle+httpServer.h"
#import "SSZipArchive.h"

static NSMutableArray *registeredHandlers = nil;

const static NSDictionary *contentTypeForExtension = nil;
const static NSDictionary *selectorForMethod = nil;



@implementation HTTPResponseHandler
//
// priority
//
// The priority determines which request handlers are given the option to
// handle a request first. The highest number goes first, with the base class
// (HTTPResponseHandler) implementing a 501 error response at priority 0
// (the lowest priorty).
//
// Even if subclasses have a 0 priority, they will always receive precedence
// over the base class, since the base class' implementation is intended as
// an error condition only.
//
// returns the priority.
//
+ (NSUInteger)priority
{
	return 0;
}

//
// load
//
// Implementing the load method and invoking
// [HTTPResponseHandler registerHandler:self] causes HTTPResponseHandler
// to register this class in the list of registered HTTP response handlers.
//
+ (void)load
{
	
	selectorForMethod = @{@"GET": @{@"download": NSStringFromSelector(@selector(dealDownloadFunction:andClientHandle:)),
									@"delete": NSStringFromSelector(@selector(dealDeleteFunction:andClientHandle:)),
									},
						  @"POST": @{@"replace": NSStringFromSelector(@selector(dealReplaceFunction:andClientHandle:)),
									 @"upload": NSStringFromSelector(@selector(dealUploadFunction:andClientHandle:)),
									 }
						  };
	
	contentTypeForExtension = @{@"ini": @"text/plain",
								@"log": @"text/plain",
								@"txt": @"text/plain",
								@"html": @"text/html",
								@"jpg": @"image/jpeg",
								@"png": @"image/png",
								@"gif": @"image/gif",
								@"mp4": @"video/mp4",
								};
	
	[HTTPResponseHandler registerHandler:self];
}

//
// registerHandler:
//
// Inserts the HTTPResponseHandler class into the priority list.
//
+ (void)registerHandler:(Class)handlerClass
{
	if (registeredHandlers == nil)
	{
		registeredHandlers = [[NSMutableArray alloc] init];
	}
	
	NSUInteger i;
	NSUInteger count = [registeredHandlers count];
	for (i = 0; i < count; i++)
	{
		if ([handlerClass priority] >= [[registeredHandlers objectAtIndex:i] priority])
		{
			break;
		}
	}
	[registeredHandlers insertObject:handlerClass atIndex:0];
}
//
// canHandleRequest:method:url:headerFields:
//
// Class method to determine if the response handler class can handle
// a given request.
//
// Parameters:
//    aRequest - the request
//    requestMethod - the request method
//    requestURL - the request URL
//    requestHeaderFields - the request headers
//
// returns YES (if the handler can handle the request), NO (otherwise)
//
+ (BOOL)canHandleRequest:(CFHTTPMessageRef)aRequest
				  method:(NSString *)requestMethod
					 url:(NSURL *)requestURL
			headerFields:(NSDictionary *)requestHeaderFields
{
	return YES;
}
//
// handlerClassForRequest:method:url:headerFields:
//
// Important method to edit for your application.
//
// This method determines (from the HTTP request message, URL and headers)
// which
//
// Parameters:
//    aRequest - the CFHTTPMessageRef, with data at least as far as the end
//		of the headers
//    requestMethod - the request method (GET, POST, PUT, DELETE etc)
//    requestURL - the URL (likely only contains a path)
//    requestHeaderFields - the parsed header fields
//
// returns the class to handle the request, or nil if no handler exists.
//
+ (Class)handlerClassForRequest:(CFHTTPMessageRef)aRequest
						 method:(NSString *)requestMethod
							url:(NSURL *)requestURL
				   headerFields:(NSDictionary *)requestHeaderFields
{
	for (Class handlerClass in registeredHandlers)
	{
		if ([handlerClass canHandleRequest:aRequest
									method:requestMethod
									   url:requestURL
							  headerFields:requestHeaderFields])
		{
			return handlerClass;
		}
	}
	
	return nil;
}

//
// handleRequest:fileHandle:server:
//
// This method parses the request method and header components, invokes
//	+[handlerClassForRequest:method:url:headerFields:] to determine a handler
// class (if any) and creates the handler.
//
// Parameters:
//    aRequest - the CFHTTPMessageRef request requiring a response
//    requestFileHandle - the file handle for the incoming request (still
//		open and possibly receiving data) and for the outgoing response
//    aServer - the server that is invoking us
//
// returns the initialized handler (if one can handle the request) or nil
//	(if no valid handler exists).
//
+ (HTTPResponseHandler *)handlerForRequest:(CFHTTPMessageRef)aRequest
								fileHandle:(NSFileHandle *)requestFileHandle
									server:(HTTPServer *)aServer
{
	NSDictionary *requestHeaderFields =
	(__bridge NSDictionary *)CFHTTPMessageCopyAllHeaderFields(aRequest);
	NSURL *requestURL =
	(__bridge NSURL *)CFHTTPMessageCopyRequestURL(aRequest);
	NSString *method =
	(__bridge NSString *)CFHTTPMessageCopyRequestMethod(aRequest);
	
	Class classForRequest =
	[self handlerClassForRequest:aRequest
						  method:method
							 url:requestURL
					headerFields:requestHeaderFields];
	
	HTTPResponseHandler *handler =
	[[classForRequest alloc]
			initWithRequest:aRequest
			method:method
			url:requestURL
			headerFields:requestHeaderFields
			fileHandle:requestFileHandle
			server:aServer];
	
	return handler;
}

//
// initWithRequest:method:url:headerFields:fileHandle:server:
//
// Init method for the handler. This method is mostly just a value copy operation
// so that the parts of the request don't need to be reparsed.
//
// Parameters:
//    aRequest - the CFHTTPMessageRef
//    method - the request method
//    requestURL - the URL
//    requestHeaderFields - the CFHTTPMessageRef header fields
//    requestFileHandle - the incoming request file handle, also used for
//		the outgoing response.
//    aServer - the server that spawned us
//
// returns the initialized object
//
- (id)initWithRequest:(CFHTTPMessageRef)aRequest
			   method:(NSString *)method
				  url:(NSURL *)requestURL
		 headerFields:(NSDictionary *)requestHeaderFields
		   fileHandle:(NSFileHandle *)requestFileHandle
			   server:(HTTPServer *)aServer
{
	self = [super init];
	if (self != nil)
	{
		request = (__bridge CFHTTPMessageRef)(__bridge id)aRequest;
		requestMethod = method;
		url = requestURL;
		headerFields = requestHeaderFields;
		fileHandle = requestFileHandle;
		server = aServer;
		_fileManager = [[NSFileManager alloc] init];
		
		[[NSNotificationCenter defaultCenter]
			addObserver:self
			selector:@selector(receiveIncomingDataNotification:)
			name:NSFileHandleDataAvailableNotification
			object:fileHandle];
		
		[fileHandle waitForDataInBackgroundAndNotify];
	}
	return self;
}

//
// startResponse
//
// Begin sending a response over the fileHandle. Trivial cases can
// synchronously return a response but everything else should spawn a thread
// or otherwise asynchronously start returning the response data.
//
// THIS IS THE PRIMARY METHOD FOR SUBCLASSES TO OVERRIDE. YOU DO NOT NEED
// TO INVOKE SUPER FOR THIS METHOD.
//
// This method should only be invoked from HTTPServer (it needs to add the
// object to its responseHandlers before this method is invoked).
//
// [server closeHandler:self] should be invoked when done sending data.
//
//
// startResponse
//
// Since this is a simple response, we handle it synchronously by sending
// everything at once.
//
- (void)startResponse
{
//	NSData *fileData =
//	[NSData dataWithContentsOfFile:[HTTPResponseHandler pathForFile]];
//	
//	//test code
//	NSString *str = @"hello world！";
//	fileData = [str dataUsingEncoding:NSUTF8StringEncoding];
//	
//	
//	CFHTTPMessageRef response =
//	CFHTTPMessageCreateResponse(
//								kCFAllocatorDefault, 200, NULL, kCFHTTPVersion1_1);
//	
//	CFHTTPMessageSetHeaderFieldValue(
//									 response, (CFStringRef)@"Content-Type", (CFStringRef)@"text/plain");
//	
//	CFHTTPMessageSetHeaderFieldValue(
//									 response, (CFStringRef)@"Connection", (CFStringRef)@"close");
//	
//	CFHTTPMessageSetHeaderFieldValue(
//									 response,
//									 (CFStringRef)@"Content-Length",
//									 (__bridge CFStringRef)[NSString stringWithFormat:@"%ld", [fileData length]]);
//	
//	CFDataRef headerData = CFHTTPMessageCopySerializedMessage(response);
//	
//	@try
//	{
//		[fileHandle writeData:(__bridge NSData *)headerData];
//		[fileHandle writeData:fileData];
//	}
//	@catch (NSException *exception)
//	{
//		// Ignore the exception, it normally just means the client
//		// closed the connection from the other end.
//	}
//	@finally
//	{
//		CFRelease(headerData);
//		[server closeHandler:self];
//	}
	
	NSError *err = nil;
	NSString *method = fileHandle.method;
	NSString *resource = fileHandle.resource;
	NSString *function = [fileHandle patameterForKey:@"function"];
	NSString *path = [NSHomeDirectory() stringByAppendingPathComponent:fileHandle.resource];
	
	
	NSLog(@"Info: request from:%@ method:%@ function:%@ resource:%@", fileHandle.socketAddress, method, function, resource);
	
	BOOL isDir = NO;
	BOOL pathExist = [_fileManager fileExistsAtPath:path isDirectory:&isDir];
	
	if(pathExist == NO) {
		if([resource isEqualToString:@"/debug"]) {
			err = [self dealDebugRequest:function andClientHandle:fileHandle];
		}else {
			NSString *alert = [NSString stringWithFormat:@"file '%@' not existed!", path];
			err = [NSError errorWithDomain:NSCocoaErrorDomain code:404 userInfo:@{@"alert": alert}];
		}
	}else {
		if(function) {
			NSString *selectorStr = selectorForMethod[method][function];
			if(selectorStr) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
				err = [self performSelector:NSSelectorFromString(selectorStr) withObject:path withObject:fileHandle];
#pragma clang diagnostic pop
			}else {
				NSString *alert = [NSString stringWithFormat:@"no support method '%@' function '%@'!", method, function];
				err = [NSError errorWithDomain:NSCocoaErrorDomain code:503 userInfo:@{@"alert": alert}];
			}
		}else {
			if([method isEqualToString:@"GET"]) {
				if(isDir) {
					err = [self dealShowDirectoryRequest:path andClientHandle:fileHandle];
				}else {
					err = [self dealFileRequest:path andClientHandle:fileHandle];
				}
			}
		}
	}
	
	if(err) {
		[self responseWithStatusCode:err.code andContentStr:err.userInfo[@"alert"] andContentType:@"text/plain" andClientHandle:fileHandle];
	}
	
	
	
}


- (NSError *)dealShowDirectoryRequest:(NSString *)path andClientHandle:(NSFileHandle *)clientHandle
{
	NSError *error = nil;
	NSMutableArray *fileHtmlInfos = [NSMutableArray array];
	NSMutableArray *directoryHtmlInfos = [NSMutableArray array];
	NSArray *allNames = [_fileManager contentsOfDirectoryAtPath:path error:&error];
	NSString *currentPath = path;
	if([currentPath isEqualToString:NSHomeDirectory()]) {
		currentPath = @"/";
	}else {
		currentPath = [currentPath stringByReplacingOccurrencesOfString:NSHomeDirectory() withString:@""];
	}
	
	if(error) {
		return [NSError errorWithDomain:NSCocoaErrorDomain code:503 userInfo:@{@"alert": [NSString stringWithFormat:@"internal error\n%@", error]}];
	}
	
	const static char *sortKey = __func__;
	
	for(NSString *name in allNames) {
		NSString *filePath = [path stringByAppendingPathComponent:name];
		NSDictionary *info = [_fileManager attributesOfItemAtPath:filePath error:nil];
		if(info) {
			NSString *htmlDesc = [HTTPResponseHandler htmlForFileInfo:info andName:name andCurrentPath:currentPath];
			if(htmlDesc) {
				NSString *fileType = info[NSFileType];
				if([fileType isEqualToString:NSFileTypeRegular]) {
					[fileHtmlInfos addObject:htmlDesc];
				}else if([fileType isEqualToString:NSFileTypeDirectory]) {
					[directoryHtmlInfos addObject:htmlDesc];
				}
				
				id sortObj = name;
				objc_setAssociatedObject(htmlDesc, sortKey, sortObj, OBJC_ASSOCIATION_RETAIN);
			}
		}
	}
	
	[fileHtmlInfos sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
		id o1 = objc_getAssociatedObject(obj1, sortKey);
		id o2 = objc_getAssociatedObject(obj2, sortKey);
		return [o1 compare:o2];
	}];
	
	[directoryHtmlInfos sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
		id o1 = objc_getAssociatedObject(obj1, sortKey);
		id o2 = objc_getAssociatedObject(obj2, sortKey);
		return [o1 compare:o2];
	}];
	
	NSMutableArray *contentArray = [NSMutableArray arrayWithArray:directoryHtmlInfos];
	[contentArray addObjectsFromArray:fileHtmlInfos];
	
	NSString *html = [HTTPResponseHandler htmlPageWithTableContent:contentArray andCurrentPath:currentPath];
	[self responseWithStatusCode:200 andContentStr:html andContentType:@"text/html" andClientHandle:clientHandle];
	
	return nil;
}


- (NSError *)dealDebugRequest:(NSString *)function andClientHandle:(NSFileHandle *)clientHandle
{
	NSError *error = nil;
	if([function isEqualToString:@"callstack"]) {
//		NSString *stack = [AppStack allCallStack];
//		[self responseWithStatusCode:200 andContentStr:stack andContentType:@"text/plain" andClientHandle:clientHandle];
	}else if([function isEqualToString:@"uistack"]) {
//		NSString *stack = [AppStack viewStack];
//		[self responseWithStatusCode:200 andContentStr:stack andContentType:@"text/plain" andClientHandle:clientHandle];
	}else if(function == nil) {
		static NSString *html = @"<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">\r\n<html xmlns=\"http://www.w3.org/1999/xhtml\">\r\n<head>\r\n<meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\" />\r\n<title>调试信息</title>\r\n</head>\r\n\r\n<body>\r\n\r\n<br><br>\r\n**text**\r\n\r\n</body>\r\n</html>";
		NSMutableArray *line = [NSMutableArray array];
		[line addObject:@"<div align=\"center\">\r\n<a target=\"_blank\" href=\"/debug?function=callstack\">函数调用栈</a>\r\n</div>"];
		[line addObject:@"<div align=\"center\">\r\n<a target=\"_blank\" href=\"/debug?function=uistack\">UI栈</a>\r\n</div>"];
		NSString *content = [line componentsJoinedByString:@"\r\n<br><br>\r\n"];
		content = [html stringByReplacingOccurrencesOfString:@"**text**" withString:content];
		[self responseWithStatusCode:200 andContentStr:content andContentType:@"text/html" andClientHandle:clientHandle];
	}else {
		error = [NSError errorWithDomain:NSCocoaErrorDomain code:503 userInfo:@{@"alert": [NSString stringWithFormat:@"no support function:%@", function]}];
	}
	
	return error;
}

#pragma mark - tools

+ (NSData *)httpHeaderDataWithStatusCode:(NSInteger)statusCode andContentType:(NSString *)contentType andContentLength:(NSInteger)contentLength andOther:(NSDictionary *)other
{
	CFHTTPMessageRef reponseMsg = CFHTTPMessageCreateResponse(kCFAllocatorDefault, statusCode, NULL, kCFHTTPVersion1_0);
	CFHTTPMessageSetHeaderFieldValue(reponseMsg, (__bridge CFStringRef)@"Connection", (__bridge CFStringRef)@"close");
	if(contentType) {
		CFHTTPMessageSetHeaderFieldValue(reponseMsg, (__bridge CFStringRef)@"Content-Type", (__bridge CFStringRef)contentType);
	}
	
	CFHTTPMessageSetHeaderFieldValue(reponseMsg, (__bridge CFStringRef)@"Content-Length", (__bridge CFStringRef)@(contentLength).stringValue);
	
	[other enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
		NSAssert([key isKindOfClass:[NSString class]] && [obj isKindOfClass:[NSString class]], nil);
		CFHTTPMessageSetHeaderFieldValue(reponseMsg, (__bridge CFStringRef)key, (__bridge CFStringRef)obj);
	}];
	
	CFDataRef headerDataRef = CFHTTPMessageCopySerializedMessage(reponseMsg);
	NSData *headerData = (__bridge_transfer NSData *)headerDataRef;
	CFRelease(reponseMsg);
	
	return headerData;
}

+ (NSString *)htmlForFileInfo:(NSDictionary *)info andName:(NSString *)name andCurrentPath:(NSString *)currentPath
{
	NSString *fileType = info[NSFileType];
	
	if([fileType isEqualToString:NSFileTypeDirectory] == NO
	   && [fileType isEqualToString:NSFileTypeRegular] == NO) {
		return nil;
	}
	
	NSString *(^sizeDescBlock)(int64_t) = ^NSString *(int64_t sizeInt) {
		NSString *sizeStr = nil;
		if(sizeInt >= 1*1024*1024*1024) {
			sizeStr = [NSString stringWithFormat:@"%0.1lfGB", sizeInt*1.0/(1*1024*1024*1024)];
		}else if(sizeInt >= 1*1024*1024) {
			sizeStr = [NSString stringWithFormat:@"%0.1lfMB", sizeInt*1.0/(1*1024*1024)];
		}else if(sizeInt >= 1*1024) {
			sizeStr = [NSString stringWithFormat:@"%0.1lfKB", sizeInt*1.0/(1*1024)];
		}else {
			sizeStr = [NSString stringWithFormat:@"%ldB", (long)sizeInt];
		}
		return sizeStr;
	};
	
	NSDateFormatter *formatter = nil;
	if(formatter == nil) {
		formatter = [[NSDateFormatter alloc] init];
		formatter.timeZone = [NSTimeZone systemTimeZone];
		formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
	}
	
	NSString *dateStr = [formatter stringFromDate:info[NSFileModificationDate]];
	NSString *path = [currentPath stringByAppendingPathComponent:name];
	NSString *sizeStr = [fileType isEqualToString:NSFileTypeRegular]? sizeDescBlock([info[NSFileSize] longLongValue]): @"";
	
	NSString *delUrl = [NSString stringWithFormat:@"%@?function=delete", path];
	NSString *downUrl = [NSString stringWithFormat:@"%@?function=download", path];
	
	static const NSString *oprHtml = @"<a href=\"%@\">%@</a>";
	static const NSString *html = @"<tr>\r\n    <td height=\"30\"><a href=\"%@\">%@</a></td>\r\n    <td><div align=\"center\">%@</div></td>\r\n    <td><div align=\"center\">%@</div></td>\r\n    <td><div align=\"center\">**opr**</div></td>\r\n</tr>";
	
	NSMutableArray *opr = [NSMutableArray array];
	
	if([fileType isEqualToString:NSFileTypeRegular]) {
		[opr addObject:[NSString stringWithFormat:(NSString *)oprHtml, delUrl, @"删除"]];
	} else {
		[opr addObject:[NSString stringWithFormat:(NSString *)oprHtml, downUrl, @"下载"]];
		[opr addObject:[NSString stringWithFormat:(NSString *)oprHtml, delUrl, @"删除"]];
	}
	
	NSString *oprStr = [opr componentsJoinedByString:@" / "];
	NSString *htmlStr = [html stringByReplacingOccurrencesOfString:@"**opr**" withString:oprStr];
	
	NSString *retStr = [NSString stringWithFormat:htmlStr, path, name, dateStr, sizeStr];
	
	return retStr;
}

+ (NSString *)htmlPageWithTableContent:(NSArray *)content andCurrentPath:(NSString *)currentPath
{
	static const NSString *html = @"<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">\r\n<html xmlns=\"http://www.w3.org/1999/xhtml\">\r\n<head>\r\n<meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\" />\r\n<title>文件浏览器</title>\r\n</head>\r\n\r\n<body>\r\n**text**\r\n<table width=\"790\" height=\"30\" border=\"1\" align=\"center\">\r\n  <tr>\r\n    <td width=\"450\" height=\"30\"><div align=\"center\">名称</div></td>\r\n    <td width=\"160\"><div align=\"center\">编辑时间</div></td>\r\n    <td width=\"80\"><div align=\"center\">大小</div></td>\r\n    <td width=\"100\"><div align=\"center\">操作</div></td>\r\n</tr>\r\n**table**\r\n</table>\r\n</body>\r\n</html>";
	
	static const NSString *upload = @"<form action=\"%@\" method=\"post\" enctype =\"multipart/form-data\" runat=\"server\"> \r\n<div align=\"center\">\r\n<input id=\"file\" runat=\"server\" name=\"uploadfile\" type=\"file\" /> \r\n<input type=\"submit\" name=\"upload\" value=\"%@\" id=\"upload\" />\r\n</form>\r\n<form action=\"%@\" method=\"post\" enctype =\"multipart/form-data\" runat=\"server\"> \r\n<input id=\"file\" runat=\"server\" name=\"replace\" type=\"file\" /> \r\n<input type=\"submit\" name=\"replace\" value=\"%@\" id=\"replace\" />\r\n</div>\r\n</form>\r\n";
	
	static const NSString *debug = @"<br>\r\n<div align=\"center\">\r\n<a href=\"/debug\">调试信息</a>\r\n</div>\r\n";
	
	NSString *uploadUrl = [NSString stringWithFormat:@"%@?function=upload", currentPath];
	NSString *replaceUrl = [NSString stringWithFormat:@"%@?function=replace", currentPath];
	NSString *uploadForm = [NSString stringWithFormat:(NSString *)upload, uploadUrl, @"上传文件", replaceUrl, @"替换目录"];
	
	NSString *str = [content componentsJoinedByString:@"\r\n"];
	str = [html stringByReplacingOccurrencesOfString:@"**table**" withString:str];
	
	static const NSString *textPrev = @"<p align=\"center\"><a href=\"%@\">返回上级</a></p>";
	static const NSString *textCurrent = @"<p align=\"center\">当前目录：%@</p>";
	
	NSMutableArray *textArray = [NSMutableArray array];
	[textArray addObject:debug];
	if(currentPath.length > 1) {
		[textArray addObject:[NSString stringWithFormat:(NSString *)textPrev, currentPath.stringByDeletingLastPathComponent]];
	}
	[textArray addObject:[NSString stringWithFormat:(NSString *)textCurrent, currentPath]];
	
	NSString *textStr = [NSString stringWithFormat:@"%@", [textArray componentsJoinedByString:@"\r\n"]];
	if([currentPath isEqualToString:@"/"] == NO
	   && [currentPath hasPrefix:@"/tmp"] == NO) {
		textStr = [NSString stringWithFormat:@"\r\n%@\r\n%@\r\n", uploadForm, textStr];
	}
	str = [str stringByReplacingOccurrencesOfString:@"**text**" withString:textStr];
	
	str = [str stringByReplacingOccurrencesOfString:@"**debug**" withString:(NSString *)debug];
	
	return str;
}


#pragma mark - methodFunction


- (NSError *)dealUploadFunction:(NSString *)path andClientHandle:(NSFileHandle *)clientHandle
{
	NSData *content = clientHandle.receiveFileData;
	NSString *filename = clientHandle.receiveFileName;
	
	if(content && filename && path) {
		
		NSString *filepath = [path stringByAppendingPathComponent:filename];
		[content writeToFile:filepath atomically:YES];
		
		[self responseRedirectToPath:[NSString stringWithFormat:@"./%@", path.lastPathComponent] andClientHandle:clientHandle];
		
		return nil;
	}
	
	return [NSError errorWithDomain:NSCocoaErrorDomain code:503 userInfo:@{@"alert": @"internal error"}];
}

- (NSError *)dealReplaceFunction:(NSString *)path andClientHandle:(NSFileHandle *)clientHandle
{
	NSData *content = clientHandle.receiveFileData;
	NSString *filename = clientHandle.receiveFileName;
	
	if(content && filename && path) {
		if([filename.pathExtension.lowercaseString isEqualToString:@"zip"] == NO) {
			return [NSError errorWithDomain:NSCocoaErrorDomain code:503 userInfo:@{@"alert": @"replace folder only support zip file"}];
		}
		
		if([path isEqualToString:NSHomeDirectory()]) {
			return [NSError errorWithDomain:NSCocoaErrorDomain code:503 userInfo:@{@"alert": @"can't replace root folder"}];
		}
		
		BOOL isDir = NO;
		if([_fileManager fileExistsAtPath:path isDirectory:&isDir] == NO) {
			NSString *alert = [NSString stringWithFormat:@"file '%@' not existed!", path];
			return [NSError errorWithDomain:NSCocoaErrorDomain code:404 userInfo:@{@"alert": alert}];
		} else if(isDir == NO) {
			return [NSError errorWithDomain:NSCocoaErrorDomain code:503 userInfo:@{@"alert": @"replace function noly support folder path"}];
		}
		
		NSError *err = nil;
		NSString *tmpPath =[NSTemporaryDirectory() stringByAppendingPathComponent:path.pathComponents.lastObject];
		if([_fileManager fileExistsAtPath:tmpPath isDirectory:&isDir] && isDir == YES) {
			[_fileManager removeItemAtPath:tmpPath error:&err];
			if(err) {
				return [NSError errorWithDomain:NSCocoaErrorDomain code:503 userInfo:@{@"alert": err.description}];
			}
		}
		[_fileManager createDirectoryAtPath:tmpPath withIntermediateDirectories:YES attributes:nil error:&err];
		if(err) {
			return [NSError errorWithDomain:NSCocoaErrorDomain code:503 userInfo:@{@"alert": err.description}];
		}
		
		NSString *tmpZipPath = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
		[content writeToFile:tmpZipPath atomically:YES];
		
		if(NO == [YHSSZipArchive unzipFileAtPath:tmpZipPath toDestination:tmpPath]) {
			return [NSError errorWithDomain:NSCocoaErrorDomain code:503 userInfo:@{@"alert": @"unzip file failed"}];
		}
		
		[_fileManager removeItemAtPath:tmpZipPath error:nil];
		
		NSString *copyPath = nil;
		NSArray *fileNames = [_fileManager contentsOfDirectoryAtPath:tmpPath error:nil];
		if(fileNames.count > 2) {
			return [NSError errorWithDomain:NSCocoaErrorDomain code:503 userInfo:@{@"alert": @"unzip file exception"}];
		}
		for(NSString *n in fileNames) {
			if([n isEqualToString:@"__MACOSX"] == NO) {
				copyPath = [tmpPath stringByAppendingPathComponent:n];
			}
		}
		
		if(copyPath == nil) {
			return [NSError errorWithDomain:NSCocoaErrorDomain code:503 userInfo:@{@"alert": @"unzip file exception"}];
		}
		
		[_fileManager removeItemAtPath:path error:&err];
		if(err) {
			return [NSError errorWithDomain:NSCocoaErrorDomain code:503 userInfo:@{@"alert": err.description}];
		}
		
		[_fileManager moveItemAtPath:copyPath toPath:path error:&err];
		if(err) {
			return [NSError errorWithDomain:NSCocoaErrorDomain code:503 userInfo:@{@"alert": err.description}];
		}
		
		[_fileManager removeItemAtPath:tmpPath error:nil];
		
		[self responseRedirectToPath:[NSString stringWithFormat:@"./%@", path.lastPathComponent] andClientHandle:clientHandle];
	}
	
	return nil;
}

- (NSError *)dealDownloadFunction:(NSString *)path andClientHandle:(NSFileHandle *)clientHandle
{
	NSError *err = nil;
	BOOL isDir = NO;
	if([_fileManager fileExistsAtPath:path isDirectory:&isDir]) {
		if(isDir) {
			err = [self dealDirectoryRequest:path andClientHandle:clientHandle];
		}else {
			err = [self dealFileRequest:path andClientHandle:clientHandle];
		}
	}else {
		NSString *alert = [NSString stringWithFormat:@"file '%@' not existed!", path];
		err = [NSError errorWithDomain:NSCocoaErrorDomain code:404 userInfo:@{@"alert": alert}];
	}
	
	return err;
}

- (NSError *)dealDeleteFunction:(NSString *)path andClientHandle:(NSFileHandle *)clientHandle
{
	NSError *error = nil;
	if(path.length > 1 && [path rangeOfString:NSHomeDirectory()].location != NSNotFound) {
		if([_fileManager removeItemAtPath:path error:&error]) {
			path = [path stringByDeletingLastPathComponent];
			[self responseRedirectToPath:@"./" andClientHandle:clientHandle];
		}else {
			NSString *reason = [NSString stringWithFormat:@"delete '%@' failed with error: %@", path, error];
			error = [NSError errorWithDomain:NSCocoaErrorDomain code:503 userInfo:@{@"alert": reason}];
		}
	}else {
		NSString *reason = [NSString stringWithFormat:@"can't delete '%@'", path];
		error = [NSError errorWithDomain:NSCocoaErrorDomain code:503 userInfo:@{@"alert": reason}];
	}
	
	return error;
}

- (NSError *)dealFileRequest:(NSString *)path andClientHandle:(NSFileHandle *)clientHandle
{
	[self responseWithConetentPath:path andClientHandle:clientHandle];
	return nil;
}


- (NSError *)dealDirectoryRequest:(NSString *)path andClientHandle:(NSFileHandle *)clientHandle
{
//	NSURL *zipUrl = [MOAZipArchive zipFilesAtPaths:@[path]];
	
	NSString *tempPath = [HTTPResponseHandler pathForFile];
	BOOL success = [YHSSZipArchive createZipFileAtPath:tempPath withFilesAtPaths:@[path]];
	if (! success) {
		return nil;
	}

	[self dealFileRequest:tempPath andClientHandle:clientHandle];
	
	return nil;
}

#pragma mark - send response
- (void)responseRedirectToPath:(NSString *)path andClientHandle:(NSFileHandle *)clientHandle
{
	NSString *locUrl = path;
	NSData *headerData = [HTTPResponseHandler httpHeaderDataWithStatusCode:302 andContentType:nil andContentLength:0 andOther:@{@"Location": locUrl}];
	
	[clientHandle sendData:nil andHeaderData:headerData];
	
	NSLog(@"Info: response %@ redirect to %@", clientHandle.socketAddress, locUrl);
}

- (void)responseWithStatusCode:(NSInteger)statusCode andContentStr:(NSString *)contentStr andContentType:(NSString *)contentType andClientHandle:(NSFileHandle *)clientHandle
{
	NSData *data = nil;
	if(contentStr) {
		data = [contentStr dataUsingEncoding:NSUTF8StringEncoding];
	}
	[self responseWithStatusCode:statusCode andContentData:data andContentType:contentType? contentType: @"text/plain" andClientHandle:clientHandle];
}
- (void)responseWithStatusCode:(NSInteger)statusCode andContentData:(NSData *)contentData andContentType:(NSString *)contentType andClientHandle:(NSFileHandle *)clientHandle
{
	NSAssert(contentType, nil);
	
	NSData *headerData = [HTTPResponseHandler httpHeaderDataWithStatusCode:statusCode andContentType:contentType andContentLength:contentData.length andOther:nil];
	
	[clientHandle sendData:contentData andHeaderData:headerData];
	
	NSLog(@"Info: response %@ statusCode=%ld contentLength=%lu", clientHandle.socketAddress, (long)statusCode, (unsigned long)contentData.length);
	
}

- (void)responseWithConetentPath:(NSString *)contentPath andClientHandle:(NSFileHandle *)clientHandle
{
	if([contentPath isKindOfClass:[NSString class]] == NO) {
		[self responseWithStatusCode:503 andContentStr:@"internal error" andContentType:nil andClientHandle:clientHandle];
		return;
	}
	
	NSError *error = nil;
	NSDictionary *info = [_fileManager attributesOfItemAtPath:contentPath error:&error];
	
	if(error) {
		[self responseWithStatusCode:503 andContentStr:@"internal error" andContentType:nil andClientHandle:clientHandle];
		return;
	}
	//文件类型是否常规文件
	if([info[NSFileType] isEqualToString:NSFileTypeRegular] == NO) {
		[self responseWithStatusCode:503 andContentStr:@"internal error" andContentType:nil andClientHandle:clientHandle];
		return;
	}
	
	NSInteger fileSize = [info[NSFileSize] integerValue];
	NSString *contentType = contentTypeForExtension[contentPath.pathExtension.lowercaseString];
	if(contentType == nil) {
		contentType = @"text/plain";
	}
	
	NSData *header = [HTTPResponseHandler httpHeaderDataWithStatusCode:200 andContentType:contentType andContentLength:fileSize andOther:nil];
	
	[clientHandle sendFile:contentPath andHeaderData:header];
	
	NSLog(@"Info: response %@ statusCode=%ld contentLength=%ld", clientHandle.socketAddress, (long)200, (long)fileSize);
}

#pragma mark - other

//
// pathForFile
//
// In this sample application, the only file returned by the server lives
// at a fixed location, whose path is returned by this method.
//
// returns the path of the text file.
//
+ (NSString *)pathForFile
{
	NSString *path = NSTemporaryDirectory();
	
	BOOL exists = [[NSFileManager defaultManager] fileExistsAtPath:path];
	if (!exists)
	{
		[[NSFileManager defaultManager]
			createDirectoryAtPath:path
			withIntermediateDirectories:YES
			attributes:nil
			error:nil];
	}
	return [path stringByAppendingPathComponent:@"logFile.txt"];
}

//
// endResponse
//
// Closes the outgoing file handle.
//
// You should not invoke this method directly. It should only be invoked from
// HTTPServer (it needs to remove the object from its responseHandlers before
// this method is invoked). To close a reponse handler, use
// [server closeHandler:responseHandler].
//
// Subclasses should stop any other activity when this method is invoked and
// invoke super to close the file handle.
//
// If the connection is persistent, you must set fileHandle to nil (without
// closing the file) to prevent the connection getting closed by this method.
//
- (void)endResponse
{
	if (fileHandle)
	{
		[[NSNotificationCenter defaultCenter]
			removeObserver:self
			name:NSFileHandleDataAvailableNotification
			object:fileHandle];
		[fileHandle closeFile];
		[fileHandle releaseResource];
		fileHandle = nil;
	}
	
	server = nil;
}

//
// receiveIncomingDataNotification:
//
// Continues to receive incoming data for the connection. Remember that the
// first data past the end of the headers may already have been read into
// the request.
//
// Override this method to read the complete HTTP Request Body. This is a
// complicated process if you want to handle both Content-Length and all common
// Transfer-Encodings, so I haven't implemented it.
//
// If you want to handle persistent connections, you would need careful handling
// to determine the end of the request, seek the fileHandle so it points
// to the byte immediately after then end of this request, and then send an
// NSFileHandleConnectionAcceptedNotification notification with the fileHandle
// as the NSFileHandleNotificationFileHandleItem in the userInfo dictionary
// back to the server to handle the fileHandle as a new incoming request again
// (before setting fileHandle to nil so the connection won't get closed when this
// handler ends).
//
// Parameters:
//    notification - notification that more data is available
//
- (void)receiveIncomingDataNotification:(NSNotification *)notification
{
	NSFileHandle *incomingFileHandle = [notification object];
	NSData *data = [incomingFileHandle availableData];
	
	if (!data||[data length] == 0)
	{
		[incomingFileHandle readToEndOfFileInBackgroundAndNotify];
		[server closeHandler:self];
		return;
	}
	
	//
	// This is a default implementation and simply ignores all data.
	// If you need the HTTP body, you need to override this method to continue
	// accumulating data. Don't forget that new data may need to be combined
	// with any HTTP body data that may have already been received in the
	// "request" body.
	//
	
    [incomingFileHandle appendingReceiveData:data];
    if(incomingFileHandle.isHeaderComplete) {
        if(incomingFileHandle.isBodyComplete) {
            [self startResponse];
            return;
        }
    }
    
	[incomingFileHandle waitForDataInBackgroundAndNotify];
}

//
// dealloc
//
// Stops the response if still running.
//
- (void)dealloc
{
	if (server)
	{
		[self endResponse];
	}
	request = nil;
	requestMethod = nil;
	url = nil;
	headerFields = nil;
	
}



@end
