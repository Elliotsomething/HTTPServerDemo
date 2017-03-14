//
//  ViewController.m
//  HTTPServerDemo
//
//  Created by yanghao on 2017/3/9.
//  Copyright © 2017年 justlike. All rights reserved.
//

#import "ViewController.h"
#import "HTTPServer.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	[[HTTPServer sharedHTTPServer] start];
}


- (void)didReceiveMemoryWarning {
	[super didReceiveMemoryWarning];
	// Dispose of any resources that can be recreated.
}


@end
