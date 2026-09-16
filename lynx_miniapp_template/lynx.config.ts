import { defineConfig } from "@lynx-js/rspeedy";
import { pluginReactLynx } from "@lynx-js/react-rsbuild-plugin";

export default defineConfig({
  plugins: [
    pluginReactLynx({ engineVersion: "4.1" }),
  ],
  source: {
    entry: {
      main: "./scripts/miniapp-entry.tsx",
    },
  },
  output: {
    filename: "[name].lynx.bundle",
  },
});
