//
//  GSPCMWriter.m
//  GSCommonKit
//
//  Created by gensee on 2019/9/9.
//  Copyright © 2019年 gensee. All rights reserved.
//

#import "GSPCMWriter.h"

@implementation GSPCMWriter {
    NSOutputStream *m_outputSteam; //视频输出流写入文件
    NSString *m_filename;
    NSString *cachePath;
}
- (instancetype)init {
    if (self = [super init]) {
        [self setup];
    }
    return self;
}

- (void)setup {
    if (!m_outputSteam) {
        NSArray *array = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *path = [[array objectAtIndex:0] stringByAppendingPathComponent:@"AudioFile"];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        BOOL isDir = NO;
        if(![fileManager fileExistsAtPath:path isDirectory:&isDir]){
            NSError *error = nil;
            [fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error];
        }
        cachePath = [[array objectAtIndex:0] stringByAppendingPathComponent:@"AudioFile"];
  
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        [fmt setDateFormat:@"YYYYMMDD-HHMMSS"];
        NSDate *current = [NSDate date];
        NSString *webcastId = [fmt stringFromDate:current];
        m_filename = [cachePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@",webcastId]];
        
        if([fileManager fileExistsAtPath:m_filename isDirectory:&isDir]){
            NSError *error = nil;
            BOOL result = [fileManager removeItemAtPath:m_filename error:&error];
            if (result) {
                NSLog(@"[GSPCMWriter] remove PCM at %@",m_filename);
                [fileManager createFileAtPath:m_filename contents:nil attributes:nil];
            }
        }else {
            [fileManager createFileAtPath:m_filename contents:nil attributes:nil];
        }
        NSLog(@"[GSPCMWriter] write PCM to %@",m_filename);
        m_outputSteam = [[NSOutputStream alloc] initToFileAtPath:m_filename append:YES];
        [m_outputSteam open];
    }
}

/**
 获得文件句柄
 */
- (NSString*)getPCMHandler {
    return m_filename;
}

/**
 重置文件句柄
 */
- (void)resetPCMHandler {
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    [fmt setDateFormat:@"YYYYMMDD-HHMMSS"];
    NSDate *current = [NSDate date];
    NSString *webcastId = [fmt stringFromDate:current];
    [self resetPCMHandler:webcastId];
}

/**
 重置文件句柄
 
 @param filename 提供文件名
 */
- (void)resetPCMHandler:(NSString *)filename {
    if (m_outputSteam) {
        [m_outputSteam close];
        m_outputSteam = nil;
    }
    m_filename = [cachePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@",filename]];
    BOOL isDir = NO;
    if([[NSFileManager defaultManager] fileExistsAtPath:m_filename isDirectory:&isDir]){
        NSError *error = nil;
        BOOL result = [[NSFileManager defaultManager] removeItemAtPath:m_filename error:&error];
        if (result) {
            NSLog(@"[GSPCMWriter] remove PCM at %@",m_filename);
            [[NSFileManager defaultManager] createFileAtPath:m_filename contents:nil attributes:nil];
        }
    }else {
        [[NSFileManager defaultManager] createFileAtPath:m_filename contents:nil attributes:nil];
    }
    NSLog(@"[GSPCMWriter] write PCM to %@",m_filename);
    m_outputSteam = [[NSOutputStream alloc] initToFileAtPath:m_filename append:YES];
    [m_outputSteam open];
}

- (void)writePCM:(void*)data length:(unsigned int)length {
    if (m_outputSteam){
        [m_outputSteam write:(const uint8_t*)data maxLength:length];
    }
}

- (void)clearAllPCM {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSArray* tempArray = [manager contentsOfDirectoryAtPath:cachePath error:nil];
    for (NSString* fileName in tempArray) {
        BOOL flag = YES;
        NSString* fullPath = [cachePath stringByAppendingPathComponent:fileName];
        if ([manager fileExistsAtPath:fullPath isDirectory:&flag]) {
            if (!flag) {
                [manager removeItemAtPath:fullPath error:nil];
            }
        }
    }
    m_filename = nil;
}

@end
