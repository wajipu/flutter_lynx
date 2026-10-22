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
宿主可在 initData 增加可选 `theme` 命名空间覆写任意键（如宿主明暗主题切换时注入
`{"theme": {"background": "#111318", "surface": "#1b1d22", ...}}`）。键白名单收敛：非主题键、
非字符串值一律忽略。`theme` 不播种进渲染器数据模型（模板不允许 path 绑定主题键）。
主题键含行为项 `exitAnimation`：`"fade-up"`（默认，提交后 320ms 上滑淡出）或 `"none"`
（关闭离场动效，提交后仅降透明防连点——in-chat 等卡片不离场、提交后转终态只读卡的
场景注入此键）。

**提交离场动效**：确认/取消提交后卡片自带 320ms 上滑淡出（`src/a2ui-card-exit.css`
的 `a2ui-card-exit` 类，@keyframes 走样式表——Lynx 内联样式不支持关键帧动画；
注意 flex 简写里 basis 为 0 必须带单位，如 `flex: "1 1 0%"`，无单位会被引擎静默丢弃）。
上报失败恢复可点时类被移除、卡片回到可见，动画天然可逆。**宿主建议收到
`ui.confirmResult` 后延迟 ~350ms 再关半屏**，与卡片动画衔接。

## 4. Catalog = 组件白名单（沙箱边界）

Catalog 即渲染端组件白名单：消息引用白名单外组件时官方渲染器 fail-soft（告警一次、渲染 null），不崩宿主。
当前白名单（以 `src/a2ui-card.tsx` 实际注册为准，共 29 组件）：`basicFunctions`（官方基础函数集，数据绑定/校验求值所需）+ 官方移植 `Text / Row / Column / Card / Divider / Button / Icon / Image / List / Loading / Tabs` + 图表 `LineChart / BarChart / PieChart / ScatterChart / RadarChart / FunnelChart / AreaChart / StackedBar / Gauge` + KPI 与流程 `StatCard / RankList / ProgressRing / ComparisonRow / Timeline / BadgeGroup / Accordion / DataTable / CountUp`（确认卡与展示卡所需子集）。
十三个组件的实现已换成 `src/a2ui-card-catalog.tsx` 的美化版（语义逐字复刻官方实现，仅呈现层内联样式 + 主题注入；displayName 仍显式钉住防压缩白屏）；**白名单语义边界不变**。视觉规范对齐宿主 App 设计系统（`lib/theme/app_theme.dart`：Spring Green `#126652` 品牌主色、Paper `#FAFAFA`、Ink `#171D1F`、Apple HIG 字阶、卡片圆角 14、图标尺寸 16/20/24），并以 `A2UICardTheme` 键暴露；宿主明暗切换时经 `initData.theme` 注入 `darkA2UICardTheme` 同源色板即可。

**引擎图形能力实测（2026-09-28，iOS 模拟器）**：本引擎 `image` 不支持 SVG data URI（base64/URL 编码均空白）、`<svg>` 元素不渲染，`@font-face` base64 可用。据此：

- **Icon** 用 Lucide 图标字体子集渲染（`src/a2ui-card-icon-font.ts` + `a2ui-card-font.css`，fontTools.subset 裁剪到白名单 29 个码点仅 5.5KB；数据源 lucide-static/ISC），码点字形颜色随主题文本色；未映射名静默渲染空。
- **LineChart** 用纯 view 绘制（网格/轴线为 1px view，折线为「中心点定位 + rotate」的线段 view，数据点为圆 view），画布固定 300px 设计宽；支持点选列——tap 整列热区出参考线 + 放大数据点 + 数值气泡，再 tap 取消。
- **PieChart 占比条**支持点选行——选中行数值转主色加粗、其余行淡化，再 tap 取消。
- **PieChart** 为真·环形/饼图：圆环拆成每 6° 一段的切线旋转矩形逼近（与折线/雷达同款线段技术），`donut` 内径 52 / `pie` 小孔 14，图例含数值与百分比，点选扇形高亮；进场为顺时针 0→100 扫描（每段按角度错峰）。
- **BarChart**（柱状图）为宿主自有扩展组件（官方 basic catalog 无此组件，Skill 约束需显式教给模型）：props 与 LineChart 对齐（labels + series），基线从 0 起，`showValues: true` 显示柱顶数值，支持点选整组高亮 + 数值气泡。
- **ScatterChart**（散点图）/ **RadarChart**（雷达图）/ **FunnelChart**（漏斗图，居中递减条画法）均为宿主自有扩展组件，view 绘制：散点支持点选列（参考线 + 数值气泡），雷达支持图例点选系列高亮，漏斗支持点选行（转化率显示为相对首行的百分比）。
- Tabs 页签标题为字面量（官方 Tabs 直读 props.tabs，页签标题不做 path 绑定）；图表 labels/series/data 为顶层 prop 的 path 绑定（渲染器解析）。展示卡演示消息见 `example/assets/a2ui/display-card-messages.json`（守护测试 `test/a2ui_display_card_messages_test.dart`）。
  白名单扩充 = 数组加一个内置组件，消息面与渲染面同步收敛；禁止全量引入 22 个内置组件中的输入类组件
  （TextField/RadioGroup/ChoicePicker/Slider/DateTimeInput/Modal）除非业务评审通过；Icon 已解除排除
  （实现见上方引擎图形能力实测——图标字体子集方案）。

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
2. 运行示例：`flutter run -d <Android或iOS测试设备>`（example App，包名 `io.github.wajipu.flutter_lynx_example`，勿覆盖业务 App）。
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

**图表颜色契约（防报错）**：所有图表的颜色三级回滚——数据项级 `color`（如 `series[].color`、`data[].color`）→ 图表级 `colors` 数组（任意图表可传，覆盖系列色板）→ 默认色板自动轮转。三级全部可省略：不传任何颜色时自动按默认色板生成，**不传不报错、非法值（非字符串/空串）忽略并回滚**，渲染永不因颜色失败。

硬约束（写进 Skill 提示语）：`version` 恒 `v0.9`；必须含 `root` 根组件；`children`/`child` 只能 id 引用不得内联；
只用白名单组件（§4）；只用字面量与 path 绑定（禁函数调用），绑定只落 `/payload/*`、`/label/*`、`/confirmationId`、`/statusText`；
业务值/ID 全字符串（禁数值转换）；文案零硬编码（一律 `/label/*` 绑定）；
**禁用一切 SVG 表达**（宿主引擎不支持 SVG：模板不产出 svg 内容/属性，图表用 LineChart/BarChart/PieChart/ScatterChart/RadarChart/FunnelChart 承载）；
Tabs 页签标题为字面量（`tabs[].title` 不做 path 绑定）；图表数据走 `labels`/`series`/`data` 顶层 prop 的 path 绑定。展示卡消息可包 a2ui 围栏（`a2ui，注意不是 `lynx），解析分段器需支持该标记。弹窗/浮层不进模板（属宿主能力）：需弹出呈现只发 action 事件回传，由宿主用原生弹窗/半屏/页面承载。

## 8.5 渲染 bundle 的 OSS 动态下发（LynxBundleUpdater）

渲染 bundle 支持不发版热修（渲染层 bug / 间距调整等）；新增组件属白名单扩张仍走 App 版本评审。

**OSS 布局**（产物按版本归档永不覆盖，`manifest.json` 只是指针，回滚/提升秒级生效）：

```text
oss://<bucket>/<prefix>/a2ui/
  ├─ manifest.json
  └─ <version>/a2ui-card.lynx.bundle   # version = git短SHA-时间戳，如 8008c75-20260929T1530
```

**manifest v2**（兼容 v1 扁平 `{version,url,md5}`，视为仅 stable）：

```json
{
  "stable": {"version": "8008c75-…", "url": "oss://…/a2ui-card.lynx.bundle", "md5": "…"},
  "gray":   {"version": "8c32b02-…", "url": "…", "md5": "…", "percent": 10}
}
```

**客户端**（flutter_lynx 已导出 `LynxBundleUpdater`）：

```dart
final r = await LynxBundleUpdater().resolve(
  manifestUrl: "https://<cdn>/a2ui/manifest.json",
  builtinBytes: 内置资产bytes,   // 兜底
  cacheDirectory: 缓存目录,
  deviceId: 设备ID,             // 灰度分桶用，可空
);
// r.bytes / r.source(network|cache|builtin) / r.channel(stable|gray) / r.version
// LynxView onLoadFail 时（source 非 builtin）：updater.markLoadFailed(cacheDirectory:…, version: r.version!)
// → 本机熔断该版本回退内置，OSS 发新版本号后自动放行
```

行为要点：manifest 请求带 `t` 参数防 CDN 缓存；本地缓存 version+md5 双一致免下载；下载 MD5 校验失败清缓存回退内置；灰度按 deviceId FNV-1a 稳定分桶（同设备结果恒定，桶号 < percent 吃 gray）。

**一键发布**（`lynx_miniapp_template/`，前置：本机 ossutil + `A2UI_OSS_BUCKET` 环境变量）：

```bash
npm run a2ui:release                                        # 发布 stable
A2UI_CHANNEL=gray A2UI_GRAY_PERCENT=10 npm run a2ui:release # 灰度 10%
npm run a2ui:promote -- <version>                           # 灰度转正
A2UI_MD5=<发布时的md5> npm run a2ui:rollback -- <version>    # 回滚
npm run a2ui:status                                         # 查看远端 manifest
```

URL 链路小程序不走本机制（`LynxMiniProgramManager` 既有下载/缓存/回退不变；两者底层共用 `BundleDownloader`）。

**轻量管理页**（`npm run a2ui:admin`，浏览器操作 OSS 上的 manifest/发布记录）：

```bash
A2UI_OSS_BUCKET=oss://<bucket>/<prefix>/a2ui \
A2UI_PUBLIC_BASE=https://<bucket>.oss-cn-x.aliyuncs.com/<prefix>/a2ui \
npm run a2ui:admin          # 打开 http://127.0.0.1:8788
A2UI_OSS_STUB_DIR=/tmp/stub npm run a2ui:admin   # 无 OSS 本地演示模式
```

页面能力：查看 stable/gray 当前生效版本与发布记录（含备注/时间/大小）、
调整灰度比例、灰度转正、一键回滚历史版本（md5 自动取自发布记录索引
`releases/index.json`，每次 release 自动追加）、暂停下发（kill switch——
manifest 写 `{paused:true}`，客户端校验不过全量回退内置）。默认仅绑定
127.0.0.1；对外暴露（`A2UI_ADMIN_BIND=0.0.0.0`）必须配 `A2UI_ADMIN_TOKEN`。

注意：release 需同时设 `A2UI_PUBLIC_BASE`（manifest 里的 url 是客户端
dio 直接下载的 HTTPS 地址，不是 ossutil 的 oss:// 路径）。

## 9. 已知坑与排查分流

### 9.1 生产压缩剥离组件函数名 → Lynx 1101 白屏（已修，2026-09-28）

**根因链**：生产构建压缩剥离组件函数名 → genui `defineCatalog` 按
`displayName ?? 函数名` 派生组件名失败 → catalog 注册抛
`Lynx 1101 "Cannot add a component to the catalog: no displayName or function name"`
→ **渲染树静默死亡，而 `onLoadSuccess` 照常回调**。

最迷惑点：失败发生在**渲染期**而不是装载期——bundle 装载成功会让人往
数据注入/消息格式方向排查，实际是 catalog 注册问题。宿主 App 已在真机/
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

桌面 A2UI 子集渲染器延后出本任务范围（宿主 App 桌面 runtime 为纯 Flutter shim，任何格式均需自写渲染器），
策略待定；期间桌面不承载模型生成 UI。备选实现 lynx-card/1 已保留（见文首链接），可随时回退启用。
