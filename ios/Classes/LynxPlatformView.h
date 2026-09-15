#import <Flutter/Flutter.h>

NS_ASSUME_NONNULL_BEGIN

@interface LynxPlatformViewManager : NSObject
+ (instancetype)shared;
- (void)registerView:(id)view forViewId:(int64_t)viewId;
- (void)unregisterView:(id)view forViewId:(int64_t)viewId;
- (BOOL)sendEvent:(NSString *)eventName data:(NSDictionary *)data viewId:(NSNumber *_Nullable)viewId;
@end

@interface LynxPlatformView : NSObject <FlutterPlatformView>
- (instancetype)initWithFrame:(CGRect)frame
                       viewId:(int64_t)viewId
                       params:(NSDictionary *)params
                    messenger:(NSObject<FlutterBinaryMessenger> *)messenger;
- (BOOL)sendCustomEvent:(NSString *)eventName data:(NSDictionary *)data;
@end

@interface LynxPlatformViewFactory : NSObject <FlutterPlatformViewFactory>
- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger;
@end

NS_ASSUME_NONNULL_END
