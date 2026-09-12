# Flutter Lynx (动态小程序插件)

基于 [Lynx](https://lynxjs.org/) 引擎构建的 Flutter 动态小程序与页面容器插件。

提供 Flutter 容器、包准备和 JavaScript Bridge 入口。当前实现状态以实测为准，不把示例或占位视图当作生产能力。

## 当前状态（2026-09-12）

- Android已接官方Lynx 3.2.0及获批的官方ImageService/Fresco，在Android 15临时模拟器验证了真实A/B bundle切换、JS点击计数、system.getSystemInfo、宿主反向事件和本地PNG加载；切包没有重新编译Flutter。
- 已修复ImageService初始化缺失及其官方POM缺依赖边导致的D8默认方法问题；标准 `LynxMiniProgramPage` 可以进入真实首屏、撤掉遮罩，正常包未再触发32102或默认方法错误。坏包仍报告真实失败，不屏蔽SDK错误。
- iOS、桌面和kmanager正式工作台尚未完成真实运行时接入；本轮没有修改商家App或推送。
- 独立验收入口：在example执行 `flutter run -t lib/runtime_verification.dart -d <Android测试设备>`。安装前核对示例包名 `com.kmanager.flutter_lynx_example`，不要覆盖业务App。
- A/B源码与构建说明见 [模板README](lynx_miniapp_template/README.md)。原有用户修改的演示源码/dist仍保留，旧JSON打包脚本已经移除。

---

## 🌟 特性

- ⚡ **原生渲染**：Android接入官方Lynx；性能、其他平台及完整业务场景仍需专项验收。
- 📦 **包准备与缓存**：内置 `LynxMiniProgramManager`；现有缓存不等于完整的签名、版本回滚或离线授权机制。
- 🌉 **JSBridge 通信入口**：
  - 宿主直接注入能力：扫码、Dio 网络代理、登录信息、设备信息、存储。
  - 内置基础能力库：Toast、Modal、Loading、导航栏设置、振动。
  - 宿主与小程序双向事件总线（`EventBus`）。
- 📱 **小程序页面容器**：`LynxMiniProgramPage` 提供加载/失败状态与胶囊按钮，成功以真实首屏回调为准。
- 💻 **现代化前端开发体验**：支持使用 React (`ReactLynx`)、TypeScript、CSS，并通过 Rspeedy 一键编译生成 `main.lynx.bundle`。

---

## 🏗️ 目标架构（不是所有部分都已接入）

```text
+-------------------------------------------------------------+
|                      Lynx 动态小程序                         |
|         (React / TypeScript / CSS / Rspeedy 打包产物)        |
+-------------------------------------------------------------+
                              ↕  JSBridge (LynxBridge SDK)
+-------------------------------------------------------------+
|                     flutter_lynx 插件层                     |
|  - LynxView (PlatformView: AndroidView / UiKitView)         |
|  - LynxMiniProgramManager (包下载 / 校验 / 缓存 / 热更新)      |
|  - LynxBridge (JSB 统一消息调度分发中心)                       |
+-------------------------------------------------------------+
                              ↕  MethodChannel
+-------------------------------------------------------------+
|                     Flutter 宿主 (kmanager)                 |
|  - 扫码 (MobileScanner / QR)                                |
|  - 网络代理 (DioClient + 自动携带 Token / Refresh Token)     |
|  - 状态管理 (Riverpod / 登录信息 / 权限)                       |
|  - UI 反馈 (KTips / KDialog)                                |
+-------------------------------------------------------------+
```

---

## 🚀 快速开始

### 1. 引入插件

在宿主应用的 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  flutter_lynx:
    path: ../flutter_lynx
```

### 2. 注册宿主能力至 LynxBridge

在宿主初始化阶段（如 `main.dart` 或 `di.dart` 中），将宿主能力注入给小程序调用：

以下Host类仅说明宿主适配位置，不是kmanager现有实现。不得向JS返回主App Token；网络能力必须按确认过的接口白名单转发，不能开放携带认证的任意URL代理。

```dart
import "package:flutter_lynx/flutter_lynx.dart";

void setupLynxMiniProgramBridge() {
  final bridge = LynxBridge.instance;

  // 1. 注入扫码能力
  bridge.register("scanQRCode", (params) async {
    // 唤起宿主扫码页面并获取结果
    final qrCode = await HostScannerService.scan();
    return {"code": qrCode};
  }, module: "scanner");

  // 2. 注入当前登录用户信息
  bridge.register("getUserInfo", (params) async {
    final user = HostAuthService.currentUser;
    return {
      "userId": user.id,
      "userName": user.name,
      "phone": user.phone,
    };
  }, module: "user");

  // 网络转发需先确认每个接口的参数与权限，本例不提供任意URL代理。
}
```

### Bridge 模块授权与兼容

- `LynxView.allowedModules` 是每个原生 View 创建时的授权集合。为兼容已有内置入口，直接使用 `LynxView` 的默认值为 `{'system','ui','storage','router','default'}`；实际接入应显式收紧，例如 `const {'system'}`。`LynxMiniProgramPage` 默认仅 `system`。
- 自定义模块允许使用 `[A-Za-z0-9_-]{1,64}` 名称，必须显式列入集合。创建参数传递 1–32 项字符串列表，原生去重；缺失、空列表、超限或非法名称均在加载握手时失败，不会回退成全部允许。
- Android 在进入 Flutter MethodChannel 之前按模块名精确检查；未授权返回 `{callId,code:403,message:"Bridge module is not allowed"}`。`default` 是独立模块名，不是其他模块的通配符。
- `register/unregister/dispatch` 现在按模块精确匹配：非 default 注册不再自动创建 default 别名，任何其他模块也不再回退查找 default 函数。旧自定义调用需要同步明确 JS 模块名、宿主注册的 `module` 和 `allowedModules`。内置 handler 保留显式 default 入口的旧行为。
- 改变 `allowedModules` 会重建原生 View 并销毁旧 Bridge 绑定；普通 `reload` 不改变授权。此边界不替代业务接口权限。当前仅 Android 原生链路强制执行，未完成接入的 iOS/桌面不能作为安全容器使用。

### 3. 打开动态小程序

使用 `LynxMiniProgramPage` 快速启动远程或本地小程序：

```dart
import "package:flutter_lynx/flutter_lynx.dart";

void openDemoMiniProgram(BuildContext context) {
  final manifest = MiniProgramManifest(
    appId: "kmanager_desk_manage",
    name: "桌台管理小程序",
    version: "1.0.0",
    bundleUrl: "https://cdn.example.com/miniapp/desk_manage/1.0.0/main.lynx.bundle",
    md5: "e10adc3949ba59abbe56e057f20f883e", // 可选完整性校验
    description: "用于现场巡检与桌台状态管理的动态小程序",
    initialData: {
      "theme": "light",
      "shopId": "SHOP_888",
    },
  );

  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => LynxMiniProgramPage(
        manifest: manifest,
        allowedModules: const {"system", "scanner", "user"},
      ),
    ),
  );
}
```

### 4. 嵌入单个组件视图 (`LynxView`)

如果只需要在宿主已有页面中嵌入一部分 Lynx 动态组件：

```dart
LynxView(
  url: "file:///path/to/main.lynx.bundle", // 先通过包管理器准备asset/远端资源
  allowedModules: const {"system"},
  initialData: LynxTemplateData({"count": 42}),
  onLoadSuccess: () {
    print("Lynx 模版加载成功");
  },
  onLoadFail: (error) {
    print("加载失败: \$error");
  },
)
```

---

## 🛠️ 小程序开发说明

本仓库包含官方标准的小程序开发模板：`lynx_miniapp_template/`。

1. **进入模板工程**：
   ```bash
   cd lynx_miniapp_template
   npm install
   ```

2. **本地调试**：
   ```bash
   npm run dev
   ```

3. **打包生成 Bundle**：
   ```bash
   npm run build
   ```
   编译产物 `main.lynx.bundle` 将生成在 `dist/` 目录下。直接上传至 CDN 或复制到宿主 assets 即可动态加载！

---

## 📄 License

Apache 2.0
