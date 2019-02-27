//
//  NSFileHandle+httpServer.m
//  MOA
//
//  Created by YH on 17/3/11.
//  Copyright © 2015年 moa. All rights reserved.
//

#import "NSFileHandle+httpServer.h"
#include <netinet/in.h>
#include <arpa/inet.h>
#import <objc/runtime.h>

#define TRUNCK_SIZE     (8*1024)

static void WriteStreamClientCallBack(CFWriteStreamRef stream, CFStreamEventType type, void *clientCallBackInfo);

static const char *kSocketAddress = "kSocketAddress";
static const char *kMethod = "kMethod";
static const char *kResource = "kResource";
static const char *kUrlComponents = "kUrlComponents";
static const char *kHttpMessageRef = "kHttpMessageRef";
static const char *kHttpHeaderField = "kHttpHeaderField";
static const char *kBodyData = "kBodyData";

static const char *kReceiveBytes = "kReceiveBytes";
static const char *kHeaderBytes = "kHeaderBytes";
static const char *kIsHeaderComplete = "kIsHeaderComplete";
static const char *kIsBodyComplete = "kIsBodyComplete";
static const char *kFileDataRangeInBody = "kFileDataRangeInBody";
static const char *kReceiveFileName = "kReceiveFileName";

static const char *kWriteStream = "kWriteStream";
static const char *kConnected = "kConnected";
static const char *kSendObjectLength = "kSendObjectLength";
static const char *kSendObjectOffset = "kSendObjectOffset";
static const char *kSendObject = "kSendObject";
static const char *kHeaderData = "kHeaderData";
static const char *kHeaderDataSent = "kHeaderDataSent";

@implementation NSFileHandle (httpServer)

- (NSString *)socketAddress
{
    NSString *_socketAddress = objc_getAssociatedObject(self, kSocketAddress);
    if(_socketAddress) {
        return _socketAddress;
    }
     
    if(self.connected == NO) {
        return nil;
    }
    
    int fd = self.fileDescriptor;
    if(fd < 0) {
        return nil;
    }
    
    struct sockaddr_in cliaddr;
    socklen_t cliaddr_len = sizeof(cliaddr);
    memset(&cliaddr, 0, sizeof(cliaddr));
    
    if(getpeername(fd, (struct sockaddr *)&cliaddr, &cliaddr_len) == 0) {
        char ip[INET6_ADDRSTRLEN];
        memset(ip, 0, sizeof(ip));
        inet_ntop(cliaddr.sin_family, &cliaddr.sin_addr, ip, sizeof(ip));
        _socketAddress = [NSString stringWithFormat:@"%s:%d", ip, ntohs(cliaddr.sin_port)];
    }
    
    objc_setAssociatedObject(self, kSocketAddress, _socketAddress, OBJC_ASSOCIATION_RETAIN);

    return _socketAddress;
}

- (CFHTTPMessageRef)httpMessageRef
{
    CFHTTPMessageRef _httpMessageRef = (__bridge CFHTTPMessageRef)objc_getAssociatedObject(self, kHttpMessageRef);
    if(_httpMessageRef) {
        return _httpMessageRef;
    }
    
    _httpMessageRef = CFHTTPMessageCreateEmpty(kCFAllocatorDefault, YES);
    objc_setAssociatedObject(self, kHttpMessageRef, (__bridge id)_httpMessageRef, OBJC_ASSOCIATION_RETAIN);
    
    return _httpMessageRef;
}

- (NSURLComponents *)urlComponents
{
    NSURLComponents *_urlComponents = objc_getAssociatedObject(self, kUrlComponents);
    if(_urlComponents) {
        return _urlComponents;
    }
    
    NSURL *url = (__bridge_transfer NSURL *)CFHTTPMessageCopyRequestURL(self.httpMessageRef);
    _urlComponents = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:YES];
    objc_setAssociatedObject(self, kUrlComponents, _urlComponents, OBJC_ASSOCIATION_RETAIN);
    return _urlComponents;
}

- (NSString *)method
{
    NSString *_method = objc_getAssociatedObject(self, kMethod);
    if(_method) {
        return _method;
    }
    
    _method = (__bridge_transfer NSString *)CFHTTPMessageCopyRequestMethod(self.httpMessageRef);
    objc_setAssociatedObject(self, kMethod, _method, OBJC_ASSOCIATION_RETAIN);
    return _method;
}

- (NSString *)resource
{
    NSString *_resource = objc_getAssociatedObject(self, kResource);
    if(_resource) {
        return _resource;
    }
    
    _resource = self.urlComponents.URL.path;
    objc_setAssociatedObject(self, kResource, _resource, OBJC_ASSOCIATION_RETAIN);
    return _resource;
}

- (NSString *)patameterForKey:(NSString *)key
{
    if([self.urlComponents respondsToSelector:@selector(queryItems)]) {
        for(NSURLQueryItem *item in self.urlComponents.queryItems) {
            if([item.name isEqualToString:key]) {
                return item.value;
            }
        }
    }else {
        NSString *queryStr = self.urlComponents.query;
        NSArray *components = [queryStr componentsSeparatedByString:@"&"];
        for(NSString *str in components) {
            NSArray *components = [str componentsSeparatedByString:@"="];
            if(components.count == 2) {
                if([components.firstObject isEqualToString:key]) {
                    return components.lastObject;
                }
            }
        }
    }
    
    return nil;
}

- (NSDictionary *)headerField
{
    NSDictionary *ret = objc_getAssociatedObject(self, kHttpHeaderField);
    if(ret) {
        return ret;
    }
    
    if(CFHTTPMessageIsHeaderComplete(self.httpMessageRef)) {
        ret = (__bridge_transfer NSDictionary *)CFHTTPMessageCopyAllHeaderFields(self.httpMessageRef);
        objc_setAssociatedObject(self, kHttpHeaderField, ret, OBJC_ASSOCIATION_RETAIN);
    }
    
    return ret;
}

- (NSMutableData *)bodyData
{
    NSMutableData *data = objc_getAssociatedObject(self, kBodyData);
    NSAssert(data == nil || [data isKindOfClass:[NSMutableData class]], nil);
    
    if(data == nil) {
        data = [NSMutableData data];
        objc_setAssociatedObject(self, kBodyData, data, OBJC_ASSOCIATION_RETAIN);
    }
    
    return data;
}

- (NSInteger)headerBytes
{
    return [objc_getAssociatedObject(self, kHeaderBytes) integerValue];
}

- (void)setHeaderBytes:(NSInteger)headerBytes
{
    objc_setAssociatedObject(self, kHeaderBytes, @(headerBytes), OBJC_ASSOCIATION_RETAIN);
}

- (NSInteger)receiveBytes
{
    return [objc_getAssociatedObject(self, kReceiveBytes) integerValue];
}

- (void)setReceiveBytes:(NSInteger)receiveBytes
{
    objc_setAssociatedObject(self, kReceiveBytes, @(receiveBytes), OBJC_ASSOCIATION_RETAIN);
}

- (NSData *)headerData
{
    return objc_getAssociatedObject(self, kHeaderData);
}

- (void)setHeaderData:(NSData *)headerData
{
    objc_setAssociatedObject(self, kHeaderData, headerData, OBJC_ASSOCIATION_RETAIN);
}

- (BOOL)isHeaderComplete
{
    BOOL ret = [objc_getAssociatedObject(self, kIsHeaderComplete) boolValue];
    if(ret) {
        return YES;
    }
    
    if(CFHTTPMessageIsHeaderComplete(self.httpMessageRef)) {
        objc_setAssociatedObject(self, kIsHeaderComplete, @YES, OBJC_ASSOCIATION_RETAIN);
        return YES;
    }
    
    return NO;
}

- (BOOL)isBodyComplete
{
    BOOL ret = [objc_getAssociatedObject(self, kIsBodyComplete) boolValue];
    if(ret) {
        NSAssert(self.bodyData.length == self.receiveBytes-self.headerBytes, nil);
        return YES;
    }
    
    if(self.isHeaderComplete) {
        NSInteger contentLength = [self.headerField[@"Content-Length"] integerValue];
        if(self.receiveBytes >= contentLength + self.headerBytes) {
            NSAssert(self.receiveBytes == contentLength+self.headerBytes, nil);
            objc_setAssociatedObject(self, kIsBodyComplete, @YES, OBJC_ASSOCIATION_RETAIN);
            NSAssert(self.bodyData.length == self.receiveBytes-self.headerBytes, nil);
            [self parseBody];
            return YES;
        }
    }
    
    return NO;
}

- (void)parseBody
{
    NSString *seperateLine = nil;
    NSString *dispostion = nil;
    NSInteger fileDataLocation = -1;
    NSInteger fileDataEndLocation = -1;
    
    NSData *body = self.bodyData;
    NSInteger currentLine = 0;
    
    if(body.length == 0) {
        return;
    }
    
    NSData *lineData = [NSData dataWithBytes:"\r\n" length:2];
    NSRange tmpRange = NSMakeRange(0, 0);
    while(1) {
        NSRange range = NSMakeRange(tmpRange.location+tmpRange.length, body.length-tmpRange.location-tmpRange.length);
        tmpRange = [body rangeOfData:lineData options:0 range:range];
        if(tmpRange.location == NSNotFound) {
            NSAssert(0, nil);
            return;
        }
        
        NSData *tmpData = [body subdataWithRange:NSMakeRange(range.location, tmpRange.location-range.location)];
        NSString *tmpStr = [[NSString alloc] initWithData:tmpData encoding:NSUTF8StringEncoding];
        if(tmpStr == nil) {
            NSAssert(0, nil);
            return;
        }
        
        if(currentLine == 0) {
            seperateLine = tmpStr;
        }else {
            if([tmpStr rangeOfString:@"Content-Disposition"].location == 0) {
                dispostion = tmpStr;
            }else if(tmpStr.length == 0) {
                fileDataLocation = tmpRange.location+tmpRange.length;
                break;
            }
        }
        
        currentLine++;
    }
    
    NSAssert(seperateLine.length && dispostion.length && fileDataLocation > 0, nil);
    
    currentLine = 0;
    tmpRange = NSMakeRange(body.length, 0);
    while(1) {
        NSRange range = NSMakeRange(fileDataLocation, body.length-fileDataLocation-(body.length-tmpRange.location));
        tmpRange = [body rangeOfData:[seperateLine dataUsingEncoding:NSUTF8StringEncoding] options:NSDataSearchBackwards range:range];
        if(++currentLine == 2) {
            fileDataEndLocation = tmpRange.location;
            break;
        }
    }
    
    if(fileDataLocation > fileDataEndLocation) {
        NSAssert(0, nil);
        return;
    }
    //这里多了两个字节，要减去（\r\n）
    objc_setAssociatedObject(self, kFileDataRangeInBody, [NSValue valueWithRange:NSMakeRange(fileDataLocation, fileDataEndLocation-fileDataLocation-2)], OBJC_ASSOCIATION_RETAIN);
    
    tmpRange = [dispostion rangeOfString:@"filename=\""];
    if(tmpRange.location == NSNotFound) {
        NSAssert(0, nil);
        return;
    }
    
    dispostion = [dispostion substringFromIndex:tmpRange.location+tmpRange.length];
    tmpRange = [dispostion rangeOfString:@"\""];
    if(tmpRange.location == NSNotFound) {
        NSAssert(0, nil);
        return;
    }
    
    NSString *fileName = [dispostion substringToIndex:tmpRange.location];
    if(fileName == nil) {
        NSAssert(0, nil);
        return;
    }
    
    objc_setAssociatedObject(self, kReceiveFileName, fileName, OBJC_ASSOCIATION_RETAIN);
}

- (NSData *)receiveFileData
{
    NSRange range = self.fileDataRangeInBody;
    if(range.location == NSNotFound) {
        return nil;
    }
    
    return [self.bodyData subdataWithRange:range];
}

- (NSRange)fileDataRangeInBody
{
    if(self.isBodyComplete == NO) {
        NSAssert(0, nil);
        return NSMakeRange(NSNotFound, 0);
    }
    
    NSValue *value = objc_getAssociatedObject(self, kFileDataRangeInBody);
    return value.rangeValue;
}

- (NSString *)receiveFileName
{
    if(self.isBodyComplete == NO) {
        NSAssert(0, nil);
        return nil;
    }
    
    NSString *name = objc_getAssociatedObject(self, kReceiveFileName);
    if(name == nil) {
        objc_setAssociatedObject(self, kReceiveFileName, name, OBJC_ASSOCIATION_RETAIN);
    }
    
    return name;
}

- (BOOL)headerDataSent
{
    return [objc_getAssociatedObject(self, kHeaderDataSent) boolValue];
}

- (void)setHeaderDataSent:(BOOL)headerDataSent
{
    objc_setAssociatedObject(self, kHeaderDataSent, @(headerDataSent), OBJC_ASSOCIATION_RETAIN);
}

- (BOOL)connected
{
    return [objc_getAssociatedObject(self, kConnected) boolValue];
}

- (void)setConnected:(BOOL)connected
{
    objc_setAssociatedObject(self, kConnected, @(connected), OBJC_ASSOCIATION_RETAIN);
}

- (NSOutputStream *)writeStream
{
    return objc_getAssociatedObject(self, kWriteStream);
}

- (void)setWriteStream:(NSOutputStream *)writeStream
{
    objc_setAssociatedObject(self, kWriteStream, writeStream, OBJC_ASSOCIATION_RETAIN);
}

- (NSInteger)sendObjectLength
{
    return [objc_getAssociatedObject(self, kSendObjectLength) integerValue];
}

- (void)setSendObjectLength:(NSInteger)sendObjectLength
{
    objc_setAssociatedObject(self, kSendObjectLength, @(sendObjectLength), OBJC_ASSOCIATION_RETAIN);
}

- (NSInteger)sendObjectOffset
{
    return [objc_getAssociatedObject(self, kSendObjectOffset) integerValue];
}

- (void)setSendObjectOffset:(NSInteger)sendObjectOffset
{
    objc_setAssociatedObject(self, kSendObjectOffset, @(sendObjectOffset), OBJC_ASSOCIATION_RETAIN);
}

- (id)sendObject
{
    return objc_getAssociatedObject(self, kSendObject);
}

- (void)setSendObject:(id)sendObject
{
    NSAssert(self.sendObject == nil, nil);
    objc_setAssociatedObject(self, kSendObject, sendObject, OBJC_ASSOCIATION_RETAIN);
    
    if([sendObject isKindOfClass:[NSFileHandle class]]) {
        NSFileHandle *fileHandle = sendObject;
        [fileHandle seekToEndOfFile];
        self.sendObjectLength = fileHandle.offsetInFile;
        [fileHandle seekToFileOffset:0];
    }else if([sendObject isKindOfClass:[NSData class]]) {
        self.sendObjectLength = [sendObject length];
    }
    
    self.sendObjectOffset = 0;
}

- (void)appendingReceiveData:(NSData *)data
{
    if(data.length) {
        CFHTTPMessageRef msgRef = self.httpMessageRef;
        
        if(self.isHeaderComplete) {
            [self.bodyData appendData:data];
        }else {
            CFHTTPMessageAppendBytes(msgRef, data.bytes, data.length);
        }
        
        self.receiveBytes = self.receiveBytes + data.length;
        
        if(self.isHeaderComplete) {
            if(self.headerBytes == 0) {
                static const char *completeFlag = "\r\n\r\n";
                NSData *flagData = [NSData dataWithBytes:(void *)completeFlag length:strlen(completeFlag)];
                NSRange range = [data rangeOfData:flagData options:0 range:NSMakeRange(0, data.length)];
                if(range.location != NSNotFound) {
                    self.headerBytes = range.location + range.length;
                }else {
                    self.headerBytes = data.length;
                }
                if(self.headerBytes < data.length) {
                    NSData *bodyData = [data subdataWithRange:NSMakeRange(self.headerBytes, data.length-self.headerBytes)];
                    [self.bodyData appendData:bodyData];
                }
            }
        }
    }
}

- (BOOL)rollbackData:(NSInteger)length
{
    NSInteger nowOffset = self.sendObjectOffset - length;
//    NSAssertRet(NO, nowOffset >= 0 && nowOffset < self.sendObjectLength, nil);
	
    id _sendObject = self.sendObject;
    
    if([_sendObject isKindOfClass:[NSFileHandle class]]) {
        NSFileHandle *file = _sendObject;
        [file seekToFileOffset:nowOffset];
    }
    
    self.sendObjectOffset = nowOffset;
    
    return YES;
}

- (NSData *)getSendData:(NSInteger)length
{
    NSData *data = nil;
    id _sendObject = self.sendObject;
    NSInteger _sendObjectOffset = self.sendObjectOffset;
    NSInteger _sendObjectLength = self.sendObjectLength;
    
    if([_sendObject isKindOfClass:[NSFileHandle class]]) {
        NSFileHandle *file = _sendObject;
        data = [file readDataOfLength:length];
    }else if([_sendObject isKindOfClass:[NSData class]]) {
        if(_sendObjectOffset + length > _sendObjectLength) {
            length = _sendObjectLength - _sendObjectOffset;
        }
        data = [_sendObject subdataWithRange:NSMakeRange(_sendObjectOffset, length)];
    }else {
        NSAssert(_sendObject == nil, nil);
    }
    
    self.sendObjectOffset += data.length;
    
    return data;
}

- (void)sendFile:(NSString *)path andHeaderData:(NSData *)headerData
{
    CFWriteStreamRef writeStream = NULL;
    CFStreamCreatePairWithSocket(kCFAllocatorDefault, self.fileDescriptor, NULL, &writeStream);
    if(writeStream == NULL) {
        NSLog(@"Warn: CFStreamCreatePairWithSocket failed");
        return;
    }
    
    if(!CFWriteStreamOpen(writeStream))
    {
        NSLog(@"Warn: CFWriteStreamOpen");
        return;
    }
    
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:path];
    self.sendObject = fileHandle;
    self.headerData = headerData;
    self.writeStream = (__bridge_transfer NSOutputStream *)writeStream;
    
    CFStreamClientContext ctx = {0, (__bridge void *)(self), NULL, NULL, NULL};
	//将客户端分配给流，在发生特定事件时接收回调。
    CFWriteStreamSetClient(writeStream, kCFStreamEventErrorOccurred|kCFStreamEventEndEncountered|kCFStreamEventCanAcceptBytes, WriteStreamClientCallBack, &ctx);
    CFWriteStreamScheduleWithRunLoop(writeStream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
}

- (void)sendData:(NSData *)contentData andHeaderData:(NSData *)headerData
{
    CFWriteStreamRef writeStream = NULL;
    CFStreamCreatePairWithSocket(kCFAllocatorDefault, self.fileDescriptor, NULL, &writeStream);
    if(writeStream == NULL) {
        NSLog(@"Warn: CFStreamCreatePairWithSocket failed");
        return;
    }
    
    if(!CFWriteStreamOpen(writeStream))
    {
        NSLog(@"Warn: CFWriteStreamOpen");
        return;
    }
    
    self.sendObject = contentData;
    self.headerData = headerData;
    self.writeStream = (__bridge_transfer NSOutputStream *)writeStream;
    
    CFStreamClientContext ctx = {0, (__bridge void *)(self), NULL, NULL, NULL};
	//将客户端分配给流，在发生特定事件时接收回调。
    CFWriteStreamSetClient(writeStream, kCFStreamEventErrorOccurred|kCFStreamEventEndEncountered|kCFStreamEventCanAcceptBytes, WriteStreamClientCallBack, &ctx);
	//将流加入runloop中
    CFWriteStreamScheduleWithRunLoop(writeStream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
}

- (void)releaseResource
{
    CFHTTPMessageRef _httpMessageRef = self.httpMessageRef;
    if(_httpMessageRef) {
        CFRelease(_httpMessageRef);
    }
    [self.writeStream close];
}

@end

static void WriteStreamClientCallBack(CFWriteStreamRef stream, CFStreamEventType type, void *clientCallBackInfo)
{
    NSFileHandle *fileHandle = (__bridge NSFileHandle *)clientCallBackInfo;
    
    switch(type) {
        case kCFStreamEventCanAcceptBytes:
        {
            NSData *headerData = fileHandle.headerData;
            if(headerData.length && fileHandle.headerDataSent == NO) {
                NSLog(@"Info: send header to %@ (%lu)", fileHandle.socketAddress, (unsigned long)headerData.length);
                CFWriteStreamWrite(stream, headerData.bytes, headerData.length);
                fileHandle.headerDataSent = YES;
            }else {
                NSData *data = [fileHandle getSendData:TRUNCK_SIZE];
                if(data.length) {
                    CFIndex writeBytes = CFWriteStreamWrite(stream, data.bytes, data.length);
                    if(writeBytes < 0 || writeBytes != data.length) {
                        NSLog(@"Info: http sever CFWriteStreamWrite %d", (int)writeBytes);
                        if(writeBytes < 0) {
                            [fileHandle setSendObjectOffset:0];
                        }else if(writeBytes != data.length) {
                            [fileHandle rollbackData:data.length - writeBytes];
                        }
                    }
                    NSLog(@"Info: send file to %@ (%ld/%ld)", fileHandle.socketAddress, (long)fileHandle.sendObjectOffset, (long)fileHandle.sendObjectLength);
                }else {
                    NSLog(@"Info: send file to %@ ended", fileHandle.socketAddress);
                }
            }
        }
            break;
        case kCFStreamEventErrorOccurred:
            NSLog(@"kCFStreamEventErrorOccurred");
            break;
        case kCFStreamEventEndEncountered:
            NSLog(@"kCFStreamEventErrorOccurred");
            break;
        default:
            NSLog(@"WriteStreamClientCallBack default");
            break;
    }
}
