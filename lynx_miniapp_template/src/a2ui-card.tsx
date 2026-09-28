import { useMemo, useState, useInitData } from "@lynx-js/react";
import {
  A2UI,
  Button,
  Card,
  Column,
  Divider,
  Image,
  List,
  Loading,
  Row,
  Text,
  basicFunctions,
  createMessageStore,
  normalizePayloadToMessages,
} from "@lynx-js/genui/a2ui";
import type {
  CatalogComponent,
  CatalogInput,
  UserActionPayload,
} from "@lynx-js/genui/a2ui";
// 官方主题变量（--a2ui-*，定义在 :root/.a2ui-light/.a2ui-dark 上）。
// 内置组件的 CSS 依赖这些变量，这里显式引入并配合下方 a2ui-light 包裹类。
import "@lynx-js/genui/a2ui/styles/theme.css";
import { LynxBridge } from "./bridge";

/** 宿主经 initData 注入的参数形状（与 ui.confirmResult 回传契约对齐）。 */
interface A2UICardInitData {
  token?: string;
  confirmationId?: string;
  /** A2UI v0.9 消息数组（小柯/服务端下发的协议消息流）。 */
  messages?: unknown[];
}

// 样式全部内联，对齐 confirm-card.tsx（已在真机引擎上验证过的写法）；
// as const 让属性保持字面量类型以满足 Lynx CSSProperties 的联合类型约束。
const containerStyle = {
  width: "100%",
  minHeight: "100%",
  backgroundColor: "#ffffff",
  display: "flex",
  flexDirection: "column",
  padding: "20px 16px 16px 16px",
} as const;

const surfaceStyle = {
  width: "100%",
  display: "flex",
  flexDirection: "column",
} as const;

const placeholderStyle = {
  color: "#646a73",
  fontSize: "14px",
  padding: "8px 0px",
} as const;

// 内置组件各自声明了具体 Props（TextProps/RowProps…），而 catalog 的组件
// 槽位按 GenericComponentProps 宽松接收（props 由渲染器按协议流注入）。
// 官方 defineCatalog 文档示例就是直接传 Text/Button，只是那要在关掉
// strictFunctionTypes 时才可直接通过；这里用一处显式断言对齐声明差异，
// 运行时行为与官方示例一致。
function catalogEntry(component: unknown): CatalogComponent {
  return component as CatalogComponent;
}

const catalog: readonly CatalogInput[] = [
  // basicFunctions 是 A2UI v0.9 基础目录的函数实现，官方类型为
  // CatalogFunctionEntry[]（可直接展开进 catalogs）；不展开的话消息里的
  // functionCall 数据绑定会解析失败。
  ...basicFunctions,
  catalogEntry(Text),
  catalogEntry(Row),
  catalogEntry(Column),
  catalogEntry(Card),
  catalogEntry(Divider),
  catalogEntry(Button),
  catalogEntry(Image),
  catalogEntry(List),
  catalogEntry(Loading),
];

/**
 * A2UI 宿主卡片（小柯助手）：内嵌官方 @lynx-js/genui 的 <A2UI> 渲染器，
 * 渲染宿主经 Dart 侧 initialData 注入的 A2UI v0.9 消息流。
 *
 * catalog 即组件白名单（沙箱边界）：渲染器只会实例化列进 catalogs 的
 * 组件，消息里出现白名单之外的组件走 renderUnsupported 占位，不存在
 * 任意组件执行面。这里只放确认卡需要的展示类组件；输入类组件
 * （TextField/CheckBox/Slider/ChoicePicker/DateTimeInput/RadioGroup/Modal）
 * 属于表单交互面，确认卡场景用不到，刻意排除（@lynx-js/lynx-ui 仅作为
 * genui 可选 peer 安装以通过打包解析，白名单并不放行这些组件）；
 * Icon 依赖 Material Icons 字体，真机无字体源会渲染成乱码文本，同样排除。
 */
export function A2UICard() {
  const initData = useInitData() as A2UICardInitData | undefined;
  const [answered, setAnswered] = useState(false);

  // 消息流只在挂载时经 initData 注入一次，store 随之只建一次；
  // 后续要支持多轮交互时，把小柯回包 push 进同一 store 即可。
  const store = useMemo(
    () =>
      createMessageStore({
        initialMessages: initData?.messages
          ? normalizePayloadToMessages(initData.messages)
          : [],
      }),
    // initData 视为挂载期常量（与 confirm-card.tsx 的读取方式一致）。
    // eslint-disable-next-line react-hooks/exhaustive-deps -- 见上注释
    [],
  );

  const handleAction = (payload: UserActionPayload) => {
    const action = payload.name;
    // 只处理确认/取消两个动作，其余事件（如表单 setValue）直接忽略。
    if (action !== "confirm" && action !== "cancel") return;
    if (answered) return;
    // 先置位再上报：对齐 confirm-card.tsx 的防连点语义，bridge 回调可能晚到。
    setAnswered(true);
    // 合并顺序刻意安排：context 先展开、契约字段后置，防止 context 里
    // 同名键覆盖 action/confirmationId/token。finalFields 若存在则随
    // context 一并透传。
    const params: Record<string, unknown> = {
      ...payload.context,
      action,
      token: initData?.token ?? "",
    };
    if (initData?.confirmationId != null) {
      params.confirmationId = initData.confirmationId;
    }
    LynxBridge.invoke("confirmResult", params, "ui").catch(() => {
      // 上报失败恢复可点，宿主未收到结果时用户仍可重试或划掉半屏。
      setAnswered(false);
      console.warn("a2ui-card: ui.confirmResult 上报失败");
    });
  };

  return (
    <view style={containerStyle}>
      <A2UI
        messageStore={store}
        catalogs={catalog}
        onAction={handleAction}
        wrapSurface={(children, _ctx) => (
          <view
            className="a2ui-light"
            style={answered ? { ...surfaceStyle, opacity: 0.5 } : surfaceStyle}
          >
            {children}
          </view>
        )}
        renderEmpty={() => (
          <text style={placeholderStyle}>正在加载卡片内容…</text>
        )}
        renderError={() => (
          <text style={placeholderStyle}>卡片内容加载失败，请退出后重试。</text>
        )}
        renderUnsupported={(info) => (
          <text style={placeholderStyle}>
            {`暂不支持的卡片元素：${info.tag}（${info.kind}）`}
          </text>
        )}
      />
    </view>
  );
}
