import path from "node:path";
import { defineConfig } from "@lynx-js/rspeedy";
import config from "./lynx.config.ts";

const outputDirectory = process.env.MINIAPP_CONFIRM_CARD_OUTPUT_DIR;
if (!outputDirectory || !path.isAbsolute(outputDirectory)) {
  throw new Error(
    "Confirm card build requires an explicit absolute MINIAPP_CONFIRM_CARD_OUTPUT_DIR",
  );
}

// 确认卡片独立构建：产物随 App 版本内置（宿主 App assets/miniapp/），
// 运行时由宿主 templateBytes 直喂，不走云端下发链。复用正常构建配置，
// 仅替换入口并隔离输出目录，不触碰用户自有的 dist/。
export default defineConfig({
  ...config,
  source: {
    ...config.source,
    entry: { "confirm-card": "./scripts/confirm-card-entry.tsx" },
  },
  output: {
    ...config.output,
    cleanDistPath: false,
    distPath: { ...config.output?.distPath, root: outputDirectory },
  },
});
