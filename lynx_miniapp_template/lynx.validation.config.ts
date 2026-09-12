import path from "node:path";
import { defineConfig } from "@lynx-js/rspeedy";
import config from "./lynx.config.ts";

const outputDirectory = process.env.MINIAPP_VALIDATION_OUTPUT_DIR;
if (!outputDirectory || !path.isAbsolute(outputDirectory)) {
  throw new Error("Runtime validation requires an explicit absolute MINIAPP_VALIDATION_OUTPUT_DIR");
}

export default defineConfig({
  ...config,
  source: {
    ...config.source,
    entry: {
      "validation-a": "./scripts/runtime-validation-a.tsx",
      "validation-b": "./scripts/runtime-validation-b.tsx",
    },
  },
  output: {
    ...config.output,
    cleanDistPath: false,
    distPath: { ...config.output?.distPath, root: outputDirectory },
  },
});
