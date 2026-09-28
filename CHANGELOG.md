## 0.2.0（未发布）

- feat：模型生成 UI 主线落地官方 A2UI v0.9（移动端）。`lynx_miniapp_template` 新增
  ReactLynx 宿主入口（`@lynx-js/genui@0.5.0` 精确锁版 + Catalog 组件白名单 +
  `onAction` → `ui.confirmResult` 回传），产物 `a2ui-card.lynx.bundle` 随 App 内置，
  经既有 `loadFromTemplateBytes` 装载；小柯消息走 `initialData.messages`，零新通道。
  example 新增「A2UI 确认卡」端到端演示页签、协议消息样例与结构守护测试。
  方案全文见 docs/a2ui-mobile-integration.md；桌面 A2UI 子集渲染器延后（策略待定）。
- feat：备选格式 lynx-card/1 保留（未接线）：`lib/src/card/` 解析器与渲染器 +
  docs/lynx-card-format.md 决策记录，主线若切换可回退启用。

## 0.1.0

- feat：新增模板源码直喂加载 API，对齐官方 LynxView.loadTemplate：`LynxView` 新增
  `source`（文本）/ `templateBytes`（二进制产物）入口与 `url` 三选一，`LynxController`
  新增 `loadFromSource(String)` / `loadFromTemplateBytes(Uint8List)`，MethodChannel
  新增 `loadFromSource` action（Android/iOS 原生与文件链路共用同一 bytes 直喂渲染入口）。
  桌面 `LynxDesktopRuntimeView` 同步支持 `source` 入口；既有文件链路保持完全兼容。
- fix：`LynxView.url` 从 required 放宽为可选（由三选一断言保证参数完整性），既有
  `LynxView(url: ...)` 调用方无需任何改动。
