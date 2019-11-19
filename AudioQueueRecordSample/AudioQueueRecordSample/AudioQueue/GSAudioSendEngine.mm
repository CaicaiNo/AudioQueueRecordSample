//AudioQueueRecordSample code for study


#import "GSAudioSendEngine.h"
#import <AVFoundation/AVFoundation.h>
#import "GSNotificationManager.h"
#import <UIKit/UIKit.h>
#import <pthread.h>

#define kXDXRecoderAudioBytesPerPacket      2
#define kXDXRecoderAACFramesPerPacket       1024

AudioConverterRef               _encodeConvertRef = NULL;   ///< convert param
AudioStreamBasicDescription     _targetDes;                 ///< destination format

#pragma mark Calculate DB
enum ChannelCount
{
    k_Mono = 1,
    k_Stereo
};

void caculate_bm_db(void * const data ,size_t length ,int64_t timestamp, ChannelCount channelModel,float channelValue[2],bool isAudioUnit) {
    int16_t *audioData = (int16_t *)data;
    
    if (channelModel == k_Mono) {
        int     sDbChnnel     = 0;
        int16_t curr          = 0;
        int16_t max           = 0;
        size_t traversalTimes = 0;
        
        if (isAudioUnit) {
            traversalTimes = length/2;// 由于512后面的数据显示异常  需要全部忽略掉
        }else{
            traversalTimes = length;
        }
        
        for(int i = 0; i< traversalTimes; i++) {
            curr = *(audioData+i);
            if(curr > max) max = curr;
        }
        
        if(max < 1) {
            sDbChnnel = -100;
        }else {
            sDbChnnel = (20*log10((0.0 + max)/32767) - 0.5);
        }
        
        channelValue[0] = channelValue[1] = sDbChnnel;
        
    } else if (channelModel == k_Stereo){
        int sDbChA = 0;
        int sDbChB = 0;
        
        int16_t nCurr[2] = {0};
        int16_t nMax[2] = {0};
        
        for(unsigned int i=0; i<length/2; i++) {
            nCurr[0] = audioData[i];
            nCurr[1] = audioData[i + 1];
            
            if(nMax[0] < nCurr[0]) nMax[0] = nCurr[0];
            
            if(nMax[1] < nCurr[1]) nMax[1] = nCurr[0];
        }
        
        if(nMax[0] < 1) {
            sDbChA = -100;
        } else {
            sDbChA = (20*log10((0.0 + nMax[0])/32767) - 0.5);
        }
        
        if(nMax[1] < 1) {
            sDbChB = -100;
        } else {
            sDbChB = (20*log10((0.0 + nMax[1])/32767) - 0.5);
        }
        
        channelValue[0] = sDbChA;
        channelValue[1] = sDbChB;
    }
}

#pragma mark ---------------------------------- CallBack : collect pcm and  convert  -------------------------------------
OSStatus encodeConverterComplexInputDataProc(AudioConverterRef              inAudioConverter,
                                             UInt32                         *ioNumberDataPackets,
                                             AudioBufferList                *ioData,
                                             AudioStreamPacketDescription   **outDataPacketDescription,
                                             void                           *inUserData) {
    
    ioData->mBuffers[0].mData           = inUserData;
    ioData->mBuffers[0].mNumberChannels = _targetDes.mChannelsPerFrame;
    ioData->mBuffers[0].mDataByteSize   = kXDXRecoderAACFramesPerPacket * kXDXRecoderAudioBytesPerPacket * _targetDes.mChannelsPerFrame;
    
    return 0;
}

static void AQInputCallback (void                   * inUserData,
                             AudioQueueRef          inAudioQueue,
                             AudioQueueBufferRef    inBuffer,
                             const AudioTimeStamp   * inStartTime,
                             UInt32          inNumPackets,
                             const AudioStreamPacketDescription * inPacketDesc)
{
    GSAudioSendEngine *engine = (__bridge GSAudioSendEngine *) inUserData;
    
    if (!engine) {
        NSLog(@"engine is dealloc");
        return;
    }
    NSTimeInterval playedTime = inStartTime->mSampleTime / engine.aqc.mDataFormat.mSampleRate;
    printf("inNumPackets %d record time %f\n",inNumPackets,playedTime);
    if (inNumPackets > 0) {
        [engine processAudioBuffer:inBuffer withQueue:inAudioQueue];
    }
    
    if (engine.aqc.run) {
        AudioQueueEnqueueBuffer(engine.aqc.queue, inBuffer, 0, NULL);
    }
    
}

@interface GSAudioSendEngine()
{
    BOOL isBackGround;
    pthread_mutex_t _lock;
    int64_t _lastLogTime;
    
}
@property (nonatomic, assign) BOOL isRunning;
// Volume
@property (nonatomic, assign)       float                           volLDB;
@property (nonatomic, assign)       float                           volRDB;

@end


@implementation GSAudioSendEngine
{
    BOOL _isBackgroundAudioMode;  //表示是否app打开后台模式
    BOOL _isAudioInteruptBegan;   //表示是否音频打断开始
    BOOL _isBackground;  //表示是否在后台
    int _audioCookedValue;  // 1 表示音频打断处理过 0 表示不处理  2表示音频已经打断，但由于非后台模式等原因未处理
    GSNotificationManager *notificationMananger; //通知处理类 - 可用NSNotification替换

}

static int          pcm_buffer_size = 0;
static uint8_t      pcm_buffer[kNumberBuffers*2];

- (id)init
{
    self = [super init];
    if (self) {
        //检测后台模式 是否有后台播放audio支持
        NSDictionary *infoDic = [NSBundle mainBundle].infoDictionary;
        NSArray *modes = [infoDic objectForKey:@"UIBackgroundModes"];
        if (modes && modes.count > 0) {
            for (NSString *tmp in modes) {
                if ([tmp isEqualToString:@"audio"]) {
                    _isBackgroundAudioMode = YES;
                    break;
                }
            }
        }
        _lastLogTime = 0;
        _audioCookedValue = 0;
        pthread_mutex_init(&_lock, NULL);
        
    }
    return self;
}

- (void)registerNotifications {
    NSLog(@" registerNotifications ");
    if (!notificationMananger) {
        notificationMananger = [[GSNotificationManager alloc] init];
    }
    [notificationMananger addObserver:self selector:@selector(handleAudioSessionInterruption:)
                                 name:AVAudioSessionInterruptionNotification
                               object:nil];
    [notificationMananger addObserver:self
                             selector:@selector(appDidBecomeActive)
                                 name:UIApplicationDidBecomeActiveNotification
                               object:nil];
    [notificationMananger addObserver:self
                             selector:@selector(appWillResignActive)
                                 name:UIApplicationWillResignActiveNotification object:nil];
    [notificationMananger addObserver: self
                             selector: @selector(handleRouteChange:)
                                 name: AVAudioSessionRouteChangeNotification
                               object: nil];
}

- (void)removeNotifications {
    if (notificationMananger) [notificationMananger removeAllObservers:self];
}



+ (id)shareAuidoSendEngine
{
    static GSAudioSendEngine *recorder = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        recorder = [[GSAudioSendEngine alloc] init];
        
    });
    return recorder;
}

- (AVAudioSessionCategoryOptions)sessionCategoryOption {
    if (!_sessionCategoryOption) {
        _sessionCategoryOption = AVAudioSessionCategoryOptionDefaultToSpeaker|AVAudioSessionCategoryOptionAllowBluetooth|AVAudioSessionCategoryOptionMixWithOthers;
    }
    return _sessionCategoryOption;
}

- (void)start
{
    if (_aqc.run) {
        NSLog(@"start failed : aqc run is true");
        return;
    }
    [self registerNotifications];
    
    _aqc.mDataFormat.mSampleRate = 16000.0; //采样率
    _aqc.mDataFormat.mBitsPerChannel = 16; //在一个数据帧中，每个通道的样本数据的位数。
    _aqc.mDataFormat.mChannelsPerFrame = 1; //每帧数据通道数
    _aqc.mDataFormat.mFormatID = kAudioFormatLinearPCM; //数据格式 PCM
    _aqc.mDataFormat.mFramesPerPacket = 1; //每包数据帧数
    _aqc.mDataFormat.mBytesPerFrame = (_aqc.mDataFormat.mBitsPerChannel / 8) * _aqc.mDataFormat.mChannelsPerFrame;
    _aqc.mDataFormat.mBytesPerPacket = _aqc.mDataFormat.mBytesPerFrame * _aqc.mDataFormat.mFramesPerPacket;
    _aqc.mDataFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;
    _aqc.frameSize = kFrameSize;
    
    AudioQueueNewInput(&_aqc.mDataFormat, AQInputCallback, (__bridge void *)(self), NULL, kCFRunLoopCommonModes, 0, &_aqc.queue);
    
    for (int i=0; i<kNumberBuffers; i++)
    {
        AudioQueueAllocateBuffer(_aqc.queue, _aqc.frameSize, &_aqc.mBuffers[i]);
        AudioQueueEnqueueBuffer(_aqc.queue, _aqc.mBuffers[i], 0, NULL);
    }
    
    _aqc.run = 1;
    AudioQueueStart(_aqc.queue, NULL);
    
}

- (void)appDidBecomeActive {
    if (!self.isRunning) return;
    _isBackground = NO;
    _isAudioInteruptBegan = NO;//进入前台就认为没有音频打断了
    
    if (_audioCookedValue == 2) { //当需要进入前台重置时
        [self resetAudio];
    }
    _audioCookedValue = 0;
    if (!_isBackgroundAudioMode) {
        [[AVAudioSession sharedInstance] setActive:YES error:nil];
        //to avoid receive notification interrupt start , and resume audio session
    }else {
        
    }
}

- (void)appWillResignActive {
    if (!self.isRunning) return;
    
    _isBackground = YES;
    if (!_isBackgroundAudioMode) {
        [self stop];
        NSError *error = nil;
        if (![AVAudioSession sharedInstance].secondaryAudioShouldBeSilencedHint) {
            //关闭音频session,避免打断通知混乱的问题
            [[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&error];
        }
        
        if (error) {
            NSLog(@"inactive session error %@",error.description);
        }
        //to avoid receive notification interrupt start,option kAudioSessionSetActiveFlag_NotifyOthersOnDeactivation is need
    }
}



- (void)pause {
    AudioQueuePause(_aqc.queue);
}

- (void)stop {
    NSLog(@"stop");
    [self removeNotifications];
    [self cleanUp];
}


// PCM -> AAC
AudioBufferList* convertPCMToAAC (GSAudioSendEngine *recoder) {
    
    UInt32   maxPacketSize    = 0;
    UInt32   size             = sizeof(maxPacketSize);
    OSStatus status;
    
    status = AudioConverterGetProperty(_encodeConvertRef,
                                       kAudioConverterPropertyMaximumOutputPacketSize,
                                       &size,
                                       &maxPacketSize);
    //    log4cplus_info("AudioConverter","kAudioConverterPropertyMaximumOutputPacketSize status:%d \n",(int)status);
    
    AudioBufferList *bufferList             = (AudioBufferList *)malloc(sizeof(AudioBufferList));
    bufferList->mNumberBuffers              = 1;
    bufferList->mBuffers[0].mNumberChannels = _targetDes.mChannelsPerFrame;
    bufferList->mBuffers[0].mData           = malloc(maxPacketSize);
    bufferList->mBuffers[0].mDataByteSize   = kTVURecoderPCMMaxBuffSize;
    
    AudioStreamPacketDescription outputPacketDescriptions;
    
    // inNumPackets设置为1表示编码产生1帧数据即返回，官方：On entry, the capacity of outOutputData expressed in packets in the converter's output format. On exit, the number of packets of converted data that were written to outOutputData. 在输入表示输出数据的最大容纳能力 在转换器的输出格式上，在转换完成时表示多少个包被写入
    UInt32 inNumPackets = 1;
    // inNumPackets设置为1表示编码产生1024帧数据即返回
    // Notice : Here, due to encoder characteristics, 1024 frames of data must be given to the encoder in order to complete a conversion, 在此处由于编码器特性,必须给编码器1024帧数据才能完成一次转换,也就是刚刚在采集数据回调中存储的pcm_buffer
    status = AudioConverterFillComplexBuffer(_encodeConvertRef,
                                             encodeConverterComplexInputDataProc,
                                             pcm_buffer,
                                             &inNumPackets,
                                             bufferList,
                                             &outputPacketDescriptions);
    
    if(status != noErr){
        //        log4cplus_debug("Audio Recoder","set AudioConverterFillComplexBuffer status:%d inNumPackets:%d \n",(int)status, inNumPackets);
        free(bufferList->mBuffers[0].mData);
        free(bufferList);
        return NULL;
    }
    
    if (recoder.needsVoiceDemo) {
        // if inNumPackets set not correct, file will not normally play. 将转换器转换出来的包写入文件中，inNumPackets表示写入文件的起始位置
        OSStatus status = AudioFileWritePackets(recoder.mRecordFile,
                                                FALSE,
                                                bufferList->mBuffers[0].mDataByteSize,
                                                &outputPacketDescriptions,
                                                recoder.mRecordPacket,
                                                &inNumPackets,
                                                bufferList->mBuffers[0].mData);
        //        log4cplus_info("write file","write file status = %d",(int)status);
        if (status == noErr) {
            recoder.mRecordPacket += inNumPackets;  // 用于记录起始位置
        }
    }
    
    return bufferList;
}

- (void)processAudioBuffer:(AudioQueueBufferRef)buffer withQueue:(AudioQueueRef) queue
{
    // Get DB
    float channelValue[2];
    caculate_bm_db(buffer->mAudioData, buffer->mAudioDataByteSize, 0, k_Mono, channelValue,true);
    self.volLDB = channelValue[0];
    self.volRDB = channelValue[1];
    
    // collect pcm data，可以在此存储
    // 由于PCM转成AAC的转换器每次需要有1024个采样点（每一帧2个字节）才能完成一次转换，所以每次需要2048大小的数据，这里定义的pcm_buffer用来累加每次存储的bufferData
    memcpy(pcm_buffer+pcm_buffer_size, buffer->mAudioData, buffer->mAudioDataByteSize);
    pcm_buffer_size = pcm_buffer_size + buffer->mAudioDataByteSize;
    
    if(pcm_buffer_size >= kFrameSize){
        AudioBufferList *bufferList = convertPCMToAAC(self);
        
        // 因为采样不可能每次都精准的采集到1024个样点，所以如果大于2048大小就先填满2048，剩下的跟着下一次采集一起送给转换器
        memcpy(pcm_buffer, pcm_buffer + kFrameSize, pcm_buffer_size - kFrameSize);
        pcm_buffer_size = pcm_buffer_size - kFrameSize;
        
        // free memory
        if(bufferList) {
            free(bufferList->mBuffers[0].mData);
            free(bufferList);
        }
    }
    
    if (buffer) {
        char *psrc = (char*)buffer->mAudioData;
        int bufLength = buffer->mAudioDataByteSize;
        
        if (self.delegate && [self.delegate respondsToSelector:@selector(processAudioPacket:length:)]) {
            [self.delegate processAudioPacket:psrc length:bufLength];
        }
    } else {
        NSLog(@"Audio Buffer is nil");
    }
    
}

- (void) dealloc {
    [self cleanUp];
    pthread_mutex_destroy(&_lock);
    [self removeNotifications];
}

- (void)cleanUp {
    if (_aqc.run != 0) {
        _aqc.run = 0;
        OSStatus status = AudioQueueStop(_aqc.queue, true);
        if (status != noErr) {
            for(int i = 0; i < kNumberBuffers; i++) {
                AudioQueueFreeBuffer(_aqc.queue, _aqc.mBuffers[i]);
            }
        }
        AudioQueueDispose(_aqc.queue, true);
        _aqc.queue = NULL;
    }
}


- (BOOL)isHeadsetPluggedIn {
    AVAudioSessionRouteDescription* route = [[AVAudioSession sharedInstance] currentRoute];
    for (AVAudioSessionPortDescription* desc in [route outputs]) {
        if ([[desc portType] isEqualToString:AVAudioSessionPortHeadphones])
            return YES;
    }
    return NO;
}

#pragma mark - notification

- (void)handleRouteChange:(NSNotification *)notification {
    //    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSString *seccReason = @"";
    NSInteger reason = [[[notification userInfo] objectForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
    //  AVAudioSessionRouteDescription* prevRoute = [[notification userInfo] objectForKey:AVAudioSessionRouteChangePreviousRouteKey];
    switch (reason) {
        case AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory:
            seccReason = @"The route changed because no suitable route is now available for the specified category.";
            break;
        case AVAudioSessionRouteChangeReasonWakeFromSleep:
        case AVAudioSessionRouteChangeReasonOverride:
        case AVAudioSessionRouteChangeReasonCategoryChange:
        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable: {
            seccReason = [NSString stringWithFormat:@"AVAudioSession Route change Reason is %ld (wakesleep:6,override:4,change:3,oldUnavailiable:2,newDevice:1)",(long)reason];
            //这里当route改变时(例如其他Audio Unit的三方类初始化,Session重置Mode,Category),可能会导致队列停止,没有数据输出，这里重置
            [self resetAudio];
        }
            
            break;
        case AVAudioSessionRouteChangeReasonUnknown:
        default:
            seccReason = @"The reason for the change is unknown.";
            break;
    }
    NSLog(@" handleRouteChange reason is %@", seccReason);
}

- (void)resetAudio {
    if (_aqc.run) {
        [self stop];
        [self start];
    }else {
        [self start];
    }
}

- (void)handleAudioSessionInterruption:(NSNotification*)notification {
    if (!self.isRunning) return;
    NSLog(@"handleAudioSessionInterruption:%@",notification);
    NSNumber *interruptionType = [[notification userInfo] objectForKey:AVAudioSessionInterruptionTypeKey];
    NSNumber *interruptionOption = [[notification userInfo] objectForKey:AVAudioSessionInterruptionOptionKey];
    
    switch (interruptionType.unsignedIntegerValue) {
        case AVAudioSessionInterruptionTypeBegan:{
            // • Audio has stopped, already inactive
            // • Change state of UI, etc., to reflect non-playing state
            if (_isBackground) {
                if (_isBackgroundAudioMode) {
                    [self stop]; //should stop whatever in background or app is not background audio type
                }
            }else{
                [self stop];
            }
            
            _isAudioInteruptBegan = YES;
        } break;
        case AVAudioSessionInterruptionTypeEnded:{
            // • Make session active
            // • Update user interface
            // • AVAudioSessionInterruptionOptionShouldResume option
            if (interruptionOption.unsignedIntegerValue == AVAudioSessionInterruptionOptionShouldResume) {
                // Here you should continue playback.
                // Apps that do not require user input to begin audio playback (such as games) can ignore this flag and always resume playback when an interruption ends.
                NSError *error;
                [[AVAudioSession sharedInstance] setActive:YES withOptions:kAudioSessionSetActiveFlag_NotifyOthersOnDeactivation error:&error];
                if (error) {
                    NSLog(@"error: %@", error.description);
                }
                if (_isBackground) { //如果是后台
                    //如果app适配后台播放音频模式,并且没有第二个app在占用音频
                    if (_isBackgroundAudioMode && ![AVAudioSession sharedInstance].secondaryAudioShouldBeSilencedHint) {
                        [self resetAudio];
                        _audioCookedValue = 1;
                    }else{
                        //没有重置的情况下，我们放在进入前台时重置
                        _audioCookedValue = 2;
                    }
                }else{ //if UITextView / UITextField audio entry interruped , need reset openal
                    [self resetAudio];
                    _audioCookedValue = 1;
                }
                
                NSLog(@"AVAudioSessionInterruptionOptionShouldResume");
            }else {
                if (![AVAudioSession sharedInstance].secondaryAudioShouldBeSilencedHint) {
                    if (_isBackground) {
                        if (_isBackgroundAudioMode) {
                            [self resetAudio];
                            _audioCookedValue = 1;
                        }else{
                            _audioCookedValue = 2;
                        }
                    }else{ //if UITextView / UITextField audio entry interruped , need reset openal
                        [self resetAudio];
                        _audioCookedValue = 1;
                    }
                    NSLog(@"AVAudioSessionInterruptionOptionKey is 0 - UnknowError");
                }else {
                    NSLog(@"secondaryAudioShouldBeSilencedHint is YES");
                }
            }
        }
            break;
        default:
            break;
    }
}

@end
