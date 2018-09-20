//
//  DBManager.h
//  Sport_Plus
//
//  Created by Sean on 2018/6/1.
//  Copyright © 2018年 animation. All rights reserved.
//

#import <Foundation/Foundation.h>
@class PurchaseRecord;

@interface DBManager : NSObject
+ (DBManager *)sharedManager;

- (NSArray *)records;

- (PurchaseRecord *)record:(NSString *)identifier;

- (void)insertTransaction:(NSString *)transaction_id
                  receipt:(NSString *)receipt
                  sandbox:(NSNumber *)sandbox
                  identifier:(NSString *)identifier;

- (void)finishedTransaction:(NSString *)transaction_id;

- (void)destroy;
@end
