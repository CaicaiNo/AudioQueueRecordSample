//
//  LFAudioCapture.h
//  LFLiveKit
//
//  Created by LaiFeng on 16/5/20.
//  Copyright © 2016年 LaiFeng All rights reserved.
//


// 使用LFLiveKit框架的一部分代码修改,有兴趣的去github上查看

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "GSLiveAudioConfiguration.h"

#pragma mark -- AudioCaptureNotification
/** compoentFialed will post the notification */
extern NSString *_Nullable const GSAudioComponentFailedToCreateNotification;

@class GSAudioCapture;
/** LFAudioCapture callback audioData */
@protocol GSAudioCaptureDelegate <NSObject>
- (void)captureOutput:(nullable GSAudioCapture *)capture audioData:(nullable NSData*)audioData;
@end


@interface GSAudioCapture : NSObject

#pragma mark - Attribute
///=============================================================================
/// @name Attribute
///=============================================================================

/** The delegate of the capture. captureData callback */
@property (nullable, nonatomic, weak) id<GSAudioCaptureDelegate> delegate;

/** The muted control callbackAudioData,muted will memset 0.*/
@property (nonatomic, assign) BOOL muted;

/** The running control start capture or stop capture*/
@property (nonatomic, assign) BOOL running;

#pragma mark - Initializer
///=============================================================================
/// @name Initializer
///=============================================================================
- (nullable instancetype)init UNAVAILABLE_ATTRIBUTE;
+ (nullable instancetype)new UNAVAILABLE_ATTRIBUTE;

/**
   The designated initializer. Multiple instances with the same configuration will make the
   capture unstable.
 */
- (nullable instancetype)initWithAudioConfiguration:(nullable GSLiveAudioConfiguration *)configuration NS_DESIGNATED_INITIALIZER;

@end
