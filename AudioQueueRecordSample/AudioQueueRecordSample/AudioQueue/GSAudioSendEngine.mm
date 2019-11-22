//AudioQueueRecordSample code for study


#import "GSAudioSendEngine.h"
#import <AVFoundation/AVFoundation.h>
#import "GSNotificationManager.h"
#import <UIKit/UIKit.h>
#import <pthread.h>

#import "AACEncoder.h"

#define kXDXRecoderAudioBytesPerPacket      2
#define kXDXRecoderAACFramesPerPacket       1024


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
@property (nonatomic , strong) AACEncoder *mAudioEncoder;

@end


@implementation GSAudioSendEngine
{
    BOOL _isBackgroundAudioMode;  //表示是否app打开后台模式
    BOOL _isAudioInteruptBegan;   //表示是否音频打断开始
    BOOL _isBackground;  //表示是否在后台
    int _audioCookedValue;  // 1 表示音频打断处理过 0 表示不处理  2表示音频已经打断，但由于非后台模式等原因未处理
    GSNotificationManager *notificationMananger; //通知处理类 - 可用NSNotification替换

}


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
        self.mAudioEncoder = [[AACEncoder alloc] init];
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


- (void)processAudioBuffer:(AudioQueueBufferRef)buffer withQueue:(AudioQueueRef) queue
{
//    if (buffer) {
//        [_mAudioEncoder encodeAudioQueueBuffer:buffer inputDesc:_aqc.mDataFormat completionBlock:^(NSData *encodedData, NSError *error) {
//            if (self.delegate && [self.delegate respondsToSelector:@selector(processAudioPacket:length:)]) {
//                [self.delegate processAudioPacket:(char*)encodedData.bytes length:(int)encodedData.length];
//            }
//        }];
//    }
    
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
