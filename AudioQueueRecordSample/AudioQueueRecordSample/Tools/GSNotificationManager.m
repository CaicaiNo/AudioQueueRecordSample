//
//  GSNotificationManager.m
//  FASTSDK
//
//  Created by Sheng on 2018/6/6.
//  Copyright © 2018年 Gensee. All rights reserved.
//

#import "GSNotificationManager.h"

@implementation GSNotificationManager
{
    NSMutableDictionary *_registeredNotifications;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _registeredNotifications = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)addObserver:(nonnull id)observer
           selector:(nonnull SEL)aSelector
               name:(nullable NSString *)aName
             object:(nullable id)anObject
{
    [[NSNotificationCenter defaultCenter] addObserver:observer
                                             selector:aSelector
                                                 name:aName
                                               object:anObject];
    
    [_registeredNotifications setValue:aName forKey:aName];
}

- (void)removeAllObservers:(nonnull id)observer
{
    for (NSString *name in [_registeredNotifications allKeys]) {
        [[NSNotificationCenter defaultCenter] removeObserver:observer
                                                        name:name
                                                      object:nil];
    }
}

@end
