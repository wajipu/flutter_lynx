# 移动端 A2UI 集成方案（小柯确认卡 / Generative UI 主线）

> 状态：主线方案（2026-09-28 定稿）。桌面 A2UI 子集渲染器延后，策略待定，不在本方案范围。
> 备选格式 lynx-card/1 的决策记录见 [lynx-card-format.md](lynx-card-format.md)（§10 选型与演进约定）。

## 1. 一句话架构

小柯模型现场产出 **A2UI v0.9 协议消息**（官方 JSON Schema 约束的声明式 UI 消息流）→
随 `initialData.messages` 经既有 `loadFromTemplateBytes` 注入 →
ReactLynx 宿主 bundle 内的官方 `<A2UI>` 渲染器（`@lynx-js/genui@0.5.0`）按 **Catalog 组件白名单**渲染 →
用户点确认/取消 → `onAction` 映射既有 `ui.confirmResult` Bridge 回传宿主 → 宿主路由确认单 execute/cancel。

```text
小柯 Skill(教官方协议) ──A2UI v0.9 消息──▶ 宿主 Dart
                                          │ initialData.messages (initData 通道，零新通道)
                                          ▼
              LynxView(templateBytes: a2ui-card.lynx.bundle)   ← 产物随 App 版本内置
                                          │ Lynx 4.1 真引擎
                                          ▼
              ReactLynx <A2UI> (@lynx-js/genui)  ──Catalog 白名单──▶ 原生渲染
                                          │ onAction(name=confirm/cancel)
                                          ▼
              ui.confirmResult Bridge ──▶ 宿主路由确认单 execute/cancel
```

## 2. 版本与兼容（已核实）

| 项               | 值                                                           | 说明                                                                                                     |
| ---------------- | ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------- |
| `@lynx-js/genui` | **0.5.0（锁精确版本）**                                      | 官方 lynx-family 包；0.x 阶段迭代快（4 个月 14 版），禁止 `^` 浮动                                       |
| 协议版本         | A2UI **v0.9**（稳定 v0.9.1）                                 | 上游升 v1.0（当前 Candidate）时需回归                                                                    |
| peer 依赖        | `@lynx-js/react >=0.121.0`                                   | 模板 `^0.126.0` 满足；确认卡组件集（Text/Row/Column/Card/Divider/Button）运行时不依赖 `@lynx-js/lynx-ui` |
| 引擎             | Lynx 4.1（模板 `pluginReactLynx({ engineVersion: "4.1" })`） | 官方未声明引擎级兼容矩阵，真机行为按 §6 验证                                                             |

## 3. 宿主 bundle（`lynx_miniapp_template/`）

| 文件                          | 职责                                                                                                                                                                                                                                                                           |
| ----------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `src/a2ui-card.tsx`           | `A2UICard` 组件：`useInitData()` 取 `messages` → `createMessageStore` 一次性灌入；`<A2UI messageStore catalogs onAction>` 渲染；`onAction` 只放行 `confirm`/`cancel` 两个事件名并映射 `LynxBridge.invoke("confirmResult", {...}, "ui")`；answered 一次性防连点（失败回退可点） |
| `scripts/a2ui-card-entry.tsx` | 入口挂载                                                                                                                                                                                                                                                                       |
| `lynx.a2ui-card.config.ts`    | 复用基座配置（engineVersion 4.1），独立 entry `a2ui-card`，输出目录环境变量 `MINIAPP_A2UI_CARD_OUTPUT_DIR`，`cleanDistPath: false` 不触碰用户 `dist/`                                                                                                                          |
| 构建产物                      | `dist-a2ui-card/a2ui-card.lynx.bundle`（tasm 二进制，按入口命名）→ 复制为 `example/assets/miniapp/a2ui-card.lynx.bundle`，随 App 版本内置，经 `loadFromTemplateBytes` 直喂                                                                                                     |

**回传契约（`ui.confirmResult`）**：`onAction` 收到 `UserActionPayload{name, surfaceId, sourceComponentId, timestamp, context}` 后：

```ts
LynxBridge.invoke(
  "confirmResult",
  {
    ...action.context, // 小柯塞进 event.context 的 params 先展开
    action: action.name, // 契约键后置，防 context 同名键覆盖
    confirmationId: initData?.confirmationId,
    token: initData?.token ?? "",
  },
  "ui",
);
```

宿主收到的 payload：`{action: "confirm"|"cancel", confirmationId?, token?, ...context}` ——
与既有确认卡契约一致，宿主路由确认单 execute/cancel，Dart 插件侧零改动。

**主题注入契约（initData.theme）**：目录组件已做实现层美化（`src/a2ui-card-catalog.tsx`，
语义逐字复刻官方实现、仅呈现层换内联样式），颜色全部走 `A2UICardTheme` 默认亮色板；
宿主可在 initData 增加可选 `theme` 命名空间覆写任意键（如 kmanager 明暗主题切换时注入
`{"theme": {"background": "#111318", "surface": "#1b1d22", ...}}`）。键白名单收敛：非主题键、
非字符串值一律忽略。`theme` 不播种进渲染器数据模型（模板不允许 path 绑定主题键）。

## 4. Catalog = 组件白名单（沙箱边界）

Catalog 即渲染端组件白名单：消息引用白名单外组件时官方渲染器 fail-soft（告警一次、渲染 null），不崩宿主。
当前白名单（以 `src/a2ui-card.tsx` 实际注册为准）：`basicFunctions`（官方基础函数集，数据绑定/校验求值所需）+ `Text / Row / Column / Card / Divider / Button / Image / List / Loading`（确认卡与展示卡所需子集）。
九个组件的实现已换成 `src/a2ui-card-catalog.tsx` 的美化版（语义逐字复刻官方实现，仅呈现层内联样式 + 主题注入；displayName 仍显式钉住防压缩白屏）；**白名单集合与语义边界不变**。
白名单扩充 = 数组加一个内置组件，消息面与渲染面同步收敛；禁止全量引入 22 个内置组件中的输入类组件
（TextField/RadioGroup/ChoicePicker/Slider/DateTimeInput/Modal）除非业务评审通过；Icon 因真机无 Material Icons 字体会渲染为乱码文本，同样排除。

**弹窗/浮层属宿主能力，模板不承载弹窗结构**（用户 2026-09-28 拍板）：沙箱无 Modal 类组件；
模板确需弹出呈现的场景（详情展开/二次提示），只输出 action 事件回传语义，由宿主决定用原生
弹窗/半屏/页面呈现；模板只负责卡内布局。这是把「开发者受控组件」原则贯彻到呈现形态层。

## 5. 数据与安全边界

- **无网络、无文件**：模型消息与业务数据全部经 `initialData`（initData 通道）注入；bundle 不发起任何请求。

- **数据模型播种**：宿主把 initData 的契约命名空间（`/payload/*`、`/confirmationId`、`/statusText`、`/label/*`）在首条 `createSurface` 后以一条播种 `updateDataModel` 灌进渲染器数据模型；生产模板零 `updateDataModel`、零硬编码文案——文案/字段全部 path 绑定（`label.confirm/cancel/...` 等由宿主按三语注入）。模板自带 `updateDataModel` 时按消息序覆盖播种值；`token` 等非契约字段刻意不进数据模型，避免凭据经绑定渗入 UI。
- **ID 一律字符串**：`confirmationId`、`quantity` 等业务值在 dataModel 中以字符串承载（JSON 大整数过桥丢精度），Skill 提示语中硬约束。
- **单向回传**：模板动作出口只有 `ui.confirmResult`（白名单模块授权 `allowedModules: {"system", "ui"}`）；不接 Agent 回路（action 不回服务端），确认卡是一次性渲染。
- **既有链路不变**：文件 url 链路、`loadFromSource`/`templateBytes` 协议、既有小程序流程零改动。

## 6. 真机端到端验证（Android / iOS）

1. 构建：`cd lynx_miniapp_template && MINIAPP_A2UI_CARD_OUTPUT_DIR="$(pwd)/dist-a2ui-card" ./node_modules/.bin/rspeedy build --config lynx.a2ui-card.config.ts --no-env`，产物复制到 `example/assets/miniapp/a2ui-card.lynx.bundle`（仓库内已内置一份，886 KB tasm 二进制）。
2. 运行示例：`flutter run -d <Android或iOS测试设备>`（example App，包名 `com.kmanager.flutter_lynx_example`，勿覆盖业务 App）。
3. 进「A2UI 确认卡」页签 → 点「装载」→ 卡片渲染（标题/字段/两按钮）→ 点「确认补货」/「再想想」→ 切「JSB 调测日志」页签核对 `ui.confirmResult 回传: {action, confirmationId, quantity, ...}`。
4. 验收标准：消息 → 渲染 → 点击 → 回传四步全部成立；连点只回传一次；宿主 resolve 后关闭半屏即销毁 surface。

## 7. 给小柯 Skill 的消息样例

权威样例：`example/assets/a2ui/confirm-card-messages.json`（协议结构测试 `test/a2ui_message_asset_test.dart` 守护）。
骨架（2 条消息：createSurface + updateComponents；数据由宿主经 initData 播种，模板零携带，节选）：

```json
[
  {
    "version": "v0.9",
    "createSurface": {
      "surfaceId": "xiaoke-confirm-card",
      "catalogId": "https://a2ui.org/specification/v0_9/catalogs/basic/catalog.json"
    }
  },
  {
    "version": "v0.9",
    "updateComponents": {
      "surfaceId": "xiaoke-confirm-card",
      "components": [
        {
          "id": "root",
          "component": "Column",
          "children": ["title", "…", "actions"]
        },
        {
          "id": "title",
          "component": "Text",
          "text": { "path": "/label/title" },
          "variant": "h3"
        },
        {
          "id": "f-stock-value",
          "component": "Text",
          "text": { "path": "/payload/stock" }
        },
        {
          "id": "btn-confirm",
          "component": "Button",
          "variant": "primary",
          "child": "btn-confirm-label",
          "action": {
            "event": {
              "name": "confirm",
              "context": {
                "confirmationId": { "path": "/confirmationId" },
                "quantity": { "path": "/payload/quantity" }
              }
            }
          }
        }
      ]
    }
  }
]
```

宿主须随 initData 注入契约命名空间：`payload`（候选字段）、`confirmationId`、`statusText`、`label`（`title/description/product/stock/quantity/confirm/cancel` 等，按三语注入）。

硬约束（写进 Skill 提示语）：`version` 恒 `v0.9`；必须含 `root` 根组件；`children`/`child` 只能 id 引用不得内联；
只用白名单组件（§4）；只用字面量与 path 绑定（禁函数调用），绑定只落 `/payload/*`、`/label/*`、`/confirmationId`、`/statusText`；
业务值/ID 全字符串（禁数值转换）；文案零硬编码（一律 `/label/*` 绑定）。展示卡消息可包 a2ui 围栏（`a2ui，注意不是 `lynx），解析分段器需支持该标记。弹窗/浮层不进模板（属宿主能力）：需弹出呈现只发 action 事件回传，由宿主用原生弹窗/半屏/页面承载。

## 9. 已知坑与排查分流

### 9.1 生产压缩剥离组件函数名 → Lynx 1101 白屏（已修，2026-09-28）

**根因链**：生产构建压缩剥离组件函数名 → genui `defineCatalog` 按
`displayName ?? 函数名` 派生组件名失败 → catalog 注册抛
`Lynx 1101 "Cannot add a component to the catalog: no displayName or function name"`
→ **渲染树静默死亡，而 `onLoadSuccess` 照常回调**。

最迷惑点：失败发生在**渲染期**而不是装载期——bundle 装载成功会让人往
数据注入/消息格式方向排查，实际是 catalog 注册问题。kmanager 已在真机/
模拟器用真实 PRODUCT_CREATE 模板复现并验证修复。

**修法**：白名单组件显式钉 displayName（`src/a2ui-card.tsx` 的
`catalogComponents` 表已落地，即官方错误信息指名的修法）；自定义组件同理，
必须设 `displayName` 或用 `[组件, manifest]` 元组注册。

### 9.2 渲染期失败 vs 装载期失败的排查分流

| 现象                        | 定位           | 排查方向                                                             |
| --------------------------- | -------------- | -------------------------------------------------------------------- |
| `onLoadFail` 回调           | **装载期**失败 | bundle 字节/大小、initData 编解码、引擎装载参数                      |
| 白屏但 `onLoadSuccess` 照常 | **渲染期**失败 | catalog 注册（见 9.1）、消息 Schema 违约、白名单外组件、CSS/字体缺失 |

## 8. 桌面策略（延后说明）

桌面 A2UI 子集渲染器延后出本任务范围（kmanager 桌面 runtime 为纯 Flutter shim，任何格式均需自写渲染器），
策略待定；期间桌面不承载模型生成 UI。备选实现 lynx-card/1 已保留（见文首链接），可随时回退启用。
