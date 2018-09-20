//
//  DBManager.m
//  Sport_Plus
//
//  Created by Sean on 2018/6/1.
//  Copyright © 2018年 animation. All rights reserved.
//

#import "DBManager.h"
#import "FMDB.h"
#import "PurchaseRecord.h"

@interface DBManager ()
@property (strong, nonatomic) FMDatabaseQueue *dbQueue;
@end

@implementation DBManager
+ (instancetype)sharedManager {
    static DBManager *_sharedObj = nil;
    static dispatch_once_t onceToken;
    
    dispatch_once(&onceToken, ^{
        _sharedObj = [[DBManager alloc] init];
    }) ;
    return _sharedObj;
}

- (NSArray *)records {
    __block NSMutableArray *list = [NSMutableArray new];
    
    [self.dbQueue inDatabase:^(FMDatabase * _Nonnull db) {
        FMResultSet *result = [db executeQuery:@"select * from 'APPLE_TRANSACTION'"];
        while ([result next]) {
            PurchaseRecord *item = [PurchaseRecord new];
            item.transaction_id = [result stringForColumn:@"transaction_id"];
            item.receipt = [result stringForColumn:@"receipt"];
            item.identifier = [result stringForColumn:@"identifier"];
            item.sandbox = @([result intForColumn:@"sandbox"]);
            [list addObject:item];
        }
    }];
    
    return list;
}

- (PurchaseRecord *)record:(NSString *)identifier {
    __block PurchaseRecord *record;
    
    [self.dbQueue inDatabase:^(FMDatabase * _Nonnull db) {
        FMResultSet *result = [db executeQuery:@"select * from 'APPLE_TRANSACTION' where identifier = ?",identifier];
        while ([result next]) {
            PurchaseRecord *item = [PurchaseRecord new];
            item.transaction_id = [result stringForColumn:@"transaction_id"];
            item.receipt = [result stringForColumn:@"receipt"];
            item.identifier = [result stringForColumn:@"identifier"];
            item.sandbox = @([result intForColumn:@"sandbox"]);
            record = item;
        }
    }];
    
    return record;
}

- (void)insertTransaction:(NSString *)transaction_id receipt:(NSString *)receipt sandbox:(NSNumber *)sandbox identifier:(NSString *)identifier {
    [self.dbQueue inDatabase:^(FMDatabase * _Nonnull db) {
        [db executeUpdate:@"insert or replace into APPLE_TRANSACTION (transaction_id, receipt, sandbox, identifier) values (?, ?, ?, ?)",
         transaction_id,
         receipt,
         sandbox,
         identifier];
    }];
}

- (void)finishedTransaction:(NSString *)transaction_id {
    [self.dbQueue inDatabase:^(FMDatabase * _Nonnull db) {
        [db executeUpdate:@"delete from APPLE_TRANSACTION where transaction_id = ?",transaction_id];
    }];
}

#pragma mark - Getter
- (FMDatabaseQueue *)dbQueue {
    if (!_dbQueue) {
        _dbQueue = [FMDatabaseQueue databaseQueueWithPath:[self _db_path]];
        if (_dbQueue) {
            [self createUserTableIfNeed];
        }
    }
    return _dbQueue;
}

//创建用户存储表
- (void)createUserTableIfNeed {
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        NSString *createTable = @"create table if not exists APPLE_TRANSACTION(transaction_id text primary key, receipt text, sandbox int, identifier text)";
        BOOL create = [db executeUpdate:createTable];
        NSAssert(create, @"create table feed failed");
    }];
}

#pragma mark - Private
- (void)destroy {
    [self.dbQueue close];
    self.dbQueue = 0x00;
    
    [[NSFileManager defaultManager] removeItemAtPath:[self _db_path] error:nil];
}

- (NSString *)_db_path {
    NSString *path = [[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"] stringByAppendingPathComponent:@"Sport.db"];
    return path;
}
@end
