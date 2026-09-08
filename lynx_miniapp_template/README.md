# Lynx 动态小程序开发模板

本模板基于 [LynxJS](https://lynxjs.org/) 构建，专为 KManager 动态小程序容器定制。

## 目录说明
- `src/index.tsx`: 小程序页面主入口（使用 ReactLynx 语法）
- `src/bridge.ts`: 宿主 JSBridge 客户端 SDK（提供扫码、网络请求代理、用户信息获取、原生 UI 等能力）
- `src/styles.css`: 小程序样式定义
- `lynx.config.ts`: Rspeedy 构建配置

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
构建成功后，在 `dist/` 目录下会生成 `main.lynx.bundle`。将此 bundle 打包或上传至静态服务器/CDN，即可在 Flutter 宿主中动态热加载！
