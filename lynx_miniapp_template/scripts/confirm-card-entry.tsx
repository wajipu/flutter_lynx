import { InitDataProvider, root } from "@lynx-js/react";
import { ConfirmCard } from "../src/confirm-card";

// 内容自包含在模板代码里；保留 InitDataProvider 包裹以兼容引擎初始化惯例。
root.render(
  <InitDataProvider>
    <ConfirmCard />
  </InitDataProvider>,
);
