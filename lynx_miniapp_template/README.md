# Lynx 动态小程序开发模板

本模板基于 [LynxJS](https://lynxjs.org/) 构建，专为宿主 App 的动态小程序容器定制。

## 目录说明

- `src/index.tsx`: 小程序页面主入口（使用 ReactLynx 语法）
- `src/bridge.ts`: 宿主 JSBridge 客户端 SDK（提供扫码、原生 UI、`data` 业务数据白名单方法等能力；宿主不存在的 `network`/`user` 代理已按假数据清除计划移除，不得重新宣称）
- `src/styles.css`: 小程序样式定义
- `lynx.config.ts`: Rspeedy 构建配置
- `scripts/miniapp-entry.tsx`: 挂载已有页面的入口，不改动业务页面
- `lynx.upload.config.ts`: 复用正常构建，输出到本次上传独有的临时目录
- `lynx.validation.config.ts`、`scripts/runtime-validation*.tsx`: 真实运行时 A/B 验证页，不引入业务界面或测试框架
- `scripts/miniapp-upload.mjs`: 固定配置校验、真实构建、SHA-256 与草稿上传

## 本地开发与构建

1. 安装依赖：
```bash
npm install
```

2. 本地调试（配合 Lynx Explorer App）：
```bash
npm run dev
```

3. 构建发布产物：
```bash
npm run build
```
正常构建会在 `dist/` 目录生成真正的 `main.lynx.bundle`，会替换同名旧产物。若 `dist/` 存在需要保留的未提交文件，使用下面的隔离构建命令，不直接执行默认构建。Web 的拖拽/点选上传继续保留，上传后仍需独立校验与正式发布；得到草稿不代表 Flutter 宿主已可运行。

### 真实编译链与 SDK 目标

构建插件固定为官方 `@lynx-js/react-rsbuild-plugin@0.20.2`，不再引用不存在的 `@lynx-js/react/rspeedy`。`0.20.2` 仍传递依赖 `@lynx-js/tasm@0.0.49`，该编码器只接受 `engineVersion` `[1.0, 3.9]`。官方 `@lynx-js/tasm@0.0.53`（2026-09-07，与 Lynx 4.1.0 同日发布）已把支持上限升到 4.2，因此模板用 `overrides` 钉死 `tasm@0.0.53`，才能编 `engineVersion: "4.1"`。`lynx.config.ts` 显式配置 `pluginReactLynx({ engineVersion: "4.1" })`，与宿主官方引擎 4.1.0 对齐。正常构建和上传共用 `scripts/miniapp-entry.tsx` 的 `root.render(<App />)` 挂载入口，不修改已有业务页面。该选项是最低 Lynx Engine 版本，不是 React npm 包版本。[官方兼容性](https://lynxjs.org/guide/compatibility)

已有其他依赖声明范围保持不变，新 `package-lock.json` 固定安装结果；后续重现使用 `npm ci`。

**锁文件平台陷阱**：`@rspack/binding-wasm32-wasi`（optional）与 `@napi-rs/wasm-runtime`（peer）引用 `@emnapi/core`/`@emnapi/runtime`@1.11.3。macOS 上的 `npm install` 重写锁时不物化这两个条目，而 Linux 的 `npm ci` 严格校验要求它们存在——锁里必须保留这两条（registry 真实 integrity）。**在 macOS 跑过 `npm install` 后提交前必须检查**：
```bash
grep -c '"node_modules/@emnapi/core"' package-lock.json   # 期望 1
grep -c '"node_modules/@emnapi/runtime"' package-lock.json # 期望 1
```当前锁定 ReactLynx `0.126.1`、Rspeedy `0.17.2`、编码器 `@lynx-js/tasm@0.0.53`。没有把整个 npm 包改成 ESM，以免改变旧脚本语义；Node 可能提示 TS 配置文件未声明 module type，但不影响构建。

保留 `dist/` 的完整模板隔离构建：

```bash
export MINIAPP_BUILD_OUTPUT_DIR="$(mktemp -d /tmp/lynx-template-build.XXXXXX)"
./node_modules/.bin/rspeedy build --config lynx.upload.config.ts --no-env
```

产物为 `$MINIAPP_BUILD_OUTPUT_DIR/main.lynx.bundle`。这个命令只编译，不上传、不读取会话。

旧的 `build:bundle` JSON包装脚本和命令已由真实构建替代并移除；已有 `dist/` 或 example 演示包可能仍是历史JSON产物，本次保留用户改动，不拿它们充当成功证据。CLI只使用本次真实构建输出。

## 开发人员上传草稿

需要满足现有 Rspeedy 的 Node 版本要求（`^20.19.0 || >=22.12.0`），并先安装本项目锁定的依赖。CLI 本身仅使用 Node 标准库，不会自动安装依赖、登录或更新版本号。

### 1. 填写固定配置

按 `miniapp.config.example.json` 创建 `miniapp.config.json`。示例里的空值/null **刻意无效**，必须自行填写，命令不会自动使用示例。`appCode` 从管理员已创建的真实应用复制，不自行编造或创建应用身份。

| 字段 | 要求 |
| --- | --- |
| `appCode` | 已有应用编码，1–64 字符，字母/数字/下划线/连字符 |
| `bundlePath` | **相对于本次构建输出目录**，通常为 `main.lynx.bundle`；不含 `dist/` 前缀，不允许绝对路径、`..` 或符号链接越界 |
| `lynxSdkVersion` | 实际兼容的 `x.y.z`，不是 npm 包版本；是否受支持由后端确认 |
| `bridgeApiVersion` | 已实现的正整数 Bridge 能力版本，不超过 `2147483647` |
| `minHostVersion` | `x.y.z+build`，所有整数组件不超过 `2147483647` |
| `translations` | 非空数组，项严格为 `{locale,changelog}`；changelog 1–4000 字符，不允许重复 locale，语言有效性及完整性由后端校验 |

配置拒绝未知字段。`versionName` 只读取 `package.json.version`，必须为 `x.y.z` 且各段不超过 `2147483647`。当前工作台包声明 `bridgeApiVersion: 2`（新增 `data` 业务数据模块，见 契约文档 13 号文）；声明 2 的包只有升级后的宿主会下载，旧宿主按清单直接过滤。配置里不存 Token、密码、Clientid、API 地址、任意 headers 或扩展字段。

### 2. 使用现有登录会话

由现有安全会话来源注入以下三个环境变量，再执行命令；不要把 Token 写在命令行、源码、配置文件、日志或 shell 历史里。

| 环境变量 | 内容 |
| --- | --- |
| `MINIAPP_API_BASE_URL` | 当前环境的远端 Cloud 基础地址，http 或 https 均可，不强制 TLS；可以包含部署路径前缀，不包含上传路由、账号密码、查询参数或 fragment |
| `MINIAPP_ACCESS_TOKEN` | 现有账号的原始登录 Token，不含 `Bearer ` 前缀 |
| `MINIAPP_CLIENT_ID` | 与该登录会话对应的现有 `Clientid` |

```bash
npm run miniapp:upload
```

也支持 `npm run miniapp:upload -- --session-stdin`：仅从安全管道读取固定 JSON `{apiBaseUrl,accessToken,clientId}`，不接受交互式终端明文输入，不与环境变量混用。让已有安全会话工具在内存中生成并通过管道传入；不要用包含真实 Token 的 `echo` 命令或落盘凭据文件。

这复用的是**现有用户会话及权限**，不是应用绑定的机器 Token。后端检查 `system:miniAppVersion:upload`；正式发布是另一个权限。账号本身可能还有其他权限，不能因为 CLI 没有发布命令就宣称 Token 只能上传。本工具不新增账号、开发者 Token 或另一套登录流程。

### 3. 构建、上传与结果

命令顺序固定：配置与会话校验 → 本工程 Rspeedy 真实构建 → 读取本次产物 → 计算 SHA-256 → 单次上传。构建使用 `--no-env`，会话环境变量不传给构建子进程。临时输出仅由本次命令创建和清理，不覆盖用户已有 `dist/`；构建失败、缺包、JSON 演示包、非二进制头或大于 10 MiB 都在上传前退出。

请求固定为 `POST <MINIAPP_API_BASE_URL>/system/mini-app-version/upload`，仅有 multipart 两项：

- `file`：本次生成的单个 `.lynx.bundle` 二进制。
- `metadata`（`application/json`）：`appCode,versionName,lynxSdkVersion,bridgeApiVersion,minHostVersion,translations,bundleSha256`。bundle 与发布方案全端统一，不选择 Android/iOS 目标平台。

不会发送 tenantId、用户 ID、OSS ID、状态、签名或任意扩展字段。远端 http/https 均可，不强制 TLS；拒绝本机/监听/局域网地址及解析到这些地址的域名。DNS 结果校验后固定用于此次连接，不跟随重定向，避免凭据被转发。

成功只报告 `R.data` 的固定字段：`appCode,versionId,versionName,status,validationStatus,validationMessage`。`status` 必须为 `0`（草稿）；校验状态 `0` 待校验 / `1` 通过 / `2` 失败。二进制头和摘要检查仅是上传前结构检查，不等于签名或运行时验证。命令不会启用应用、更新正式指针、灰度发布或正式发布。

上传超时、中断、权限错误、异常响应均非零退出，不自动重试。**请求发出后结果不确定，先在同一 Web 版本列表确认，不能盲目重跑制造重复草稿。** 已在隔离目录完成真实编译和定向 TypeScript 检查；未通过本命令连接真实服务上传。真实宿主验收与生产发布仍需分别验证。

## 原生 Bridge 与 A/B 运行时验证

原生调用固定为 `NativeModules.LynxBridge.call(module, method, params, callId, callback)`，响应仍为 `{callId,code,message,data?}`。不再通过 `getJSModule("LynxBridge")` 找原生模块；没有原生桥、原生调用异常或响应不匹配时 Promise 拒绝，不返回 Mock 用户、Token、扫码或网络成功。[官方 Native Modules](https://lynxjs.org/3.5/guide/use-native-modules.html)

Flutter → JS 使用原生 `sendGlobalEvent("onFlutterEvent", [{name, data}])`，JS 通过 `lynx.getJSModule("GlobalEventEmitter")` 订阅。`LynxBridge.on()` 必须在 `useEffect` 或背景线程事件处理器内调用，组件销毁时使用 `off()`；不得在双线程渲染或模块顶层获取事件模块。[官方事件订阅](https://lynxjs.org/3.5/guide/interaction/event-handling/event-propagation)

隔离构建两个真实 SDK 4.1 验证包，不触碰业务页面与 `dist/`：

```bash
export MINIAPP_VALIDATION_OUTPUT_DIR="$(mktemp -d /tmp/lynx-runtime-validation.XXXXXX)"
./node_modules/.bin/rspeedy build --config lynx.validation.config.ts --no-env
```

产物分别为 `$MINIAPP_VALIDATION_OUTPUT_DIR/validation-a.lynx.bundle` 和 `validation-b.lynx.bundle`。同一 Flutter 安装包加载两份产物后应分别显示 A/B，点击 `Increment` 应改变页面本地 `click-count`；`system-info` 必须显示原生 `system.getSystemInfo` 返回值而不是预设平台。宿主发送事件名 `host-ping` 后，页面 `host-events` 递增并显示收到的数据。编译成功和二进制头正确仅证明构建链，不能替代上述宿主交互验收。
