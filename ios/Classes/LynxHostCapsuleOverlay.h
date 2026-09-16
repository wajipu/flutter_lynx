#import <Flutter/Flutter.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 全屏小程序胶囊：画在 UIWindow 上，不跟 Lynx PlatformView 一起被 Flutter 重建。
@interface LynxHostCapsuleOverlay : NSObject

+ (instancetype)shared;

/// 绑定独立通道，点击 more/close 回 Flutter。
- (void)bindChannel:(FlutterMethodChannel *)channel;

/// 按窗口安全区画出微信式胶囊。
- (void)showDark:(BOOL)dark;

/// 只改毛玻璃主题，不重建窗口层。
- (void)setDark:(BOOL)dark;

/// 离开全屏小程序页时摘掉。
- (void)hide;

@end

NS_ASSUME_NONNULL_END
