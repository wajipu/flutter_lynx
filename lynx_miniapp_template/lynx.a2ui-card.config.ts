import path from "node:path";
import { defineConfig } from "@lynx-js/rspeedy";
import config from "./lynx.config.ts";

const outputDirectory = process.env.MINIAPP_A2UI_CARD_OUTPUT_DIR;
if (!outputDirectory || !path.isAbsolute(outputDirectory)) {
  throw new Error(
    "A2UI card build requires an explicit absolute MINIAPP_A2UI_CARD_OUTPUT_DIR",
  );
}

// A2UI 宿主卡片独立构建：内嵌官方 @lynx-js/genui 渲染器，产物随 App 版本
// 内置，运行时由宿主 templateBytes 直喂加载。复用正常构建配置，仅替换入口
// 并隔离输出目录，不触碰用户自有的 dist/。
export default defineConfig({
  ...config,
  source: {
    ...config.source,
    entry: { "a2ui-card": "./scripts/a2ui-card-entry.tsx" },
  },
  output: {
    ...config.output,
    cleanDistPath: false,
    distPath: { ...config.output?.distPath, root: outputDirectory },
  },
});
