//
//  GSOpenALUnit.m
//  GSCommonKit
//
//  Created by gensee on 2019/9/6.
//  Copyright © 2019年 gensee. All rights reserved.
//

#import "GSOpenALUnit.h"
#import <UIKit/UIKit.h>
#import <pthread.h>
#import <AVFoundation/AVFoundation.h>
#import <OpenAL/al.h>
#import <OpenAL/alc.h>
#import "GSPCMWriter.h"

#define PCMWrite 0

#define MaxBufferCount 16

static NSString* openAlErrorToString(int err) {
    switch (err) {
        case AL_NO_ERROR: return @"AL_NO_ERROR";
        case AL_INVALID_NAME: return @"AL_INVALID_NAME";
        case AL_INVALID_ENUM: return @"AL_INVALID_ENUM";
        case AL_INVALID_VALUE: return @"AL_INVALID_VALUE";
        case AL_INVALID_OPERATION: return @"AL_INVALID_VALUE";
        case AL_OUT_OF_MEMORY: return @"AL_OUT_OF_MEMORY";
            /* ... */
        default:
            return [NSString stringWithFormat:@"Unknown error code:%d",err];
    }
}

@implementation GSOpenALUnit {
    BOOL isRunning;
    BOOL isInit;
    dispatch_queue_t m_taskQueue;
    ALuint m_outSourceID;
    ALCcontext *m_mContext;  //声音环境
    ALCdevice *m_mDevice;   //声音设备
    
    pthread_mutex_t m_openalMutex;
    
    NSOperationQueue *m_operationQueue;
    
    BOOL m_isAudioInterupt;//进入前台时判断是否音频打断处理过openal
    BOOL m_isAudioInteruptBegan;//是否打断开始用于阻止数据加入队列
    BOOL m_isBackgroundAudioMode;//是否后台播放模式 audio
    BOOL m_isNeedResetCategory; //是否audio categroy变动
    BOOL m_isBackground; //是否处于后台
    
    
    int64_t m_lastLogTime;
    
    int64_t m_lastFrameTime;
    int64_t m_frameCount;
#if PCMWrite
    GSPCMWriter *pcmWriter;
#endif
    dispatch_source_t m_loopTimer;
    dispatch_queue_t m_loopQueue;
    
    int m_queueLength; //记录下queuelength，未初始化的时候返回该值
    BOOL headphonesConnected; //耳机连接
    
    ALuint *m_audioQueueBuffer;
    
    UInt32 m_fillBufferIndex;                                        // the index of the audioQueueBuffer that is being filled
    UInt32 m_bytesFilled;                                            // how many bytes have been filled
    UInt32 m_packetsFilled;                                          // how many packets have been filled
    UInt32 m_buffersUsed;                                            // how many buffers are used
    bool *m_bufferInUse;                                  // flags to indicate that a buffer is still in use
    pthread_mutex_t m_bufferInUseMutex;
    pthread_cond_t m_bufferFreeCondition;
}


@synthesize running = _running;
@synthesize sessionCategoryOption = _sessionCategoryOption;

- (instancetype)init {
    if (self = [super init]) {
        m_queueLength = 0;
        m_taskQueue = dispatch_queue_create("com.gensee.openAL.Queue", DISPATCH_QUEUE_SERIAL);
//        isInit = NO;
        m_isAudioInterupt = NO;
        m_isBackgroundAudioMode = NO;
//        _isWriteToPCM = YES;
        //检测后台模式 是否有后台播放audio支持
        NSDictionary *infoDic = [NSBundle mainBundle].infoDictionary;
        NSArray *modes = [infoDic objectForKey:@"UIBackgroundModes"];
        if (modes && modes.count > 0) {
            for (NSString *tmp in modes) {
                if ([tmp isEqualToString:@"audio"]) {
                    m_isBackgroundAudioMode = YES;
                    break;
                }
            }
        }
#if PCMWrite
        pcmWriter = [[GSPCMWriter alloc] init];
#endif
        if (pthread_mutex_init(&m_openalMutex, NULL) != 0) {
            NSLog(@"openal mutex lock create failed");
        }
        
        
        m_operationQueue = [[NSOperationQueue alloc] init];
        m_operationQueue.maxConcurrentOperationCount = 1;
        m_operationQueue.qualityOfService = NSQualityOfServiceUserInitiated;
        m_lastFrameTime = 0;
        _sessionCategoryOption = AVAudioSessionCategoryOptionDefaultToSpeaker |AVAudioSessionCategoryOptionAllowBluetooth|AVAudioSessionCategoryOptionMixWithOthers;
        
        __weak typeof(self) wself = self;
        m_loopQueue = dispatch_queue_create("com.gensee.openal.loopQueue", DISPATCH_QUEUE_SERIAL);
        m_loopTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, m_loopQueue);
        dispatch_source_set_timer(m_loopTimer, dispatch_time(DISPATCH_TIME_NOW, (80 * NSEC_PER_MSEC)), (80 * NSEC_PER_MSEC), 0);
        dispatch_source_set_event_handler(m_loopTimer, ^{
            [wself loopEvent];
        });
        
        
        m_audioQueueBuffer = new ALuint[MaxBufferCount];
        m_bufferInUse = new bool[MaxBufferCount];
        if (pthread_mutex_init(&m_bufferInUseMutex, NULL) != 0) {
            NSLog(@"bufferInUse mutex lock create failed");
        }
        
        if (pthread_cond_init(&m_bufferFreeCondition, NULL) != 0) {
            NSLog(@"bufferFreeCondition cond create failed");
        }
    }
    return self;
}

- (void)loopEvent {
    ALint processed;
    alGetSourcei(m_outSourceID, AL_BUFFERS_PROCESSED, &processed);
    while (processed--) {
        ALuint bufferID;
        alSourceUnqueueBuffers(m_outSourceID, 1, &bufferID);
        int bufIndex = -1;
        for (unsigned int i = 0; i < MaxBufferCount; ++i) {
            if (bufferID == m_audioQueueBuffer[i]) {
                bufIndex = i;
                break;
            }
        }
        if (bufIndex == -1) {
            continue;
        }
        //            NSLog(@"alSourceUnqueueBuffers index = %d",bufIndex);
        pthread_mutex_lock(&m_bufferInUseMutex);
        m_bufferInUse[bufIndex] = false;
        m_buffersUsed--;
        pthread_cond_signal(&m_bufferFreeCondition);
        pthread_mutex_unlock(&m_bufferInUseMutex);
    }
}

- (void)registerNotificationObserver {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSNotificationCenter *noficationCenter = [NSNotificationCenter defaultCenter];
    [noficationCenter addObserver: self
                         selector: @selector(handleInterruption:)
                             name: AVAudioSessionInterruptionNotification
                           object: session];
    [noficationCenter addObserver:self
                         selector:@selector(appDidBecomeActive)
                             name:UIApplicationDidBecomeActiveNotification
                           object:nil];
    
    [noficationCenter addObserver:self
                         selector:@selector(appWillResignActive)
                             name:UIApplicationWillResignActiveNotification object:nil];
    [noficationCenter addObserver:self selector:@selector(otherAppActiveSession:) name:AVAudioSessionSilenceSecondaryAudioHintNotification object:session];
}

- (void)unregisterNotificationObserver {
    NSNotificationCenter *noficationCenter = [NSNotificationCenter defaultCenter];
    [noficationCenter removeObserver:self name:AVAudioSessionInterruptionNotification object:nil];
    [noficationCenter removeObserver:self name:UIApplicationDidBecomeActiveNotification object:nil];
    [noficationCenter removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
    [noficationCenter removeObserver:self name:AVAudioSessionSilenceSecondaryAudioHintNotification object:nil];
}

- (void)setRunning:(BOOL)running {
    if (_running == running) return;
    _running = running;
    if (_running) {
        isRunning = YES;
        NSLog(@"Openal : startRunning categoryOption : %u",(unsigned int)_sessionCategoryOption);
        [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord
                                         withOptions:_sessionCategoryOption
                                               error:nil];
        [self play];
        [self registerNotificationObserver];
        if (m_loopTimer) dispatch_resume(m_loopTimer); //resume 导致计数-1
    } else {
        isRunning = NO;
        NSLog(@"Openal : stopRunning");
        [self stop];
        [self cleanQueuedBuffers];
        [self unregisterNotificationObserver];
        if (m_loopTimer) dispatch_suspend(m_loopTimer); //suspend 导致计数+1，当计数大于1时，定时器就不会开始，所以要保证调用次序要成对对应
    }
}

- (void)dealloc {
    delete []m_audioQueueBuffer;
    delete []m_bufferInUse;
    pthread_mutex_destroy(&m_openalMutex);
    pthread_mutex_destroy(&m_bufferInUseMutex);
    pthread_cond_destroy(&m_bufferFreeCondition);
    dispatch_source_cancel(m_loopTimer);
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


#pragma mark - protocol

- (void)cleanProcessdBuffers; {
    __weak typeof(self) wself = self;
    [m_operationQueue addOperationWithBlock:^{
        [wself _cleanProcessdBuffers];
    }];
}

- (void)_cleanProcessdBuffers {
    if (isInit) {
        ALint processed;
        alGetSourcei(m_outSourceID, AL_BUFFERS_PROCESSED, &processed);
        while (processed--) {
            ALuint bufferID;
            alSourceUnqueueBuffers(m_outSourceID, 1, &bufferID);
            int bufIndex = -1;
            for (unsigned int i = 0; i < MaxBufferCount; ++i) {
                if (bufferID == m_audioQueueBuffer[i]) {
                    bufIndex = i;
                    break;
                }
            }
            if (bufIndex == -1) {
                continue;
            }
            //            NSLog(@"alSourceUnqueueBuffers index = %d",bufIndex);
            pthread_mutex_lock(&m_bufferInUseMutex);
            m_bufferInUse[bufIndex] = false;
            m_buffersUsed--;
            pthread_cond_signal(&m_bufferFreeCondition);
            pthread_mutex_unlock(&m_bufferInUseMutex);
        }
    }
}

- (void)cleanQueuedBuffers { 
    [m_operationQueue cancelAllOperations];
    __weak typeof(self) wself = self;
    [m_operationQueue addOperationWithBlock:^{
        [wself _cleanQueuedBuffers];
    }];
}

- (void)_cleanQueuedBuffers {
    ALint processed;
    alGetSourcei(m_outSourceID, AL_BUFFERS_QUEUED, &processed);
    NSLog(@"[OpenAL] : cleanQueuedBuffers count : %d",processed);
    while (processed--) {
        ALuint bufferID;
        alSourceUnqueueBuffers(m_outSourceID, 1, &bufferID);
        //        alDeleteBuffers(1, &bufferID);
        int bufIndex = -1;
        for (unsigned int i = 0; i < MaxBufferCount; ++i) {
            if (bufferID == m_audioQueueBuffer[i]) {
                bufIndex = i;
                break;
            }
        }
        if (bufIndex == -1) {
            break;
        }
        pthread_mutex_lock(&m_bufferInUseMutex);
        m_bufferInUse[bufIndex] = false;
        m_buffersUsed--;
        //将数据存入缓存区
        alBufferData(m_audioQueueBuffer[bufIndex], AL_FORMAT_MONO16, NULL, 0, 16000);
        pthread_cond_signal(&m_bufferFreeCondition);
        pthread_mutex_unlock(&m_bufferInUseMutex);
    }
}

- (void)printDebugInfo {
    ALint queued;
    ALint processed;
    alGetSourcei(m_outSourceID, AL_BUFFERS_PROCESSED, &processed);
    alGetSourcei(m_outSourceID, AL_BUFFERS_QUEUED, &queued);
    NSLog(@"[GSOpenAL] process = %d, queued = %d", processed, queued);
}

- (void)refresh { 
    __weak typeof(self) wself = self;
    [m_operationQueue addOperationWithBlock:^{
        [wself _initOpenal];
    }];
}

- (void)_initOpenal {
    //    pthread_mutex_lock(&_lock);
#if PCMWrite
    [pcmWriter resetPCMHandler];
#endif
    
    if (isInit) {
        NSLog(@"must clean before init");
        return;
    }
    NSError *error = nil;
    [[AVAudioSession sharedInstance] setActive:YES error:&error];
    if (error) {
        NSLog(@"initOpenAL setActive error : %@",error);
    }
    NSLog(@"initOpenAL start");
    if (!m_mDevice) {
        pthread_mutex_lock(&m_openalMutex);
        m_mDevice = alcOpenDevice(NULL);
        pthread_mutex_unlock(&m_openalMutex);
        // 得到设备说明.
        printf("[GSOpenALHelper] Using device '%s' \n", alcGetString(m_mDevice, ALC_DEVICE_SPECIFIER));
    }
    if (!m_mDevice) {
        NSLog(@"initOpenAL failed: device is NULL");
        pthread_mutex_lock(&m_openalMutex);
        isInit = NO;
        pthread_mutex_unlock(&m_openalMutex);
        return;
    }
    if (!m_mContext) {
        pthread_mutex_lock(&m_openalMutex);
        m_mContext = alcCreateContext(m_mDevice, NULL);
        alcMakeContextCurrent(m_mContext);
        pthread_mutex_unlock(&m_openalMutex);
    }
    //创建音源
    alGenSources(1, &m_outSourceID);
    //设置播放速度, (无效, 不知道为何)
    alSpeedOfSound(1.0f);
    //设为不循环
    alSourcei(m_outSourceID, AL_LOOPING, AL_FALSE);
    //播放模式设为流式播放
    alSourcef(m_outSourceID, AL_SOURCE_TYPE, AL_STREAMING);
    //设置播放音量
    alSourcef(m_outSourceID, AL_PITCH, 1.0f);
    alSourcef(m_outSourceID, AL_GAIN, 1.f);
    //清除错误
    alGetError();
    
    if (!m_mContext) {
        NSLog(@"initOpenAL failed: context is NULL");
        pthread_mutex_lock(&m_openalMutex);
        isInit = NO;
        pthread_mutex_unlock(&m_openalMutex);
        return;
    }
    
    m_fillBufferIndex = 0;
    m_bytesFilled = 0;
    m_packetsFilled = 0;
    m_buffersUsed = 0;
    
    alGenBuffers(MaxBufferCount, m_audioQueueBuffer);
    
    for (size_t i=0; i < MaxBufferCount; i++) {
        m_bufferInUse[i] = false;
    }
    pthread_mutex_lock(&m_openalMutex);
    isInit = YES;
    pthread_mutex_unlock(&m_openalMutex);
    NSLog(@"initOpenAL end");
}

//获取当前未处理队列长度
- (unsigned int)unprocessdNumber {
    if (!isInit) {
        if (m_queueLength > 1000) {
            NSLog(@"m_queueLength > 1000");
        }
        return m_queueLength;
    }
    ALint queueLength;
    alGetSourcei(m_outSourceID, AL_BUFFERS_QUEUED, &queueLength);
    
    ALint processed;
    alGetSourcei(m_outSourceID, AL_BUFFERS_PROCESSED, &processed);
    if (m_queueLength > processed) {
        m_queueLength = queueLength - processed;
        if (m_queueLength > 1000) {
            NSLog(@"m_queueLength > 1000");
        }
        return m_queueLength;
    }else {
        return 0;
    }
}

- (void)insertPCMDataToQueue:(const unsigned char *)data size:(UInt32)size
{
    int64_t current = (int64_t)CACurrentMediaTime();
    int64_t delta   = (current > m_lastLogTime) ? current - m_lastLogTime : 0;
    if (m_lastLogTime == 0 || delta >= 10) {
        m_lastLogTime = current;
        if (!isRunning) { //未初始化和run时不加入队列
            NSLog(@"!isRunning");
            return;
        }
        
        if (!isInit) {
            NSLog(@"!isInit");
        }
        if (m_isBackground && !m_isBackgroundAudioMode) { //非后台模式下 后台时不加入队列
            NSLog(@"_isBackground && !_isBackgroundAudioMode");
            return;
        }
        if (m_isAudioInteruptBegan) { //音频打断开始
            NSLog(@"_isAudioInteruptBegan");
            return;
        }
    }
    __weak typeof(self) wself = self;
    NSMutableData *dataObj = [NSMutableData dataWithBytes:data length:size];
    [m_operationQueue addOperationWithBlock:^{
        [wself _insertPCM:dataObj];
    }];
}

- (void)_insertPCM:(NSMutableData *)data{
    if (data == nil) {
        NSLog(@"data is nil");
        return;
    }
#if PCMWrite
    if (pcmWriter) {
        [pcmWriter writePCM:(void*)data.bytes length:data.length];
    }
#endif
    int64_t current = (int64_t)CACurrentMediaTime();
    int64_t delta   = (current > m_lastFrameTime) ? current - m_lastFrameTime : 0;
    if (delta <= 0) {
        m_lastFrameTime = current;
    } else if (delta >= 10) {
        if (data.length <= 1) {
            NSLog(@"PCM size <= 1");
        }
        m_lastFrameTime = current;
        CGFloat fps = ((CGFloat)m_frameCount) / delta;
        NSLog(@"insertPCM count : %lld fps : %.02f",m_frameCount,fps);
        m_frameCount = 0;
    }else{
        m_frameCount ++;
    }
    
    pthread_mutex_lock(&m_bufferInUseMutex);
    m_bufferInUse[m_fillBufferIndex] = true;
    m_buffersUsed++;
    //将数据存入缓存区
    alBufferData(m_audioQueueBuffer[m_fillBufferIndex], AL_FORMAT_MONO16, (char *)data.bytes, (ALsizei)data.length, 16000);
    
    
    alSourceQueueBuffers(m_outSourceID, 1, &m_audioQueueBuffer[m_fillBufferIndex]);
    
    [self play];
    
    if (++m_fillBufferIndex >= MaxBufferCount) {
        m_fillBufferIndex = 0;
    }
    
    while (m_bufferInUse[m_fillBufferIndex]) {
        NSLog(@"Queue Buffer Wait Begin %u buffer in Use",(unsigned int)m_fillBufferIndex);
        pthread_cond_wait(&m_bufferFreeCondition, &m_bufferInUseMutex);
        NSLog(@"Queue Buffer Wait End %u buffer in Use",(unsigned int)m_fillBufferIndex);
    }
    pthread_mutex_unlock(&m_bufferInUseMutex);
}

- (void)play
{
    ALint state;
    alGetSourcei(m_outSourceID, AL_SOURCE_STATE, &state);
    
    if (state != AL_PLAYING) {
        alSourcePlay(m_outSourceID);
        NSLog(@"play");
    }
}

- (void)stop
{
    pthread_mutex_lock(&m_bufferInUseMutex);
    pthread_cond_signal(&m_bufferFreeCondition);
    pthread_mutex_unlock(&m_bufferInUseMutex);
    ALint state;
    alGetSourcei(m_outSourceID, AL_SOURCE_STATE, &state);
    
    if (state != AL_STOPPED) {
        alSourceStop(m_outSourceID);
        NSLog(@"stop");
    }
}

- (void)clean {
    NSLog(@"clean");
    [m_operationQueue cancelAllOperations];
    m_queueLength = 0;
    [self cleanQueuedBuffers];
    __weak typeof(self) wself = self;
    [m_operationQueue addOperationWithBlock:^{
        [wself _cleanSource];
    }];
}

- (void)_cleanSource {
    NSLog(@"_cleanSource");
    pthread_mutex_lock(&m_openalMutex);
    //删除声源
    alDeleteSources(1, &m_outSourceID);
    if (m_mContext) {
        //删除环境
        alcDestroyContext(m_mContext);
        m_mContext = nil;
        NSLog(@"destroy context");
    }
    if (m_mDevice) {
        //关闭设备
        alcCloseDevice(m_mDevice);
        m_mDevice = nil;
        NSLog(@"destroy mDevice");
    }
    
    isInit = NO;
    pthread_mutex_unlock(&m_openalMutex);
}

- (void)prepare {
    m_isAudioInteruptBegan = NO;
}

#pragma mark - notification

#pragma mark -- NSNotification

- (void)otherAppActiveSession:(NSNotification *)notification {
    NSInteger reason = [[[notification userInfo] objectForKey:AVAudioSessionSilenceSecondaryAudioHintTypeKey] integerValue];
    if (reason == AVAudioSessionSilenceSecondaryAudioHintTypeBegin) {
        NSLog(@"AVAudioSessionSilenceSecondaryAudioHintTypeBegin");
    }else if (reason == AVAudioSessionSilenceSecondaryAudioHintTypeEnd) {
        NSLog(@"AVAudioSessionSilenceSecondaryAudioHintTypeEnd");
    }
}

- (void)handleRouteChange:(NSNotification *)notification {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSString *seccReason = @"";
    NSInteger reason = [[[notification userInfo] objectForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
    //  AVAudioSessionRouteDescription* prevRoute = [[notification userInfo] objectForKey:AVAudioSessionRouteChangePreviousRouteKey];
    switch (reason) {
        case AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory:
            seccReason = @"The route changed because no suitable route is now available for the specified category.";
            break;
        case AVAudioSessionRouteChangeReasonWakeFromSleep:
            seccReason = @"The route changed when the device woke up from sleep.";
            break;
        case AVAudioSessionRouteChangeReasonOverride:
            seccReason = @"The output route was overridden by the app.";
            break;
        case AVAudioSessionRouteChangeReasonCategoryChange:
        {
            seccReason = @"The category of the session object changed.";
            if (![session.category isEqualToString:AVAudioSessionCategoryPlayAndRecord]) {
                m_isNeedResetCategory = YES;
                seccReason = @"The category of the session object changed. not 13";
            }
        }
            
            break;
        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable: {
            seccReason = @"The previous audio output path is no longer available.";
            AVAudioSessionRouteDescription *previousRoute = [[notification userInfo] objectForKey:AVAudioSessionRouteChangePreviousRouteKey];
            for (AVAudioSessionPortDescription *output in previousRoute.outputs) {
                if (output.portType == AVAudioSessionPortHeadphones) { //耳机
                    headphonesConnected = NO;
                }
            }
        }
            break;
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable: {
            seccReason = @"A preferred new audio output path is now available.";
            for (AVAudioSessionPortDescription *output in session.currentRoute.outputs) {
                if (output.portType == AVAudioSessionPortHeadphones) { //耳机
                    headphonesConnected = YES;
                }
            }
        }
            
            break;
        case AVAudioSessionRouteChangeReasonUnknown:
        default:
            seccReason = @"The reason for the change is unknown.";
            break;
    }
    NSLog(@"handleRouteChange reason is %@", seccReason);
    
    AVAudioSessionPortDescription *input = [[session.currentRoute.inputs count] ? session.currentRoute.inputs : nil objectAtIndex:0];
    AVAudioSessionPortDescription *output = [[session.currentRoute.outputs count] ? session.currentRoute.outputs : nil objectAtIndex:0];
    if (input.portType == AVAudioSessionPortHeadsetMic) {
        
    }
    NSLog(@"inport port type is %@", input.portType);
    NSLog(@"output port type is %@", output.portType);
}

- (void)handleInterruption:(NSNotification *)notification {
    NSInteger reason = 0;
    NSString *reasonStr = @"";
    if ([notification.name isEqualToString:AVAudioSessionInterruptionNotification]) {
        //Posted when an audio interruption occurs.
        if (@available(iOS 10.3, *)) {
            BOOL isSuspend = [[[notification userInfo] objectForKey:AVAudioSessionInterruptionWasSuspendedKey] boolValue];
            if (isSuspend) {
                NSLog(@"AVAudioSessionInterruptionWasSuspendedKey is YES");
                return;
            }
        } else {
            // Fallback on earlier versions
        }
        reason = [[[notification userInfo] objectForKey:AVAudioSessionInterruptionTypeKey] integerValue];
        if (reason == AVAudioSessionInterruptionTypeBegan ) { //在非后台模式下  打断处理 - 后台打断处理会导致底层线程卡死
            reasonStr = @"AVAudioSessionInterruptionTypeBegan";
            NSLog(@"cleanOpenal");
            if (m_isBackground) {
                if (m_isBackgroundAudioMode) {
                    [self stop]; //should stop whatever in background or app is not background audio type
                }
            }else{
                [self stop];
            }
            
            m_isAudioInteruptBegan = YES;
        }
        
        if (reason == AVAudioSessionInterruptionTypeEnded) {
            m_isAudioInteruptBegan = NO;
            reasonStr = @"AVAudioSessionInterruptionTypeEnded";
            NSNumber *seccondReason = [[notification userInfo] objectForKey:AVAudioSessionInterruptionOptionKey];
            switch ([seccondReason integerValue]) {
                case AVAudioSessionInterruptionOptionShouldResume:{ //在非后台模式下  打断处理 - 后台打断处理会导致底层线程卡死
                    reasonStr = @"AVAudioSessionInterruptionTypeEnded - AVAudioSessionInterruptionOptionShouldResume ";
                    if (m_isBackground) {
                        if (m_isBackgroundAudioMode && ![AVAudioSession sharedInstance].secondaryAudioShouldBeSilencedHint) {
                            NSLog(@"initOpenal for interruption");
                            m_isAudioInterupt = YES;
                            [self clean];
                            [self refresh];
                        }else{
                            m_isAudioInterupt = NO;
                        }
                    }else{ //if UITextView / UITextField audio entry interruped , need reset openal
                        [self clean];
                        [self refresh];
                    }
                    
                }
                case 0:{
                    reasonStr = @"AVAudioSessionInterruptionTypeEnded - UnknowError";
                    if (![AVAudioSession sharedInstance].secondaryAudioShouldBeSilencedHint) {
                        if (m_isBackground) {
                            if (m_isBackgroundAudioMode ) {
                                NSLog(@"initOpenal for interruption");
                                m_isAudioInterupt = YES;
                                [self clean];
                                [self refresh];
                            }else{
                                m_isAudioInterupt = NO;
                            }
                        }else{ //if UITextView / UITextField audio entry interruped , need reset openal
                            [self clean];
                            [self refresh];
                        }
                    }else {
                        NSLog(@"secondaryAudioShouldBeSilencedHint is YES");
                    }
                }
                    // Indicates that the audio session is active and immediately ready to be used. Your app can resume the audio operation that was interrupted.
                    break;
                default:
                    break;
            }
        }
    }
    
    NSLog(@"handleInterruption: %@ reason %@", notification, reasonStr);
}

- (void)appDidBecomeActive {
    m_isBackground = NO;
    m_isAudioInteruptBegan = NO;//进入前台就认为没有音频打断了
    
    BOOL success;
    NSError* error;
    AVAudioSession* session = [AVAudioSession sharedInstance];
    if (session.category != AVAudioSessionCategoryPlayAndRecord) {
        success = [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord
                                                   withOptions:_sessionCategoryOption
                                                         error:nil];
        if (!success) NSLog(@"AVAudioSession error activating: %@",error);
    }
    
    if (session.mode != AVAudioSessionModeDefault) {
        success = [session setMode:AVAudioSessionModeDefault error:&error];
        if (!success) NSLog(@"AVAudioSession setMode error: %@",error);
    }
    
    if (m_isNeedResetCategory) {
        NSLog(@"resetCategory");
        [[AVAudioSession sharedInstance] setActive:YES error:nil];
    }
    
    if (!m_isAudioInterupt) {
        NSLog(@"resetOpenal");
        [self stop];
        [self clean];
        [self refresh];
    }
    m_isAudioInterupt = NO;
    if (!m_isBackgroundAudioMode) {
        [[AVAudioSession sharedInstance] setActive:YES error:nil];
        //to avoid receive notification interrupt start , and resume audio session
    }else {
        
    }
}

- (void)appWillResignActive {
    m_isBackground = YES;
    if (!m_isBackgroundAudioMode) {
        [self stop];
        NSError *error = nil;
        if (![AVAudioSession sharedInstance].secondaryAudioShouldBeSilencedHint) {
            NSLog(@"AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation");
            [[AVAudioSession sharedInstance] setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&error];
        }
        
        if (error) {
            NSLog(@"inactive session error %@",error.description);
        }
        //to avoid receive notification interrupt start,option kAudioSessionSetActiveFlag_NotifyOthersOnDeactivation is need
    }
    
}


@end
