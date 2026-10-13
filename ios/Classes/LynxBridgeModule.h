#import <Foundation/Foundation.h>
#import <Lynx/LynxModule.h>

NS_ASSUME_NONNULL_BEGIN

@class FlutterMethodChannel;

/// One binding belongs to one native view; reload/disposal invalidates pending host callbacks.
@interface LynxBridgeBinding : NSObject
@property(nonatomic, readonly) BOOL isActive;
@property(nonatomic, copy, nullable) void (^onGoBack)(void);
/// Stage an accepted store-selection snapshot before its origin JS callback.
@property(nonatomic, copy, nullable) void (^storeScopeObserver)(NSString *sourceContextId,
                                                               NSNumber *requestedRevision,
                                                               NSDictionary *selection);
- (instancetype)initWithAllowedModules:(NSSet<NSString *> *)allowedModules
                         bridgeChannel:(FlutterMethodChannel *)bridgeChannel
                       sourceContextId:(NSString *_Nullable)sourceContextId;
- (void)invalidate;
- (void)callModule:(NSString *)module
            method:(NSString *)method
            params:(NSDictionary *)params
            callId:(NSString *)callId
          callback:(void (^)(id result))callback;
@end

/// Exposes NativeModules.LynxBridge.call without adding another JS runtime or network client.
@interface LynxBridgeModule : NSObject <LynxModule>
- (instancetype)initWithParam:(id)param;
@end

NS_ASSUME_NONNULL_END
