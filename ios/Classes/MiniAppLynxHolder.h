// 工作台小程序页面栈容器：LynxHolder 协议的宿主实现。
// LynxNavigator（引擎单例）负责页面栈调度（navigate/goBack/背滑回调），
// 本类负责为每条路由创建 LynxView 并维护显示状态。
// P1 范围：注册链路与栈状态；导航出新页面的真实视图挂载在 P2 与
// Flutter 容器（原生承载视图）对接。
#import <Lynx/LynxConfig.h>
#import <Lynx/LynxHolder.h>
#import <Lynx/LynxNavigator.h>
#import <Lynx/LynxRoute.h>
#import <Lynx/LynxView.h>
#import <Lynx/LynxViewBuilder.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

extern NSString* const MiniAppLynxHolderCurrentBundlePathDidChange;

/// 提供当前容器的 bundle 路径：导航出的新页面与来源页共用同一 bundle。
/// 由 PlatformView 侧在容器建立时写入（路由隔离原则：Dart 不参与页面栈）。
@interface MiniAppLynxHolder : NSObject <LynxHolder>

+ (instancetype)shared;

/// 当前容器的已准备 bundle 文件路径；nil 时 createLynxView 无法建页。
@property(nonatomic, copy, nullable) NSString *preparedBundlePath;

/// 页面栈挂载的原生容器视图（PlatformView 的根视图）；bind 后 navigate
/// 出的页面由本类直接 addSubview 挂载，Flutter 层不参与页面栈。
@property(nonatomic, weak, nullable) UIView *containerView;

/// 页面栈深度（含首页；观测与栈底判定用）。
@property(nonatomic, readonly) NSUInteger pageCount;

/// 栈底 goBack 时经此回调通知 Flutter 关闭容器页（单向通知，唯一 Dart 触点）。
@property(nonatomic, copy, nullable) void (^onStackBottomBack)(void);

@end

NS_ASSUME_NONNULL_END
