//
//  GSMediaAuthor.h
//  GSCommonKit
//
//  Created by gensee on 2018/10/23.
//  Copyright © 2018年 gensee. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface GSMediaAuthor : NSObject

+ (void)authorCamera:(void (^ __nullable)(BOOL granted))completion;
+ (void)authorMicphone:(void (^ __nullable)(BOOL granted))completion;

@end

NS_ASSUME_NONNULL_END
