// Lynx navigator 模块的宿主实现（引擎 Headers 仅声明接口）：
// 转发到 LynxNavigator 单例，由 MiniAppLynxHolder 承接页面栈回调。
// 与官方 platform/darwin/common/lynx/navigator/NavigationModule.m 对齐。
#import <Lynx/LynxNavigator.h>
#import <Lynx/LynxView.h>
#import <Lynx/NavigationModule.h>
#import <UIKit/UIKit.h>

#import "MiniAppLynxHolder.h"

@implementation NavigationModule

+ (NSString *)name {
  return @"NavigationModule";
}

- (void)registerRoute:(NSDictionary *)routeTable {
}

- (void)navigateTo:(NSString *)url param:(NSDictionary *)param {
  dispatch_async(dispatch_get_main_queue(), ^{
    [[LynxNavigator sharedInstance] navigate:url withParam:param];
  });
}

- (void)replace:(NSString *)url param:(NSDictionary *)param {
  dispatch_async(dispatch_get_main_queue(), ^{
    [[LynxNavigator sharedInstance] replace:url withParam:param];
  });
}

- (void)goBack {
  dispatch_async(dispatch_get_main_queue(), ^{
    [[LynxNavigator sharedInstance] goBack];
  });
}

+ (NSDictionary<NSString *, NSString *> *)methodLookup {
  return @{
    @"registerRoute" : NSStringFromSelector(@selector(registerRoute:)),
    @"navigateTo" : NSStringFromSelector(@selector(navigateTo:param:)),
    @"replace" : NSStringFromSelector(@selector(replace:param:)),
    @"goBack" : NSStringFromSelector(@selector(goBack)),
  };
}

@end
