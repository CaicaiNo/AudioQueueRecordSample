//AudioQueueRecordSample code for study

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>


#define kNumberBuffers 3
#define kFrameSize 2048
#define kTVURecoderPCMMaxBuffSize 2048

typedef struct AQCallbackStruct {
    AudioStreamBasicDescription mDataFormat;
    AudioQueueRef               queue;
    AudioQueueBufferRef         mBuffers[kNumberBuffers];
    AudioFileID                 outputFile;
    
    unsigned int               frameSize;
    long long                   recPtr;
    int                         run;
    
} AQCallbackStruct;

@protocol GSAudioSendEngineDelegate <NSObject>

- (void)processAudioPacket:(char *)data length:(int)len;

@end


@interface GSAudioSendEngine : NSObject

@property (assign, nonatomic) AQCallbackStruct aqc;
@property (weak, nonatomic) id<GSAudioSendEngineDelegate> delegate;
/**
 音频session设置AVAudioSessionCategoryOptions 默认为  AVAudioSessionCategoryOptionDefaultToSpeaker |AVAudioSessionCategoryOptionAllowBluetooth|AVAudioSessionCategoryOptionMixWithOthers;
 */
@property (nonatomic, assign) AVAudioSessionCategoryOptions sessionCategoryOption;


+ (id)shareAuidoSendEngine;
- (void)start;
- (void)stop;
- (void)pause;
- (void)processAudioBuffer:(AudioQueueBufferRef) buffer withQueue:(AudioQueueRef) queue;

@end
