// Copyright 2026 The flutter_lynx Authors. All rights reserved.
// Use of this source code is governed by an MIT-style license that can be
// found in the LICENSE file in the root directory of this project.

#import <Lynx/LynxComponentRegistry.h>
#import "XElementRefreshLazyRegister.h"

// 上游同款机制：方法指针写入 __LYNX__DATA section，LynxLazyRegister 在
// 首个 LynxEnv 初始化时遍历所有镜像（含动态 framework）执行注册。注册名
// 与上游一致取旧标签名 refresh / refresh-header，模板直接写 `<refresh>`。
@implementation LynxUIRefreshShadowNodeRegister

LYNX_LAZY_REGISTER_SHADOW_NODE("refresh")

@end

@implementation LynxUIRefreshRegister

LYNX_LAZY_REGISTER_UI("refresh")

@end

@implementation LynxUIRefreshHeaderRegister

LYNX_LAZY_REGISTER_UI("refresh-header")

@end
