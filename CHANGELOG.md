## 0.1.0

- feat：新增模板源码直喂加载 API，对齐官方 LynxView.loadTemplate：`LynxView` 新增
  `source`（文本）/ `templateBytes`（二进制产物）入口与 `url` 三选一，`LynxController`
  新增 `loadFromSource(String)` / `loadFromTemplateBytes(Uint8List)`，MethodChannel
  新增 `loadFromSource` action（Android/iOS 原生与文件链路共用同一 bytes 直喂渲染入口）。
  桌面 `LynxDesktopRuntimeView` 同步支持 `source` 入口；既有文件链路保持完全兼容。
- fix：`LynxView.url` 从 required 放宽为可选（由三选一断言保证参数完整性），既有
  `LynxView(url: ...)` 调用方无需任何改动。
