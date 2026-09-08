# Flutter Lynx (动态小程序插件)

基于 [Lynx](https://lynxjs.org/) 引擎构建的 Flutter 动态小程序与页面容器插件。

支持在 Flutter 应用中动态下载、缓存、热更新和秒级加载 Lynx 编译的 `.lynx.bundle` 小程序，并提供双向的高性能 JavaScript Bridge (JSB)，使小程序能够无缝调用 Flutter 宿主应用的业务能力（如扫码、网络请求代理、登录态与权限、本地存储、原生弹窗等）。

---

## 🌟 特性

- ⚡ **原生级双线程渲染**：基于字节跳动 Lynx 跨端引擎，JS 逻辑与原生渲染分线程运行，帧率稳定流畅。
- 📦 **动态热更与离线缓存**：内置 `LynxMiniProgramManager`，支持版本比对、MD5 完整性校验、分包解压及离线秒开。
- 🌉 **全功能 JSBridge 通信系统**：
  - 宿主直接注入能力：扫码、Dio 网络代理、登录信息、设备信息、存储。
  - 内置基础能力库：Toast、Modal、Loading、导航栏设置、振动。
  - 宿主与小程序双向事件总线（`EventBus`）。
- 📱 **开箱即用小程序页面容器**：`LynxMiniProgramPage` 自带小程序胶囊按钮（`···` 与 `✕`）、加载进度条、失败重试及版本说明弹窗。
- 💻 **现代化前端开发体验**：支持使用 React (`ReactLynx`)、TypeScript、CSS，并通过 Rspeedy 一键编译生成 `main.lynx.bundle`。

---

## 🏗️ 架构设计

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

```dart
import "package:flutter_lynx/flutter_lynx.dart";

void setupLynxMiniProgramBridge() {
  final bridge = LynxBridge.instance;

  // 1. 注入扫码能力
  bridge.register("scanQRCode", (params) async {
    // 唤起宿主扫码页面并获取结果
    final qrCode = await HostScannerService.scan();
    return {"code": qrCode};
  });

  // 2. 注入当前登录用户信息
  bridge.register("getUserInfo", (params) async {
    final user = HostAuthService.currentUser;
    return {
      "userId": user.id,
      "userName": user.name,
      "phone": user.phone,
      "token": user.token,
    };
  });

  // 3. 注入网络请求代理 (复用宿主 DioClient 与鉴权 Token)
  bridge.register("request", (params) async {
    final url = params["url"] as String;
    final method = params["method"] as String? ?? "GET";
    final data = params["data"];

    final response = await HostDioClient.request(url, method: method, data: data);
    return {"data": response.data, "status": response.statusCode};
  });
}
```

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
      builder: (_) => LynxMiniProgramPage(manifest: manifest),
    ),
  );
}
```

### 4. 嵌入单个组件视图 (`LynxView`)

如果只需要在宿主已有页面中嵌入一部分 Lynx 动态组件：

```dart
LynxView(
  url: "file:///path/to/main.lynx.bundle", // 或 assets:// / https://
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
