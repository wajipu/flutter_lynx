// 工作台小程序页面栈容器：承载 MiniAppLynxHolder 的多页 LynxView，
// 自带左缘背滑手势（驱动 LynxNavigator goBack；栈底时通知 Flutter 关容器页）。
#import <Flutter/Flutter.h>

NS_ASSUME_NONNULL_BEGIN

@interface MiniAppPageStackFactory : NSObject <FlutterPlatformViewFactory>
- (instancetype)initWithMessenger:(NSObject<FlutterBinaryMessenger> *)messenger;
@end

@interface MiniAppPageStackView : NSObject <FlutterPlatformView>
@end

NS_ASSUME_NONNULL_END
