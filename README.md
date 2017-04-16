**版权声明：本文为博主原创文章，未经博主允许不得转载；如需转载，请保持原文链接。**

### iOS日志上传很简单(一)搭建简易的HTTP服务器

首先我们来搭建一个简易的HTTP服务器，用于APP端的文件下载，这样做的目的是方便开发人员查看日志；做完之后的结果是，只要知道APP端的ip，就能够查看其日志，这样是不是方便（很恐怖:),幸好我是有职业道德的，只用来看日志）；

当程序运行的时候，会在8088端口运行一个HTTP服务，你只需要在浏览器输入APP端的IP地址加上8088端口号，就可以访问日志文件的内容（或者下载文件）。

#### 简述
在APP端创建一个`socket`，作为`server`端监听8088端口；当有客户端接入进来的时候，检测数据可用性，当确认请求正确后，返回响应数据（也就是文件内容），完成之后关闭接口，这样一个简易的`HTTP`服务器就完成了；

#### 详细步骤
新建一个单例类，`HTTPServer`类基于`NSObjetct`，用于管理`socket`端口连接和客户端的请求处理；

```objective_c
+ (HTTPServer *)sharedHTTPServer
{
	static HTTPServer * httpServer;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		httpServer = [[HTTPServer alloc]init];
	});
	return httpServer;
}
```

新建一个`start`函数，在`start`函数中创建一个`socket`端口，然后创建文件句柄，添加连接监听；如果想要详细了解`socket`的话，可以看下我的[这篇文章](https://elliotsomething.github.io/2015/08/29/iOS-%E4%B9%8B-Socket%E5%AD%A6%E4%B9%A0%E7%AC%94%E8%AE%B0/)，这里不做详细介绍，有注释应该都能看懂了;

```objective_c
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
```
上面的代码创建了一个`socket`套接字，并将8088作为端口；
接下来是使用该`socket`作为文件描述符，创建一个文件句柄并打开连接：

```objective_c
	//使用socket作为fileDescriptor为套接字创建文件句柄。需要手动关闭
	listeningHandle = [[NSFileHandle alloc]initWithFileDescriptor:fileDescriptor closeOnDealloc:YES];
	//在后台接受套接字连接（仅适用于流式套接字），并为通信通道的“近”（客户端）端创建文件句柄。
	[listeningHandle acceptConnectionInBackgroundAndNotify];
```
然后加入监听，当有客户端连接8088端口的时候，进入监听函数，然后去处理请求数据：

```objective_c
	//有客户端连接进来的监听函数（也可以是上面CFSocketCreate创建的回调函数）
	[[NSNotificationCenter defaultCenter]
		addObserver:self
		selector:@selector(receiveIncomingConnectionNotification:)
		name:NSFileHandleConnectionAcceptedNotification
		object:nil];

-(void)receiveIncomingConnectionNotification:(NSNotification *)notification
{
	//todo
}
```
当然有`start`函数就要有`stop`函数，用来结束`socket`连接

```objective_c
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

	if (socket)
	{
		CFSocketInvalidate(socket);
		CFRelease(socket);
		socket = nil;
	}

}
```
然后在`viewController`里面或者你随意的其他地方调用

```objective_c
[[HTTPServer sharedHTTPServer] start];
```

到这里前期的工作就基本完成了，你可以试一下在监听函数打个断点，从pc端输入`127.0.0.1:8088`，看下会不会跑进监听函数，如果能进入监听函数，说明你已经成功了一大半了；

接下来就是处理请求，然后返回响应数据了；一般来说客户端的请求`method`是`get`，解析参数比较简单，所以解析请求参数之后就可以返回对应的数据了；首先写一个简单的；当客户端请求成功之后，会进入上面所说的回调中，我们在那个方法里面处理请求参数

```objective_c
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
```
当客户端接入`socket`的时候会生成一个用于接受数据的文件句柄，如果该`FileHandle`存在时，添加接受可用数据的监听，并在监听中处理可用的请求数据并返回响应数据

```objective_c
- (void)receiveIncomingDataNotification:(NSNotification *)notification
{
	//todo
}
```
此时我们不妨新建一个专门用于管理响应数据的类`HTTPResponseHandler`，包括初始化响应数据，返回响应数据，结束响应数据以及关闭通道；

首先初始化对象，并加入了通道数据可用监听，主要用来之后的关闭通道

```objective_c
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

		[[NSNotificationCenter defaultCenter]
			addObserver:self
			selector:@selector(receiveIncomingDataNotification:)
			name:NSFileHandleDataAvailableNotification
			object:fileHandle];

		[fileHandle waitForDataInBackgroundAndNotify];
	}
	return self;
}
```

接下来是处理响应数据，这里主要是一些`CFHTTPMessageRef`对象的数据封装，并将其写入通道；`CFNetWork`对象的讲解这里不做解释，大家不熟悉的可以去看看文档。

```objective_c
- (void)startResponse
{
	NSData *fileData =
	[NSData dataWithContentsOfFile:[HTTPResponseHandler pathForFile]];
	//test code
	NSString *str = @"hello world！";
	fileData = [str dataUsingEncoding:NSUTF8StringEncoding];
	CFHTTPMessageRef response =
	CFHTTPMessageCreateResponse(
								kCFAllocatorDefault, 200, NULL, kCFHTTPVersion1_1);
	CFHTTPMessageSetHeaderFieldValue(
									 response, (CFStringRef)@"Content-Type", (CFStringRef)@"text/plain");
	CFHTTPMessageSetHeaderFieldValue(
									 response, (CFStringRef)@"Connection", (CFStringRef)@"close");
	CFHTTPMessageSetHeaderFieldValue(
									 response,
									 (CFStringRef)@"Content-Length",
									 (__bridge CFStringRef)[NSString stringWithFormat:@"%ld", [fileData length]]);
	CFDataRef headerData = CFHTTPMessageCopySerializedMessage(response);
	@try
	{
		[fileHandle writeData:(__bridge NSData *)headerData];
		[fileHandle writeData:fileData];
	}
	@catch (NSException *exception)
	{
		// Ignore the exception, it normally just means the client
		// closed the connection from the other end.
	}
	@finally
	{
		CFRelease(headerData);
		[server closeHandler:self];
	}
}
```
最后是结束响应了，代码没什么，就是移除监听，关闭通道等

```objective_c
- (void)receiveIncomingDataNotification:(NSNotification *)notification
{
	NSFileHandle *incomingFileHandle = [notification object];
	NSData *data = [incomingFileHandle availableData];

	if ([data length] == 0)
	{
		[server closeHandler:self];
	}
	[incomingFileHandle waitForDataInBackgroundAndNotify];
}

- (void)endResponse
{
	if (fileHandle)
	{
		[[NSNotificationCenter defaultCenter]
			removeObserver:self
			name:NSFileHandleDataAvailableNotification
			object:fileHandle];
		[fileHandle closeFile];
		fileHandle = nil;
	}
	server = nil;
}
```

好了，`HTTPResponseHandler`类的响应数据基本就这样处理完了，一些细节方面的大家可以看下我的demo，到时候别忘记`star`一下哈；

接下来就是在原来的`HTTPServer`类中的数据监听函数中，调用`HTTPResponseHandler`响应数据的方法

```objective_c
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
	/*此函数将由newBytes指定的数据附加到通过调用CFHTTPMessageCreateEmpty创建的指定消息对象。数据是从客户端或服务器接收的传入的串行
	化HTTP请求或响应。在附加数据时，此函数对其进行反序列化，删除消息可能包含的任何基于HTTP的格式，并将消息存储在消息对象中。然后，您可以分别
	调用CFHTTPMessageCopyVersion，CFHTTPMessageCopyBody，CFHTTPMessageCopyHeaderFieldValue
	和CFHTTPMessageCopyAllHeaderFields来获取消息的HTTP版本，消息的正文，特定的头字段和所有的消息头。
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
```

最后移除监听关闭通道

```objective_c
- (void)closeHandler:(HTTPResponseHandler *)aHandler
{
	[aHandler endResponse];
	[responseHandlers removeObject:aHandler];
}
```

至此整个demo基本就完成了，完成的效果是这样的
<img src="https://Elliotsomething.GitHub.io/images/post-HTTPServer-demo-01.png">

#### 总结
通过该`HTTPServerdemo`你可以学到的技术有`CFSocket`，`kvo`，`NSFileHandle`，以及`CFHTTPMessage`等一些其他`CFNetwork`框架中的知识；
该demo主要是用来访问APP端沙箱中的一些文件数据等，你可以用它来查看日志文件，或者一些用户数据；

下一篇会继续讲`HTTPServer`的进阶篇，具体的去处理get请求参数；

### iOS日志上传很简单(二)搭建HTTPServer升级篇

上一篇介绍了一下怎么搭建一个简易的HttpServer，也就是直接在客户端上通过IP加上端口号直接访问APP的沙箱文件内容；
没看过的可以移步看一下[搭建简易HTTPServer](https://elliotsomething.github.io/2017/02/25/%E6%97%A5%E5%BF%97%E4%B8%8A%E4%BC%A0%E5%BE%88%E7%AE%80%E5%8D%95(%E4%B8%80)%E6%90%AD%E5%BB%BA%E7%AE%80%E6%98%93%E7%9A%84HTTP%E6%9C%8D%E5%8A%A1%E5%99%A8/);

#### 概述

这一篇作为进阶篇，也就是在上一篇的基础上加一些复杂的逻辑，比如文件的上传、下载、删除等；

实现的大概思路很简单，只是实现稍微复杂

1. 首先客户端发起请求，也就是IP地址加端口号（这个在上一篇已经讲过了）
2. 服务端返回响应数据，这个上一篇基本也讲了，不同的是服务端返回的数据是一个网页，其中包含APP的沙箱文件列表，以及一些操作按钮
3. 客户端点击操作按钮，比如下载、删除等
4. 服务端接收数据，处理客户端请求，比如method=upload，并返回响应数据

基本就是这样一个实现思路，其中比较难处理的是第二步，和第四步；不过整体思路理解了还是不难实现的，只是时间问题而已

#### 具体实现

首先第一步客户端发起请求，这个忽略；我们从第二步开始讲起；

**服务端返回网页数据**
服务端返回数据，这个在上一篇的响应数据已经讲了，接下来只要把响应的数据替换为网页数据即可；

代码如下：

```objective_c
static const NSString *html = @"<!DOCTYPE html PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\"
 \"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd\">\r\n<html
  xmlns=\"http://www.w3.org/1999/xhtml\">\r\n<head>\r\n<meta http-equiv=\"Content-Type\" content=\"text/html;
   charset=utf-8\" />\r\n<title>文件浏览器</title>\r\n</head>\r\n\r\n<body>\r\n**text**\r\n<table width=\"790\"
    height=\"30\" border=\"1\" align=\"center\">\r\n  <tr>\r\n    <td width=\"450\" height=\"30\"><div
     align=\"center\">名称</div></td>\r\n    <td width=\"160\"><div align=\"center\">编辑时间</div></td>\r\n    <td
      width=\"80\"><div align=\"center\">大小</div></td>\r\n    <td width=\"100\"><div align=\"center\">
      操作</div></td>\r\n</tr>\r\n**table**\r\n</table>\r\n</body>\r\n</html>";
```
上面的代码是返回一个基本的网页，这种简单的html就不讲了；

但是只是返回一个基本网页是不够的，我们还需要在网页里面能够点击操作，所以我加了一个简单的form表单，然后加了上传、替换、下载、删除四个提交表单方法；

代码如下

```objective_c
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

static const NSString *upload = @"<form action=\"%@\" method=\"post\" enctype =\"multipart/form-data\" runat=\"server\"> \r\n<div align=\"center\">\r\n<input id=\"file\" runat=\"server\" name=\"uploadfile\" type=\"file\" /> \r\n<input type=\"submit\" name=\"upload\" value=\"%@\" id=\"upload\" />\r\n</form>\r\n<form action=\"%@\" method=\"post\" enctype =\"multipart/form-data\" runat=\"server\"> \r\n<input id=\"file\" runat=\"server\" name=\"replace\" type=\"file\" /> \r\n<input type=\"submit\" name=\"replace\" value=\"%@\" id=\"replace\" />\r\n</div>\r\n</form>\r\n";
NSString *uploadUrl = [NSString stringWithFormat:@"%@?function=upload", currentPath];
NSString *replaceUrl = [NSString stringWithFormat:@"%@?function=replace", currentPath];
NSString *uploadForm = [NSString stringWithFormat:(NSString *)upload, uploadUrl, @"上传文件", replaceUrl, @"替换目录"];

NSString *str = [content componentsJoinedByString:@"\r\n"];
str = [html stringByReplacingOccurrencesOfString:@"**table**" withString:str];
```
上面的代码就是组合四个form提交表单方法，基本的html知识即可看懂，这里也不细讲；当我们把这些数据返回给客户端之后，基本这一步就完成了；

**客户端点击操作按钮，发起下载，删除等请求**

客户端点击操作按钮，发起请求，其实就是html的表单提交，只要懂html就能理解，我们在上一步的时候已经把这个一步的步骤都完成了，HTTPServer返回的html表单包含了4个方法，只需要在客户端点击相应的方法发起请求即可；

**服务端处理下载、删除的请求，返回响应数据**

HTTPServer处理请求，返回响应数据，这里同样也是和前面一样，只是稍微加几个if的条件判断，然后分别处理不同的请求，然后返回不同的响应数据就搞定了

首先我们需要分别定义四个处理表单请求的方法

```objective_c
selectorForMethod = @{@"GET": @{@"download": NSStringFromSelector(@selector(dealDownloadFunction:andClientHandle:)),
@"delete": NSStringFromSelector(@selector(dealDeleteFunction:andClientHandle:)),},
@"POST": @{@"replace": NSStringFromSelector(@selector(dealReplaceFunction:andClientHandle:)),
@"upload": NSStringFromSelector(@selector(dealUploadFunction:andClientHandle:)),}
};
```
然后这四个方法分别处理对用的下载、删除、替换、上传这四个请求，基本的HTTPServer就此完成了；由于代码有点多，这里就不贴出来了，还有一些具体的实现细节大家可以去github上下载demo自己看；基本的实现细节就讲到这里，由于水平不够，可能有很多地方没讲清楚，大家如果有不懂的可以直接提问

#### 结束

这一篇是进阶篇，基本就是模拟了HTTP的服务器处理请求数据并返回响应数据；只要理解了整个思路，基本自己就慢慢实现出来，这里只讲了一些大概的实现，具体的实现细节大家可以去看[demo](https://github.com/Elliotsomething/HTTPServerDemo)（别忘记star一下哈）
