//
//  ViewController.m
//  AudioQueueRecordSample
//
//  Created by gensee on 2019/11/12.
//  Copyright © 2019年 haocai. All rights reserved.
//

#import "ViewController.h"
#import "GSMediaAuthor.h"
#import "GSAudioSendEngine.h"
#import "GSPCMWriter.h"
#import <AVKit/AVKit.h>
#import "GSOpenALUnit.h"
#import "MCSimpleAudioPlayer.h"

typedef enum : NSUInteger {
    PlayerStop = 0,
    PlayerPlay,
    PlayerPause,
} PlayerState;

@interface ViewController () <GSAudioSendEngineDelegate>
@property (weak, nonatomic) IBOutlet UILabel *timeLabel;
@property (weak, nonatomic) IBOutlet UILabel *pathLabel;

@property (nonatomic,strong) dispatch_source_t timer;
@property (nonatomic,assign) long count;

@property (nonatomic,strong) GSAudioSendEngine *engine;
@property (nonatomic,strong) GSPCMWriter *pcmWriter;

@property (weak, nonatomic) IBOutlet UIButton *startBtn;
@property (weak, nonatomic) IBOutlet UIButton *pauseBtn;
@property (weak, nonatomic) IBOutlet UIButton *stopBtn;
@property (nonatomic,assign) PlayerState state;

@property (nonatomic,strong) GSOpenALUnit *openALUnit;
@property (nonatomic,strong) NSInputStream *inputStream;

@property (nonatomic,strong) MCSimpleAudioPlayer *player;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    [GSMediaAuthor authorMicphone:nil];
    _engine = [GSAudioSendEngine shareAuidoSendEngine];
    _engine.delegate = self;
    
    _pcmWriter = [[GSPCMWriter alloc] init];
    [_pcmWriter clearAllPCM];
    [_pcmWriter resetPCMHandler];
    _state = 0;
    
    _openALUnit = [[GSOpenALUnit alloc] init];
    
    [self updateButtons];
}

- (IBAction)startRecord:(id)sender {
    if (_state == PlayerPlay) {
        return;
    }
    _state = PlayerPlay;
    [self.engine start];
    
    _pathLabel.text = [_pcmWriter getPCMHandler];
    [self updateButtons];
    
    if (!_timer) {
        __weak typeof(self) wself = self;
        _timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(_timer, DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC, 1 * NSEC_PER_SEC);
        dispatch_source_set_event_handler(_timer, ^{
            if (wself.state == PlayerPlay) {
                wself.count++;
                wself.timeLabel.text = [NSString stringWithFormat:@"%02ld:%02ld:%02ld",wself.count/3600,wself.count/60,wself.count];
            }
        });
        dispatch_resume(_timer);
    }
}
- (IBAction)pauseRecord:(id)sender {
    if (_state == PlayerPlay) {
        _state = 2;
        [self.engine pause];
        dispatch_suspend(_timer);
        [self updateButtons];
    }
}
- (IBAction)stopRecord:(id)sender {
    if (_state == PlayerPlay || _state == PlayerPause) {
        _state = PlayerStop;
        [self.engine stop];
        dispatch_source_cancel(_timer);
        _timer = nil;
        [self updateButtons];
        
    }
}

- (void)updateButtons {
    if (_state == PlayerPlay) {
        _startBtn.backgroundColor = [UIColor groupTableViewBackgroundColor];
        _stopBtn.backgroundColor = [UIColor greenColor];
        _pauseBtn.backgroundColor = [UIColor greenColor];
    }else if (_state == PlayerPause) {
        _pauseBtn.backgroundColor = [UIColor groupTableViewBackgroundColor];
        _stopBtn.backgroundColor = [UIColor greenColor];
        _startBtn.backgroundColor = [UIColor greenColor];
    }else{
        _stopBtn.backgroundColor = [UIColor groupTableViewBackgroundColor];
        _pauseBtn.backgroundColor = [UIColor groupTableViewBackgroundColor];
        _startBtn.backgroundColor = [UIColor greenColor];
    }
}

- (IBAction)playAction:(id)sender {
    NSString *path = [_pcmWriter getPCMHandler];
    BOOL isExist = [[NSFileManager defaultManager] fileExistsAtPath:path];
    NSLog(@"play pcm : %@, isExist : %d",path,isExist);
    
    _player = [[MCSimpleAudioPlayer alloc] initWithFilePath:path fileType:0];
    [_player play];
}



- (void)processAudioPacket:(char *)data length:(int)len {
    if (len > 0) {
        NSLog(@"write pcm data : %d",len);
        [_pcmWriter writePCM:data length:len];
    }
}

@end
