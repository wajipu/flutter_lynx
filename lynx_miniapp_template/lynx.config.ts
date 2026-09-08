import { defineConfig } from "@lynx-js/rspeedy";
import { pluginReactLynx } from "@lynx-js/react/rspeedy";

export default defineConfig({
  plugins: [
    pluginReactLynx(),
  ],
  source: {
    entry: {
      main: "./src/index.tsx",
    },
  },
  output: {
    filename: "[name].lynx.bundle",
  },
});
