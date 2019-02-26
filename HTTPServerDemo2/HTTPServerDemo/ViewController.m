//
//  ViewController.m
//  HTTPServerDemo
//
//  Created by yanghao on 2017/3/9.
//  Copyright © 2017年 justlike. All rights reserved.
//

#import "ViewController.h"
#import "HTTPServer.h"
#import "HTTPResponseHandler.h"
#import "HTTPIPTool.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	
    self.title = @"fasfdasdfa";
        
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 100, 300, 60)];
    label.text = [NSString stringWithFormat:@"IP:%@",[HTTPIPTool getIPAddress]];
    [self.view addSubview:label];
    
	NSString *str = @"dddddd";
	
	[str writeToFile:[HTTPResponseHandler pathForFile]
		atomically:YES
		encoding:NSUTF8StringEncoding
		error:NULL];
	
	
	[[HTTPServer sharedHTTPServer] start];
}


- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	// Dispose of any resources that can be recreated.
}


@end
