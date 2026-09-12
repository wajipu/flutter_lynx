import path from "node:path";
import { defineConfig } from "@lynx-js/rspeedy";
import config from "./lynx.config.ts";

const outputDirectory = process.env.MINIAPP_BUILD_OUTPUT_DIR;
if (!outputDirectory || !path.isAbsolute(outputDirectory)) {
  throw new Error("上传构建仅由 miniapp:upload 创建独立输出目录，禁止回退到 dist");
}

// Reuse the normal build; isolate upload output so user-owned dist stays intact.
export default defineConfig({
  ...config,
  source: {
    ...config.source,
    entry: { main: "./scripts/miniapp-entry.tsx" },
  },
  output: {
    ...config.output,
    cleanDistPath: false,
    distPath: { ...config.output?.distPath, root: outputDirectory },
  },
});
