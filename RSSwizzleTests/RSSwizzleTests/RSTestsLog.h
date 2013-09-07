@interface RSTestsLog : NSObject
+(void)log:(NSString *)string;
+(void)clear;
+(BOOL)is:(NSString *)compareString;
+(NSString *)logString;
@end

#define ASSERT_LOG_IS(STRING) STAssertTrue([RSTestsLog is:STRING], @"LOG IS @\"%@\" INSTEAD",[RSTestsLog logString])
#define CLEAR_LOG() ([RSTestsLog clear])
#define RSTestsLog(STRING) [RSTestsLog log:STRING]