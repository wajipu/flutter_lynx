// Copyright 2026 The KManager Authors. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file in the root directory of this project.

#import <XElement/LynxUISVG.h>

NS_ASSUME_NONNULL_BEGIN

/// `svg` UI 的懒加载注册入口（上游 LynxUISVGAutoRegistry 的等价实现）。
/// XElement/SVG 子规范只含元素实现，注册文件在上游 Behavior 子规范里，
/// 而该子规范静态链接宿主专用，动态框架宿主无法引入，见 podspec 注释。
@interface LynxUISVGRegister : LynxUISVG

@end

NS_ASSUME_NONNULL_END
