import { defineConfig } from "@lynx-js/rspeedy";
import { pluginReactLynx } from "@lynx-js/react-rsbuild-plugin";

export default defineConfig({
  plugins: [
    pluginReactLynx({ targetSdkVersion: "3.2" }),
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
