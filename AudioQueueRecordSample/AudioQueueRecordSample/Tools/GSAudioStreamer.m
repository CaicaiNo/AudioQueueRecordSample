//
//  GSAudioStreamer.m
//  AudioQueueRecordSample
//
//  Created by gensee on 2019/11/13.
//  Copyright © 2019年 haocai. All rights reserved.
//

#import "GSAudioStreamer.h"
#import <AudioToolbox/AudioToolbox.h>


@interface GSAudioStreamer()

- (void)handleBufferCompleteForQueue:(AudioQueueRef)inAQ
                              buffer:(AudioQueueBufferRef)inBuffer;

@end


static void GSAudioQueueOutputCallback(void*                inClientData,
                                       AudioQueueRef            inAQ,
                                       AudioQueueBufferRef        inBuffer)
{
    // this is called by the audio queue when it has finished decoding our data.
    // The buffer is now free to be reused.
    GSAudioStreamer* streamer = (__bridge GSAudioStreamer*)inClientData;
    [streamer handleBufferCompleteForQueue:inAQ buffer:inBuffer];
}

static void GSAudioQueueIsRunningCallback(void *inUserData, AudioQueueRef inAQ, AudioQueuePropertyID inID)
{
    GSAudioStreamer* streamer = (__bridge GSAudioStreamer *)inUserData;
    //    [streamer handlePropertyChangeForQueue:inAQ propertyID:inID];
}

static void MyPropertyListenerProc(    void *                            inClientData,
                            AudioFileStreamID                inAudioFileStream,
                            AudioFileStreamPropertyID        inPropertyID,
                            UInt32 *                        ioFlags) {
    
}

static void MyPacketsProc(                void *            inClientData,
                          UInt32                            inNumberBytes,
                          UInt32                            inNumberPackets,
                          const void *                    inInputData,
                          AudioStreamPacketDescription    *inPacketDescriptions) {
    
}

@implementation GSAudioStreamer {
    NSString *m_path;
    NSInputStream *m_inputStream;
}

- (instancetype)initWithPCMFile:(NSString *)path {
    if (self = [super init]) {
        // initialize a mutex and condition so that we can block on buffers in use.
        pthread_mutex_init(&queueBuffersMutex, NULL);
        pthread_cond_init(&queueBufferReadyCondition, NULL);
        m_path = path;
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            m_inputStream = [NSInputStream inputStreamWithFileAtPath:path];
        }else {
            NSLog(@"[GSAudioStreamer] init error : %@ is not exist",path);
        }
//        OSStatus err = AudioFileStreamOpen(self, MyPropertyListenerProc, MyPacketsProc, kAudioFileCAFType, <#AudioFileStreamID  _Nullable * _Nonnull outAudioFileStream#>)
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
        AudioQueueEnqueueBuffer(audioQueue, audioQueueBuffer[i], 0, NULL);
    }
    
    
    AudioQueueSetParameter(audioQueue, kAudioQueueParam_Volume, 1.0);
    
    memset(inuse, 0, kNumAQBufs);
}

- (void)enqueueBuffer {
    inuse[fillBufferIndex] = true;        // set in use flag
    buffersUsed++;
    
    // enqueue buffer
    AudioQueueBufferRef fillBuf = audioQueueBuffer[fillBufferIndex];
    fillBuf->mAudioDataByteSize = bytesFilled;
    
    if (packetsFilled)
    {
        err = AudioQueueEnqueueBuffer(audioQueue, fillBuf, packetsFilled, packetDescs);
    }
    else
    {
        err = AudioQueueEnqueueBuffer(audioQueue, fillBuf, 0, NULL);
    }
    
    
    // go to next buffer
    if (++fillBufferIndex >= kNumAQBufs) fillBufferIndex = 0;
    bytesFilled = 0;        // reset bytes filled
    packetsFilled = 0;        // reset packets filled
    
    // wait until next buffer is not in use
    pthread_mutex_lock(&queueBuffersMutex);
    while (inuse[fillBufferIndex])
    {
        pthread_cond_wait(&queueBufferReadyCondition, &queueBuffersMutex);
    }
    pthread_mutex_unlock(&queueBuffersMutex);
}

- (void)cleanup {
    pthread_mutex_destroy(&queueBuffersMutex);
    pthread_cond_destroy(&queueBufferReadyCondition);
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
    unsigned int bufIndex = -1;
    for (unsigned int i = 0; i < kNumAQBufs; ++i)
    {
        if (inBuffer == audioQueueBuffer[i])
        {
            bufIndex = i;
            break;
        }
    }
    
    if (bufIndex == -1)
    {
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
    
    //
    //  Enable this logging to measure how many buffers are queued at any time.
    //
#if LOG_QUEUED_BUFFERS
    NSLog(@"Queued buffers: %ld", buffersUsed);
#endif
    
    pthread_cond_signal(&queueBufferReadyCondition);
    pthread_mutex_unlock(&queueBuffersMutex);
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
//    UInt32 running;
//    UInt32 size;
//    OSStatus err = AudioQueueGetProperty(inAQ, kAudioQueueProperty_IsRunning, &running, &size);
//    if (err) {
////        PRINTERROR("get kAudioQueueProperty_IsRunning");
//        return;
//    }
//    if (!running) {
//        pthread_mutex_lock(&self->queueBuffersMutex);
//        pthread_cond_signal(&self->queueBufferReadyCondition);
//        pthread_mutex_unlock(&self->queueBuffersMutex);
//    }
//    if (![[NSThread currentThread] isEqual:internalThread])
//    {
//        [self
//         performSelector:@selector(handlePropertyChange:)
//         onThread:internalThread
//         withObject:[NSNumber numberWithInt:inID]
//         waitUntilDone:NO
//         modes:[NSArray arrayWithObject:NSDefaultRunLoopMode]];
//        return;
//    }
//    @synchronized(self)
//    {
//        if (inID == kAudioQueueProperty_IsRunning)
//        {
//            if (state == AS_STOPPING)
//            {
//                // Should check value of isRunning to ensure this kAudioQueueProperty_IsRunning isn't
//                // the *start* of a very short stream
//                UInt32 isRunning = 0;
//                UInt32 size = sizeof(UInt32);
//                AudioQueueGetProperty(audioQueue, inID, &isRunning, &size);
//                if (isRunning == 0)
//                {
//                    self.state = AS_STOPPED;
//                }
//            }
//            else if (state == AS_WAITING_FOR_QUEUE_TO_START)
//            {
//                //
//                // Note about this bug avoidance quirk:
//                //
//                // On cleanup of the AudioQueue thread, on rare occasions, there would
//                // be a crash in CFSetContainsValue as a CFRunLoopObserver was getting
//                // removed from the CFRunLoop.
//                //
//                // After lots of testing, it appeared that the audio thread was
//                // attempting to remove CFRunLoop observers from the CFRunLoop after the
//                // thread had already deallocated the run loop.
//                //
//                // By creating an NSRunLoop for the AudioQueue thread, it changes the
//                // thread destruction order and seems to avoid this crash bug -- or
//                // at least I haven't had it since (nasty hard to reproduce error!)
//                //
//                [NSRunLoop currentRunLoop];
//
//                self.state = AS_PLAYING;
//            }
//            else
//            {
//                NSLog(@"AudioQueue changed state in unexpected way.");
//            }
//        }
//    }
}

@end
