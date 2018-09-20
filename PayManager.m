//
//  PayManager.m
//  Sports
//
//  Created by Sean on 2017/2/6.
//  Copyright © 2017年 雷速体育. All rights reserved.
//

static NSString *const kTransactionKey = @"in_app_purchase";

#import "PayManager.h"
#import "WXApi.h"
#import "SPChargeItem.h"
#import "SPChargeCoinView.h"
#import "SPChargeVIPView.h"
#import "DBManager.h"
#import "PurchaseRecord.h"

@interface PayManager () <SKProductsRequestDelegate, SKPaymentTransactionObserver>
@property (strong, nonatomic) SKProductsRequest *request;

@property (strong, nonatomic) SPChargeCoinView *coinView;
@property (strong, nonatomic) SPChargeVIPView *vipView;

@property (strong, nonatomic) NSString *order_id;
@property (strong, nonatomic) NSString *product_id;
@end

@implementation PayManager
+ (instancetype)sharedManager {
    static dispatch_once_t onceToken;
    static PayManager *instance;
    dispatch_once(&onceToken, ^{
        instance = [[PayManager alloc] init];
    });
    return instance;
}

- (void)startMonitoring {
    [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handlePaymentFinished) name:PaymentFinishedNotification object:nil];
    
    [self _refreshOrders];
}

- (void)registerDelegate:(id <PaymentDelegate>)delegate {
    self.paymentDelegate = delegate;
}

- (void)removeDelegate {
    self.paymentDelegate = nil;
}

#pragma mark - Apple Pay
- (void)beginApplePay:(SPChargeItem *)item {
    [_vipView remove];
    [self startLoading];
    int timeStamp = [[NSDate date] timeIntervalSince1970];
    NSDictionary *params = @{@"product_id":item.product_id, @"amount":item.amount, @"pay_type":@3, @"order_no":@(timeStamp)};
    
    [[Sports_NetApiClient sharedBaseURLInstance] requestJsonDataWithPath:Https_Post_Pay_TransactionStart withParams:params.mutableCopy withMethodType:Post andBlock:^(id result, NSError *error) {
        if (result) {
            self.order_id = result[@"transaction_id"];
            self.product_id = item.apple_product_id;
            [self purchase];
        }
    }];
}

- (void)purchase {
    NSArray *product = @[self.product_id];
    NSSet *nsset = [NSSet setWithArray:product];
    //请求动作
    _request = [[SKProductsRequest alloc] initWithProductIdentifiers:nsset];
    
    _request.delegate = self;
    [_request start];
}

#pragma mark - SKProductsRequestDelegate
- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response {
    NSArray *product = response.products;
    if([product count] == 0){
        NSLog(@"没有这个商品");
        return;
    }
    
    SKProduct *p = nil;
    //所有的商品,遍历招到我们的商品
    for (SKProduct *pro in product) {
        if([pro.productIdentifier isEqualToString:self.product_id]) {
            p = pro;
        }
    }
    SKPayment *payment = [SKPayment paymentWithProduct:p];
    
    [[SKPaymentQueue defaultQueue] addPayment:payment];
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error {
    [self stopLoading];
    [NSObject showHudTipStr:@"请求商品信息错误"];
}

#pragma mark - Coin
- (void)coinPay:(SPChargeItem *)chargeItem {
    [_vipView remove];
    [self startLoading];
    int timeStamp = [[NSDate date] timeIntervalSince1970];
    NSDictionary *params = @{@"product_id":chargeItem.product_id, @"amount":@(1), @"pay_type":@4, @"order_no":@(timeStamp)};
    
    @weakify(self);
    [[Sports_NetApiClient sharedBaseURLInstance] requestJsonDataWithPath:Https_Post_Pay_TransactionStart withParams:params.mutableCopy withMethodType:Post andBlock:^(id data, NSError *error) {
        @strongify(self);
        [self stopLoading];
        if (data) {
            self.order_id = data[@"transaction_id"];
            [self coinPayComplete];
        }
    }];
}

- (void)coinPayComplete {
    NSString *trade_id = self.order_id;
    if (!trade_id || trade_id.length == 0) return;
    NSDictionary *params = @{@"transaction_id":trade_id};
    
    @weakify(self);
    [[Sports_NetApiClient sharedBaseURLInstance] requestJsonDataWithPath:Https_Post_Pay_TransactionComplete withParams:params.mutableCopy withMethodType:Post andBlock:^(id data, NSError *error) {
        @strongify(self);
        if (data) {
            if (self.paymentDelegate && [self.paymentDelegate respondsToSelector:@selector(coinPaySuccessed)]) {
                [self.paymentDelegate coinPaySuccessed];
            }
        }
    }];
}

#pragma mark - SKPaymentTransactionObserver
- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transaction {
    for(SKPaymentTransaction *tran in transaction) {
        switch (tran.transactionState) {
            case SKPaymentTransactionStatePurchased:
                [self completeTransaction:tran];
                break;
            case SKPaymentTransactionStatePurchasing:
                [NSObject showHudTipStr:@"正在请求支付信息"];
                break;
            case SKPaymentTransactionStateRestored:
                [NSObject showHudTipStr:@"已经购买过商品"];
                [self completeTransaction:tran];
                break;
            case SKPaymentTransactionStateFailed:
                [NSObject showHudTipStr:@"购买失败"];
                [self completeTransaction:tran];
                break;
            default:
                [self stopLoading];
                break;
        }
        
    }
}

- (void)completeTransaction:(SKPaymentTransaction *)transaction {
    if (transaction.transactionState == SKPaymentTransactionStatePurchased) { //如果从AppStore购买成功需要请求服务器验证订单
        [self validateReceipt:transaction];
    } else {
        //比如用户第一次支付,会跳转apple store,订单状态取消(暂时没有验证)
        [[DBManager sharedManager] insertTransaction:self.order_id receipt:@"" sandbox:@0 identifier:transaction.transactionIdentifier];
        [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
        [self stopLoading];
    }
}

- (void)validateReceipt:(SKPaymentTransaction *)transaction {
    NSURL *receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData *receipt = [NSData dataWithContentsOfURL:receiptURL];
    NSString *requestAuth = [receipt base64EncodedStringWithOptions:0];
    
    if (!self.order_id) self.order_id = [[DBManager sharedManager] record:transaction.transactionIdentifier].transaction_id;
    if (!self.order_id || self.order_id.length == 0) return;
    if (!requestAuth || requestAuth.length == 0) return;
    
    NSNumber *sandbox;
#if DEBUG
    sandbox = @1;
#else
    sandbox = @0;
#endif
    
    [[DBManager sharedManager] insertTransaction:self.order_id receipt:requestAuth sandbox:sandbox identifier:transaction.transactionIdentifier];
    
    NSDictionary *params = @{@"receipt":requestAuth, @"transaction_id":self.order_id, @"sandbox":sandbox, @"identifier":transaction.transactionIdentifier};
    @weakify(self);
    [self _submit:params block:^(id result, NSError *error) {
        @strongify(self);
        if (result) {
            [self confimWithIdentifier:transaction.transactionIdentifier transaction:self.order_id];
        }
    }];
    
    [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
}

- (void)confimWithIdentifier:(NSString *)transactionIdentifier transaction:(NSString *)transaction_id  {
    NSDictionary *params = @{@"transaction_id":transaction_id, @"identifier":transactionIdentifier};
    
    @weakify(self);
    [[Sports_NetApiClient sharedBaseURLInstance] requestJsonDataWithPath:Https_Post_Pay_TransactionComplete withParams:params.mutableCopy withMethodType:Post andBlock:^(id result, NSError *error) {
        @strongify(self);
        [self stopLoading];
        if (result) {
            [[DBManager sharedManager] finishedTransaction:transaction_id];
            if (self.paymentDelegate && [self.paymentDelegate respondsToSelector:@selector(applePaySuccessed)]) {
                [self.paymentDelegate applePaySuccessed];
            }
        }
    }];
}

#pragma mark - Private
- (void)_submit:(NSDictionary *)params block:(void (^)(id data, NSError *error))block {
    [[Sports_NetApiClient sharedBaseURLInstance] requestJsonDataWithPath:Https_Post_Pay_ApplepaySubmit withParams:params withMethodType:Post andBlock:^(id result, NSError *error) {
        if (block) block(result, error);
    }];
}

- (void)_refreshOrders {
    for (PurchaseRecord *record in [[DBManager sharedManager] records]) {
        if (record.receipt.length == 0) {
            [[DBManager sharedManager] finishedTransaction:record.transaction_id];
        } else {
            NSDictionary *params = @{@"receipt":record.receipt,
                                     @"transaction_id":record.transaction_id,
                                     @"sandbox":record.sandbox,
                                     @"identifier":record.identifier};
            @weakify(self);
            [self _submit:params block:^(id result, NSError *error) {
                @strongify(self);
                if (result) {
                    [self confimWithIdentifier:record.identifier transaction:record.transaction_id];
                }
            }];
        }
    }
}

#pragma mark - Notification
- (void)handlePaymentFinished {
    if (self.paymentDelegate && [self.paymentDelegate respondsToSelector:@selector(aliPaySuccessed)]) {
        [self.paymentDelegate aliPaySuccessed];
    }
}

#pragma mark - Getter
- (void)startLoading {
    MBProgressHUD *loadingHud = [MBProgressHUD showHUDAddedTo:_displayView animated:YES];
    loadingHud.color = [[UIColor blackColor] colorWithAlphaComponent:.8f];
    loadingHud.mode = MBProgressHUDModeIndeterminate;
    loadingHud.detailsLabelFont = kText_ScaleFont(16.f);
    loadingHud.detailsLabelText = @"请稍候";
    loadingHud.removeFromSuperViewOnHide = true;
    loadingHud.margin = 25.f;
}

- (void)stopLoading {
    [MBProgressHUD hideHUDForView:_displayView animated:YES];
}
@end
