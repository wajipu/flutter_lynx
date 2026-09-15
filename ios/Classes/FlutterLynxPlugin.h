#import <Flutter/Flutter.h>

NS_ASSUME_NONNULL_BEGIN

@interface FlutterLynxPlugin : NSObject <FlutterPlugin>
+ (void)callBridge:(NSString *)module
            method:(NSString *)method
            params:(NSDictionary *)params
            callId:(NSString *)callId
        completion:(void (^)(NSDictionary *response))completion;
@end

NS_ASSUME_NONNULL_END
