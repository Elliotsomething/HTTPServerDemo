//
//  NSFileHandle+httpServer.h
//  MOA
//
//  Created by YH on 17/3/11.
//  Copyright © 2015年 moa. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSFileHandle (httpServer)

@property (nonatomic, readonly) NSString *socketAddress;
@property (nonatomic, readonly) NSString *method;
@property (nonatomic, readonly) NSString *resource;
@property (nonatomic, readonly) NSURLComponents *urlComponents;
@property (nonatomic, readonly) CFHTTPMessageRef httpMessageRef;
@property (nonatomic, readonly) NSDictionary *headerField;
@property (nonatomic, readonly) NSMutableData *bodyData;
@property (nonatomic, readonly) NSInteger receiveBytes;
@property (nonatomic, readonly) NSInteger headerBytes;
@property (nonatomic, readonly) BOOL isHeaderComplete;
@property (nonatomic, readonly) BOOL isBodyComplete;
@property (nonatomic, readonly) NSRange fileDataRangeInBody;
@property (nonatomic, readonly) NSString *receiveFileName;
@property (nonatomic, readonly) NSData *receiveFileData;
@property (nonatomic, readonly) NSOutputStream *writeStream;

@property (nonatomic, assign) BOOL connected;

@property (nonatomic, assign) NSInteger sendObjectLength;
@property (nonatomic, assign) NSInteger sendObjectOffset;
@property (nonatomic, strong) id sendObject;

@property (nonatomic, strong) NSData *headerData;
@property (nonatomic, assign) BOOL headerDataSent;

- (void)appendingReceiveData:(NSData *)data;

- (NSString *)patameterForKey:(NSString *)key;
- (NSData *)getSendData:(NSInteger)length;

- (void)sendFile:(NSString *)path andHeaderData:(NSData *)headerData;
- (void)sendData:(NSData *)contentData andHeaderData:(NSData *)headerData;

- (void)releaseResource;

@end
