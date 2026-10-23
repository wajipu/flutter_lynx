// Copyright 2026 The flutter_lynx Authors. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file in the root directory of this project.

#import <XElement/LynxUIRefresh.h>
#import <XElement/LynxUIRefreshHeader.h>
#import <XElement/LynxUIRefreshShadowNode.h>

NS_ASSUME_NONNULL_BEGIN

/// `<refresh>`/`<refresh-header>` 的懒加载注册入口（上游 LynxUIRefreshAutoRegistry
/// 的等价实现）。XElement/Refresh 子规范只含元素实现，注册文件在上游 Behavior
/// 子规范里，而该子规范静态链接宿主专用（见 podspec 注释），动态框架宿主无法
/// 引入，故按 svg 同款 LYNX_LAZY_REGISTER 机制补注册。
@interface LynxUIRefreshShadowNodeRegister : LynxUIRefreshShadowNode

@end

@interface LynxUIRefreshRegister : LynxUIRefresh

@end

@interface LynxUIRefreshHeaderRegister : LynxUIRefreshHeader

@end

NS_ASSUME_NONNULL_END
