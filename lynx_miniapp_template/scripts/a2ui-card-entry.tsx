import { InitDataProvider, root } from "@lynx-js/react";
import { A2UICard } from "../src/a2ui-card";

// A2UI 消息与 token 由宿主经 initData 注入；保留 InitDataProvider 包裹以兼容引擎初始化惯例。
root.render(
  <InitDataProvider>
    <A2UICard />
  </InitDataProvider>,
);
