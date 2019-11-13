//
//  GSMediaAuthor.m
//  GSCommonKit
//
//  Created by gensee on 2018/10/23.
//  Copyright © 2018年 gensee. All rights reserved.
//

#import "GSMediaAuthor.h"
#import <AVFoundation/AVFoundation.h>
@implementation GSMediaAuthor

+ (void)authorCamera:(void (^ __nullable)(BOOL granted))completion{
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    if(authStatus == AVAuthorizationStatusAuthorized) {
        if (completion) {
            completion(YES);
        }
        // do your logic
    } else if(authStatus == AVAuthorizationStatusDenied){
        if (completion) {
            completion(NO);
        }
        // denied
    } else if(authStatus == AVAuthorizationStatusRestricted){
        // restricted, normally won't happen
    } else if(authStatus == AVAuthorizationStatusNotDetermined){
        // not determined?!
        //                    dispatch_async(dispatch_get_main_queue(), ^{
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:completion];
        
    } else {
        // impossible, unknown authorization status
    }
}

+ (void)authorMicphone:(void (^ __nullable)(BOOL granted))completion{
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio];
    if(authStatus == AVAuthorizationStatusAuthorized) {
        if (completion) {
            completion(YES);
        }
        // do your logic
    } else if(authStatus == AVAuthorizationStatusDenied){
        if (completion) {
            completion(NO);
        }
    } else if(authStatus == AVAuthorizationStatusRestricted){
        // restricted, normally won't happen
    } else if(authStatus == AVAuthorizationStatusNotDetermined){
        // not determined?!
        //                    dispatch_async(dispatch_get_main_queue(), ^{
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:completion];
        
    } else {
        // impossible, unknown authorization status
    }
}

@end
