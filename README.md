# Flutter Lynx (动态小程序插件)

[![CI](https://github.com/wajipu/flutter_lynx/actions/workflows/ci.yml/badge.svg)](https://github.com/wajipu/flutter_lynx/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

基于 [Lynx](https://lynxjs.org/) 引擎构建的 Flutter 动态小程序与页面容器插件。

提供 Flutter 容器、包准备和 JavaScript Bridge 入口。当前实现状态以实测为准，不把示例或占位视图当作生产能力。

## 当前状态（2026-09-15）

- 整栈锁定官方稳定版 **Lynx 4.1.0 + PrimJS 4.1.1 + ImageService 4.1.0**，依据 [官方集成文档](https://lynxjs.org/guide/start/integrate-with-existing-apps) 与 GitHub `4.1.0` release（2026-09-07）。不要用 Maven metadata 的 `latest`（当前指向 `4.1.0-nightly`）。
- Android / iOS 仍只接官方 Image 服务与已获批的 Fresco 2.3.0 / SDWebImage 5.15.5；不接 HTTP、Log、DevTool、XElement。
- iOS 宿主 `Podfile` 必须同时声明 `https://cdn.cocoapods.org/` 和 `https://github.com/lynx-family/Specs.git`。Lynx 4.1.0 不在 CocoaPods CDN。
- 已删除 Lynx 3.2 / PrimJS 2.12.0 及配套 `ios/lynx_3_2_xcode16.rb`。4.1 编译或 `lynx_core.js` 查找若再出问题，按 4.1 源码另写补丁，不要回退 3.2。
- macOS / Windows 的官方桌面引擎是 CMake `libLynx`，不是 iOS `LynxView`。当前 Flutter `LynxView` 在这些平台明确失败，不再用 Dart 自绘预览冒充已加载。
- 宿主 App 通过固定 Git 提交接入，当前只授权 `system` Bridge。Android / iOS 打开官方引擎闸门；macOS 明确拒绝。
- 独立验收入口：`flutter run -t lib/runtime_verification.dart -d <Android或iOS测试设备>`。安装前核对示例包名 `io.github.wajipu.flutter_lynx_example`，不要覆盖业务App。
- A/B源码与构建说明见 [模板README](lynx_miniapp_template/README.md)。原有用户修改的演示源码/dist仍保留，旧JSON打包脚本已经移除。

---

## 🌟 特性

- ⚡ **原生渲染**：Android / iOS 接入官方 Lynx 4.1.0；Flutter 桌面未嵌入官方 CMake SDK。性能与完整业务场景仍需专项验收。
- 📦 **包准备与缓存**：内置 `LynxMiniProgramManager`；现有缓存不等于完整的签名、版本回滚或离线授权机制。
- 🌉 **JSBridge 通信入口**：
  - 宿主直接注入能力：扫码、Dio 网络代理、登录信息、设备信息、存储。
  - 内置基础能力库：Toast、Modal、Loading、导航栏设置、振动。
  - 宿主与小程序双向事件总线（`EventBus`）。
- 📱 **小程序页面容器**：`LynxMiniProgramPage` 全屏铺 Lynx。微信式胶囊（状态栏下 4pt、距右 7pt、87×32）由原生画在窗口层（iOS `UIWindow`、Android Activity decor），跟系统亮暗主题走，不进 Flutter 树，也不挂在 Lynx PlatformView 上。`applySafeArea`（默认打开，initData 传 `1`/`0`）只把安全区和 `menuButton` 交给小程序排版。裸 `LynxView` 不画胶囊。
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
|  - LynxHostCapsule（原生窗口层胶囊；Dart 只做开关）              |
|  - LynxMiniProgramManager (包下载 / 校验 / 缓存 / 热更新)      |
|  - LynxBridge (JSB 统一消息调度分发中心)                       |
+-------------------------------------------------------------+
                              ↕  MethodChannel
+-------------------------------------------------------------+
|                     Flutter 宿主 App                 |
|  - 扫码 (MobileScanner / QR)                                |
|  - 网络代理 (DioClient + 自动携带 Token / Refresh Token)     |
|  - 状态管理 (Riverpod / 登录信息 / 权限)                       |
|  - UI 反馈 (KTips / KDialog)                                |
+-------------------------------------------------------------+
```

---

## 🚀 快速开始

### 1. 引入插件

iOS 宿主 `Podfile` 顶部必须同时声明两个 source，否则解析不到 Lynx 4.1.0：

```ruby
source 'https://cdn.cocoapods.org/'
source 'https://github.com/lynx-family/Specs.git'
```

在宿主应用的 `pubspec.yaml` 中添加依赖：

```yaml
dependencies:
  flutter_lynx:
    git:
      url: https://github.com/wajipu/flutter_lynx.git
      ref: <宿主 App 的 pubspec.yaml 锁定的已验证提交>
```

宿主应固定已验证提交，禁止 `path:` 指向相邻本地目录，也不要跟浮动 `main`。

### 2. 注册宿主能力至 LynxBridge

在宿主初始化阶段（如 `main.dart` 或 `di.dart` 中），将宿主能力注入给小程序调用：

以下Host类仅说明宿主适配位置，不是宿主 App 现有实现。不得向JS返回主App Token；网络能力必须按确认过的接口白名单转发，不能开放携带认证的任意URL代理。

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
- Android 与 iOS 在进入 Flutter MethodChannel 之前按模块名精确检查；未授权返回 `{callId,code:403,message:"Bridge module is not allowed"}`。`default` 是独立模块名，不是其他模块的通配符。
- `register/unregister/dispatch` 现在按模块精确匹配：非 default 注册不再自动创建 default 别名，任何其他模块也不再回退查找 default 函数。旧自定义调用需要同步明确 JS 模块名、宿主注册的 `module` 和 `allowedModules`。内置 handler 保留显式 default 入口的旧行为。
- 改变 `allowedModules` 会重建原生 View 并销毁旧 Bridge 绑定；普通 `reload` 不改变授权。此边界不替代业务接口权限。Android 与 iOS 原生链路在进入 Flutter MethodChannel 之前按模块名精确检查；macOS 没有官方引擎，不能作为安全容器使用。

### 3. 打开动态小程序

使用 `LynxMiniProgramPage` 快速启动远程或本地小程序：

```dart
import "package:flutter_lynx/flutter_lynx.dart";

void openDemoMiniProgram(BuildContext context) {
  final manifest = MiniProgramManifest(
    appId: "host_desk_manage",
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
      fullscreenDialog: true,
      builder: (_) => LynxMiniProgramPage(
        manifest: manifest,
        allowedModules: const {"system", "scanner", "user"},
        // 默认 true。不需要宿主垫安全区时关掉。
        // applySafeArea: false,
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

### 5. 直喂模板源码加载（对齐官方 `LynxView.loadTemplate`）

固定、可信的模板（如确认卡片）可随 App 版本内置，运行时直接把模板内容喂给引擎，
不经落盘与缓存链路。`url`、`source`（文本内容）、`templateBytes`（二进制产物）三选一：

```dart
// 文本型模板内容直喂（对应官方 TemplateBundle.fromTemplate 的 String 语义）
LynxView(
  source: templateText, // 引擎可执行的模板产物文本，上限 10 MiB
  allowedModules: const {"system"},
  initialData: LynxTemplateData({"orderId": "A1024"}),
);

// rspeedy/tasm 编译产物是二进制模板（非 UTF-8），必须走 bytes 通道：
final asset = await rootBundle.load("assets/miniapp/main.lynx.bundle");
LynxView(
  templateBytes: asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes),
  allowedModules: const {"system"},
);
```

运行期换内容可调控制器（对应官方 `loadTemplate(bytes)` 的动态调用）：

```dart
controller.loadFromSource(templateText);
await controller.loadFromTemplateBytes(bytes, initialData: {"orderId": "A1024"});
```

三条链路在原生侧共用同一个官方 bytes 直喂渲染入口
（Android `LynxView.renderTemplateWithBaseUrl` / iOS `loadTemplate:withURL:initData:`），
`loadFromSource`/`templateBytes` 只是省掉了"读文件"这一步，渲染结果与文件链路一致。
`LynxDesktopRuntimeView`（桌面演示运行时）同样支持传 `source` 直喂，与 `url` 二选一。
数据注入仍走 `LynxTemplateData` 与 `controller.updateData`，与文件链路完全一致。

### 6. 模型生成 UI（A2UI 主线，移动端）

大模型现场生成的 UI 走官方 **A2UI v0.9** 协议：模型输出协议消息，随 `initialData.messages`
注入内置的 ReactLynx 宿主 bundle（官方 `@lynx-js/genui@0.5.0` `<A2UI>` 渲染器 + Catalog
组件白名单），按钮点击经既有 `ui.confirmResult` Bridge 回传宿主。

```dart
final bytes = await rootBundle.load("assets/miniapp/a2ui-card.lynx.bundle");
LynxView(
  templateBytes: bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
  allowedModules: const {"system", "ui"},
  initialData: LynxTemplateData({
    "token": token,
    "confirmationId": confirmationId,
    "messages": modelGeneratedA2uiMessages, // A2UI v0.9 消息数组
  }),
);
```

集成方案全文（架构、Catalog 白名单、回传契约、真机验证步骤、Skill 消息样例硬约束）：
[docs/a2ui-mobile-integration.md](docs/a2ui-mobile-integration.md)。
桌面 A2UI 子集渲染器延后（策略待定）；备选自研格式 lynx-card/1 的解析渲染实现保留于
`lib/src/card/`，决策记录见 [docs/lynx-card-format.md](docs/lynx-card-format.md)。

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

   编译产物 `main.lynx.bundle` 将生成在 `dist/` 目录下，可上传 CDN 或复制到宿主 assets 动态加载。

---

## License

[MIT](LICENSE)
