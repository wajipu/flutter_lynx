import { InitDataProvider, root } from "@lynx-js/react";
import { RuntimeValidation } from "./runtime-validation";

root.render(
  <InitDataProvider>
    <RuntimeValidation variant="A" />
  </InitDataProvider>,
);
