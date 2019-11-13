//
//  GSLiveAudioConfiguration.h
//  LFLiveKit
//
//  Created by LaiFeng on 16/5/20.
//  Copyright © 2016年 LaiFeng All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
/// 音频码率 (默认96Kbps)
typedef NS_ENUM (NSUInteger, GSLiveAudioBitRate) {
    /// 32Kbps 音频码率
    GSLiveAudioBitRate_32Kbps = 32000,
    /// 64Kbps 音频码率
    GSLiveAudioBitRate_64Kbps = 64000,
    /// 96Kbps 音频码率
    GSLiveAudioBitRate_96Kbps = 96000,
    /// 128Kbps 音频码率
    GSLiveAudioBitRate_128Kbps = 128000,
    /// 默认音频码率，默认为 96Kbps
    GSLiveAudioBitRate_Default = GSLiveAudioBitRate_96Kbps
};

/// 音频采样率 (默认44.1KHz)
typedef NS_ENUM (NSUInteger, GSLiveAudioSampleRate){
    /// 16KHz 采样率
    GSLiveAudioSampleRate_16000Hz = 16000,
    /// 44.1KHz 采样率
    GSLiveAudioSampleRate_44100Hz = 44100,
    /// 48KHz 采样率
    GSLiveAudioSampleRate_48000Hz = 48000,
    /// 默认音频采样率，默认为 44.1KHz
    GSLiveAudioSampleRate_Default = GSLiveAudioSampleRate_44100Hz
};

///  Audio Live quality（音频质量）
typedef NS_ENUM (NSUInteger, GSLiveAudioQuality){
    /// 低音频质量 audio sample rate: 16KHz audio bitrate: numberOfChannels 1 : 32Kbps  2 : 64Kbps
    GSLiveAudioQuality_Low = 0,
    /// 中音频质量 audio sample rate: 44.1KHz audio bitrate: 96Kbps
    GSLiveAudioQuality_Medium = 1,
    /// 高音频质量 audio sample rate: 44.1MHz audio bitrate: 128Kbps
    GSLiveAudioQuality_High = 2,
    /// 超高音频质量 audio sample rate: 48KHz, audio bitrate: 128Kbps
    GSLiveAudioQuality_VeryHigh = 3,
    /// 默认音频质量 audio sample rate: 44.1KHz, audio bitrate: 96Kbps
    GSLiveAudioQuality_Default = GSLiveAudioQuality_High
};

@interface GSLiveAudioConfiguration : NSObject<NSCoding, NSCopying>

/// 默认音频配置
+ (instancetype)defaultConfiguration;
/// 音频配置
+ (instancetype)defaultConfigurationForQuality:(GSLiveAudioQuality)audioQuality;

#pragma mark - Attribute
///=============================================================================
/// @name Attribute
///=============================================================================
/// 声道数目(default 2)
@property (nonatomic, assign) NSUInteger numberOfChannels;
/// 采样率
@property (nonatomic, assign) GSLiveAudioSampleRate audioSampleRate;
/// 码率
@property (nonatomic, assign) GSLiveAudioBitRate audioBitrate;
/// flv编码音频头 44100 为0x12 0x10
@property (nonatomic, assign, readonly) char *asc;
/// 缓存区长度
@property (nonatomic, assign,readonly) NSUInteger bufferLength;

/**
 音频session设置AVAudioSessionCategoryOptions 默认为 AVAudioSessionCategoryOptionDefaultToSpeaker|AVAudioSessionCategoryOptionAllowBluetooth|AVAudioSessionCategoryOptionMixWithOthers
 */
@property (nonatomic, assign) AVAudioSessionCategoryOptions sessionCategoryOption;
@end
