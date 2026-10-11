#import <Flutter/Flutter.h>
#import "MiniAppPageStackView.h"

NS_ASSUME_NONNULL_BEGIN

@interface FlutterLynxPlugin : NSObject <FlutterPlugin>

/// 全局 bridge 转发通道（页面栈等原生自建 LynxView 复用同一条）。
+ (FlutterMethodChannel *)bridgeChannel;

+ (void)callBridge:(NSString *)module
            method:(NSString *)method
            params:(NSDictionary *)params
            callId:(NSString *)callId
   sourceContextId:(NSString *_Nullable)sourceContextId
           channel:(FlutterMethodChannel *)channel
        completion:(void (^)(NSDictionary *response))completion;
@end

NS_ASSUME_NONNULL_END
