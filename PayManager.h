//
//  PayManager.h
//  Sports
//
//  Created by Sean on 2017/2/6.
//  Copyright © 2017年 雷速体育. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <StoreKit/StoreKit.h>
@class SPChargeItem;

@protocol PaymentDelegate <NSObject>
@optional
- (void)applePaySuccessed;
- (void)aliPaySuccessed;
- (void)wechatPaySuccessed;
- (void)coinPaySuccessed;
@end

@interface PayManager : NSObject
@property (weak, nonatomic) id <PaymentDelegate> paymentDelegate;
@property (strong, nonatomic) UIView *displayView;

+ (instancetype)sharedManager;

- (void)startMonitoring;

- (void)registerDelegate:(id <PaymentDelegate>)delegate;
- (void)removeDelegate;

#pragma mark - ApplePay
- (void)beginApplePay:(SPChargeItem *)item;
- (void)completeTransaction:(SKPaymentTransaction *)transaction;
@end
