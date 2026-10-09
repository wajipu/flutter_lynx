// 宿主提供的 Lynx <input> 原生 UI：本地构建的 Lynx.xcframework 未包含表单组件，
// 缺失时报 LynxCreateUIException（input ui not found）导致整个页面加载失败。
// 覆盖工作台小程序模板用到的能力：default-value/placeholder/maxlength/confirm-type
// 与 bindinput/bindconfirm 事件。
#import <Lynx/LynxComponentRegistry.h>
#import <Lynx/LynxEvent.h>
#import <Lynx/LynxPropsProcessor.h>
#import <Lynx/LynxUI.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface LynxUIInput : LynxUI<UITextField*>
@end

NS_ASSUME_NONNULL_END
