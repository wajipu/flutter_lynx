// Copyright 2026 The flutter_lynx Authors. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file in the root directory of this project.

#import <Lynx/LynxComponentRegistry.h>
#import "XElementSVGLazyRegister.h"

@implementation LynxUISVGRegister

// 上游同款机制：方法指针写入 __LYNX__DATA section，LynxLazyRegister 在
// 首个 LynxEnv 初始化时遍历所有镜像（含动态 framework）执行注册。
// 若宿主日后改用静态链接并引入完整 XElement（Behavior 子规范），同名
// 注册按"后者覆盖前者"规则自然合并，无需改动此处。
LYNX_LAZY_REGISTER_UI("svg")

@end
