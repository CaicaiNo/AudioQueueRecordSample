//
//  GSAudioStreamer.h
//  AudioQueueRecordSample
//
//  Created by gensee on 2019/11/13.
//  Copyright © 2019年 haocai. All rights reserved.
//

#import <Foundation/Foundation.h>
#include <pthread.h>
#include <AudioToolbox/AudioToolbox.h>

#define kNumAQBufs 16            // Number of audio queue buffers we allocate.
// Needs to be big enough to keep audio pipeline
// busy (non-zero number of queued buffers) but
// not so big that audio takes too long to begin
// (kNumAQBufs * kAQBufSize of data must be
// loaded before playback will start).
//
// Set LOG_QUEUED_BUFFERS to 1 to log how many
// buffers are queued at any time -- if it drops
// to zero too often, this value may need to
// increase. Min 3, typical 8-24.

#define kAQDefaultBufSize 2048    // Number of bytes in each audio queue buffer
// Needs to be big enough to hold a packet of
// audio from the audio file. If number is too
// large, queuing of audio before playback starts
// will take too long.
// Highly compressed files can use smaller
// numbers (512 or less). 2048 should hold all
// but the largest packets. A buffer size error
// will occur if this number is too small.

#define kAQMaxPacketDescs 512    // Number of packet descriptions in our array

typedef enum
{
    AS_INITIALIZED = 0,
    AS_STARTING_FILE_THREAD,
    AS_WAITING_FOR_DATA,
    AS_FLUSHING_EOF,
    AS_WAITING_FOR_QUEUE_TO_START,
    AS_PLAYING,
    AS_BUFFERING,
    AS_STOPPING,
    AS_STOPPED,
    AS_PAUSED
} AudioStreamerState;

@interface GSAudioStreamer : NSObject{
    AudioQueueRef audioQueue;
    AudioFileStreamID audioFileStream;    // the audio file stream parser
    AudioStreamBasicDescription asbd;    // description of the audio
    AudioQueueBufferRef audioQueueBuffer[kNumAQBufs];        // audio queue buffers
    AudioStreamPacketDescription packetDescs[kAQMaxPacketDescs];    // packet descriptions for enqueuing audio
    unsigned int fillBufferIndex;    // the index of the audioQueueBuffer that is being filled
    UInt32 packetBufferSize;
    size_t bytesFilled;                // how many bytes have been filled
    size_t packetsFilled;            // how many packets have been filled
    bool inuse[kNumAQBufs];            // flags to indicate that a buffer is still in use
    NSInteger buffersUsed;
    
    AudioStreamerState state;
    OSStatus err;
    
    pthread_mutex_t queueBuffersMutex;            // a mutex to protect the inuse flags
    pthread_cond_t queueBufferReadyCondition;    // a condition varable for handling the inuse flags
}

- (instancetype)initWithPCMFile:(NSString *)path;

/**
 播放声音
 */
- (void)play;

/**
 停止播放
 */
- (void)stop;

@end
