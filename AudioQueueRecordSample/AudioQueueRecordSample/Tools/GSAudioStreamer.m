//
//  GSAudioStreamer.m
//  AudioQueueRecordSample
//
//  Created by gensee on 2019/11/13.
//  Copyright © 2019年 haocai. All rights reserved.
//

#import "GSAudioStreamer.h"

static void GSAudioQueueOutputCallback(void*                inClientData,
                                       AudioQueueRef            inAQ,
                                       AudioQueueBufferRef        inBuffer)
{
    // this is called by the audio queue when it has finished decoding our data.
    // The buffer is now free to be reused.
    GSAudioStreamer* streamer = (__bridge GSAudioStreamer*)inClientData;
//    [streamer handleBufferCompleteForQueue:inAQ buffer:inBuffer];
}

static void GSAudioQueueIsRunningCallback(void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
{
    GSAudioStreamer* streamer = (__bridge GSAudioStreamer *)inUserData;
//    [streamer handlePropertyChangeForQueue:inAQ propertyID:inID];
}

@implementation GSAudioStreamer

- (instancetype)init {
    if (self = [super init]) {
        
    }
    return self;
}

- (void)play {
    asbd.mSampleRate = 16000.0; //采样率
    asbd.mBitsPerChannel = 16; //在一个数据帧中，每个通道的样本数据的位数。
    asbd.mChannelsPerFrame = 1; //每帧数据通道数
    asbd.mFormatID = kAudioFormatLinearPCM; //数据格式 PCM or AAC ...
    asbd.mFramesPerPacket = 1; //每包数据帧数
    asbd.mBytesPerFrame = (asbd.mBitsPerChannel / 8) * asbd.mChannelsPerFrame;
    asbd.mBytesPerPacket = asbd.mBytesPerFrame * asbd.mFramesPerPacket;
    asbd.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    
    err = AudioQueueNewOutput(&asbd, GSAudioQueueOutputCallback, (__bridge void *)(self), NULL, NULL, 0, &audioQueue);
    
    // start the queue if it has not been started already
    // listen to the "isRunning" property
    err = AudioQueueAddPropertyListener(audioQueue, kAudioQueueProperty_IsRunning, GSAudioQueueIsRunningCallback, (__bridge void * _Nullable)(self));
    if (err)
    {
//        [self failWithErrorCode:AS_AUDIO_QUEUE_ADD_LISTENER_FAILED];
        return;
    }
    
    
    // allocate audio queue buffers
    for (unsigned int i = 0; i < kNumAQBufs; ++i)
    {
        err = AudioQueueAllocateBuffer(audioQueue, packetBufferSize, &audioQueueBuffer[i]);
        if (err)
        {
//            [self failWithErrorCode:AS_AUDIO_QUEUE_BUFFER_ALLOCATION_FAILED];
            return;
        }
    }
}

@end
