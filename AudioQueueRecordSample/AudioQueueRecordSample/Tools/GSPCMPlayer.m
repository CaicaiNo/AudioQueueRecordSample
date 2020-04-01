//
//  GSAudioStreamer.m
//  AudioQueueRecordSample
//
//  Created by gensee on 2019/11/13.
//  Copyright © 2019年 haocai. All rights reserved.
//


// 注: 此文件仅做了简单的播放逻辑处理，只为了学习了解其流程，真正使用还需要处理很多，例如多线程以及音频打断路由处理
// 可以参考 AudioStreamer 做更好的处理

#import "GSPCMPlayer.h"
#import <AudioToolbox/AudioToolbox.h>

@interface GSPCMPlayer()

- (void)handleBufferCompleteForQueue:(AudioQueueRef)inAQ
                              buffer:(AudioQueueBufferRef)inBuffer;
- (void)handlePropertyChangeForQueue:(AudioQueueRef)inAQ
                          propertyID:(AudioQueuePropertyID)inID;
@end


static void GSAudioQueueOutputCallback(void*                inClientData,
                                       AudioQueueRef            inAQ,
                                       AudioQueueBufferRef        inBuffer)
{
    // this is called by the audio queue when it has finished decoding our data.
    // The buffer is now free to be reused.
    GSPCMPlayer* streamer = (__bridge GSPCMPlayer*)inClientData;
    [streamer handleBufferCompleteForQueue:inAQ buffer:inBuffer];
}

//static void GSAudioQueueIsRunningCallback(void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
//{
//    GSPCMPlayer* streamer = (__bridge GSPCMPlayer *)inUserData;
//    [streamer handlePropertyChangeForQueue:inAQ propertyID:inID];
//}

@implementation GSPCMPlayer {
    NSString *m_path;
    AudioFileID m_audioFileID;
    u_int32_t packetNums;
    NSInputStream *inputStream;
}

- (instancetype)initWithPCMFile:(NSString *)path {
    if (self = [super init]) {
        // initialize a mutex and condition so that we can block on buffers in use.
        pthread_mutex_init(&queueBuffersMutex, NULL);
        pthread_cond_init(&queueBufferReadyCondition, NULL);
        m_path = path;
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            if ([path.pathExtension isEqualToString:@"pcm"]) {
                inputStream = [[NSInputStream alloc]initWithFileAtPath:path];
                [inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
                inputStream.delegate = self;
                if (!inputStream) {
                    NSLog(@"打开PCM文件失败");
                }else {
                    [self pcmSetup];
                    [inputStream open];
                }
            }
        }else {
            NSLog(@"[GSAudioStreamer] init error : %@ is not exist",path);
        }
        fillBufferIndex = 0;
        buffersUsed = 0;
    }
    return self;
}

- (void)pcmSetup {
    //这里因为我知道录制时的参数，所以我写死了
    asbd.mSampleRate = 16000.0; //采样率
    asbd.mBitsPerChannel = 16; //在一个数据帧中，每个通道的样本数据的位数。
    asbd.mChannelsPerFrame = 1; //每帧数据通道数
    asbd.mFormatID = kAudioFormatLinearPCM; //数据格式 PCM
    asbd.mFramesPerPacket = 1; //每包数据帧数
    asbd.mBytesPerFrame = (asbd.mBitsPerChannel / 8) * asbd.mChannelsPerFrame;
    asbd.mBytesPerPacket = asbd.mBytesPerFrame * asbd.mFramesPerPacket;
    asbd.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    //asbd = AudioStreamBasicDescription
    err = AudioQueueNewOutput(&asbd, GSAudioQueueOutputCallback, (__bridge void *)(self), NULL, NULL, 0, &audioQueue);
    if (audioQueue) {
        // allocate audio queue buffers
        for (unsigned int i = 0; i < kNumAQBufs; ++i){
            err = AudioQueueAllocateBuffer(audioQueue, kAQDefaultBufSize, &audioQueueBuffer[i]);//此时为buffer分配了内存空间
            AudioQueueEnqueueBuffer(audioQueue, audioQueueBuffer[i], 0, NULL);
        }
    }
    
}

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode
{
    switch (eventCode) {
        case NSStreamEventNone:
            NSLog(@"NSStreamEventNone");
            break;
        case NSStreamEventOpenCompleted:
            NSLog(@"NSStreamEventOpenCompleted");
            break;
        case NSStreamEventHasBytesAvailable:
            break;
        case NSStreamEventHasSpaceAvailable:
            NSLog(@"NSStreamEventHasSpaceAvailable");
            break;
            //此处处理错误事件
        case NSStreamEventErrorOccurred: {
            NSError * error = [aStream streamError];
            NSString * errorInfo = [NSString stringWithFormat:@"Failed while reading stream; error '%@' (code %ld)", error.localizedDescription, error.code];
            NSLog(@"%@",errorInfo);
            break;
        }
        case NSStreamEventEndEncountered: {
            [aStream close];
            [aStream removeFromRunLoop:[NSRunLoop currentRunLoop]
                               forMode:NSDefaultRunLoopMode];
            aStream = nil;
        }
            break;
        default:
            break;
    }
    NSLog(@"查看inputSteam状态值：%lu",inputStream.streamStatus);
}

- (void)setVolume:(float)vol {
    AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, vol);
}


- (void)play {
    @synchronized (self) {
        if (state == AS_INITIALIZED || state == AS_STOPPED) {
            int i = 0;
            while (i <= kNumAQBufs + 1) {
                [self enqueueBuffer];
                i++;
            }
            
        }
    }
}



- (void)enqueueBuffer {
    @synchronized (self) {
    // wait until next buffer is not in use
        pthread_mutex_lock(&queueBuffersMutex);
        inuse[fillBufferIndex] = true;        // set in use flag
        buffersUsed++;
        
        printf("fillBufferIndex %ld \n",(long)fillBufferIndex);
        // enqueue buffer
        AudioQueueBufferRef fillBuf = audioQueueBuffer[fillBufferIndex];
        pthread_mutex_unlock(&queueBuffersMutex);
        uint32_t readbytes = 0, packets = (uint32_t)1;
        
        readbytes = [inputStream read:fillBuf->mAudioData maxLength:kAQDefaultBufSize];
        if (readbytes > 0) {
            fillBuf->mAudioDataByteSize = readbytes;
            NSLog(@"共读取包数量为 %zu , 包大小 %d",packetsFilled,readbytes);
            err = AudioQueueEnqueueBuffer(audioQueue, fillBuf, 0, NULL);
            packetsFilled += packets;
            
            // go to next buffer
            if (++fillBufferIndex >= kNumAQBufs) fillBufferIndex = 0;
            
            state = AS_PLAYING;
            AudioQueueStart(audioQueue, NULL);
        }else {
            // -1 means no datas
            state = AS_STOPPING;
            AudioQueueStop(audioQueue, NO);
        }
        
    }
}

//
// handleBufferCompleteForQueue:buffer:
//
// Handles the buffer completetion notification from the audio queue
//
// Parameters:
//    inAQ - the queue
//    inBuffer - the buffer
//
- (void)handleBufferCompleteForQueue:(AudioQueueRef)inAQ
                              buffer:(AudioQueueBufferRef)inBuffer
{
    @synchronized (self) {
        unsigned int bufIndex = -1;
        for (unsigned int i = 0; i < kNumAQBufs; ++i) {
            if (inBuffer == audioQueueBuffer[i]) {
                bufIndex = i;
                break;
            }
        }
        
        if (bufIndex == -1) {
            //        [self failWithErrorCode:AS_AUDIO_QUEUE_BUFFER_MISMATCH];
            pthread_mutex_lock(&queueBuffersMutex);
            pthread_cond_signal(&queueBufferReadyCondition);
            pthread_mutex_unlock(&queueBuffersMutex);
            return;
        }
        
        // signal waiting thread that the buffer is free.
        pthread_mutex_lock(&queueBuffersMutex);
        inuse[bufIndex] = false;
        buffersUsed--;
        if (buffersUsed == 0) {
            NSLog(@"buffersUsed == 0");
//            state == AS_STOPPED;
        }
        //
        //  Enable this logging to measure how many buffers are queued at any time.
        //
#if 1
        NSLog(@"Queued buffers: %ld", buffersUsed);
#endif
        
        pthread_cond_signal(&queueBufferReadyCondition);
        pthread_mutex_unlock(&queueBuffersMutex);
        if (state == AS_PLAYING) {
            [self enqueueBuffer];
        }
    }
    
}

- (void)stop {
    @synchronized (self) {
        if (state == AS_PLAYING) {
            err = AudioQueuePause(audioQueue);
            state = AS_STOPPED;
        }
    }
}

- (void)dealloc {
    state = AS_STOPPED;
    err = AudioQueuePause(audioQueue);
    if (err != noErr) {
        for(int i = 0; i < kNumAQBufs; i++) {
            AudioQueueFreeBuffer(audioQueue, audioQueueBuffer[i]);
        }
    }
    AudioQueueDispose(audioQueue, true);
}

- (void)handlePropertyChange:(NSNumber *)num
{
    [self handlePropertyChangeForQueue:NULL propertyID:[num intValue]];
}
//
// handlePropertyChangeForQueue:propertyID:
//
// Implementation for ASAudioQueueIsRunningCallback
//
// Parameters:
//    inAQ - the audio queue
//    inID - the property ID
//
- (void)handlePropertyChangeForQueue:(AudioQueueRef)inAQ
                          propertyID:(AudioQueuePropertyID)inID
{
    @autoreleasepool {
        if (inID == kAudioQueueProperty_IsRunning) {
            if (state == AS_STOPPING) {
                // Should check value of isRunning to ensure this kAudioQueueProperty_IsRunning isn't
                // the *start* of a very short stream
                UInt32 isRunning = 0;
                UInt32 size = sizeof(UInt32);
                AudioQueueGetProperty(audioQueue, inID, &isRunning, &size);
                if (isRunning == 0)
                {
                    state = AS_STOPPED;
                }
            } else if (state == AS_WAITING_FOR_QUEUE_TO_START) {
                //
                // Note about this bug avoidance quirk:
                //
                // On cleanup of the AudioQueue thread, on rare occasions, there would
                // be a crash in CFSetContainsValue as a CFRunLoopObserver was getting
                // removed from the CFRunLoop.
                //
                // After lots of testing, it appeared that the audio thread was
                // attempting to remove CFRunLoop observers from the CFRunLoop after the
                // thread had already deallocated the run loop.
                //
                // By creating an NSRunLoop for the AudioQueue thread, it changes the
                // thread destruction order and seems to avoid this crash bug -- or
                // at least I haven't had it since (nasty hard to reproduce error!)
                //
                [NSRunLoop currentRunLoop];
                
                state = AS_PLAYING;
            } else {
                NSLog(@"AudioQueue changed state in unexpected way.");
            }
        }
    }
}

@end
