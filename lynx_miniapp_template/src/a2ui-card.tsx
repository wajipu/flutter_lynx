import { useMemo, useState, useInitData } from "@lynx-js/react";
import {
  A2UI,
  basicFunctions,
  createMessageStore,
  normalizePayloadToMessages,
} from "@lynx-js/genui/a2ui";
import type {
  CatalogComponent,
  CatalogInput,
  UserActionPayload,
} from "@lynx-js/genui/a2ui";
// A2UIRenderer 内部兜底渲染（默认 unsupported/loading 兜底）仍引用 --a2ui-*
// CSS 变量；白名单组件已全部换成美化实现，这里保留官方 theme.css 与
// a2ui-light/a2ui-dark 包裹类，让兜底路径有变量可用——宿主按 App 明暗经
// initData.appearance（"dark"/"light"）注入，内部组件与兜底渲染同步换肤。
import "@lynx-js/genui/a2ui/styles/theme.css";
// 提交离场动效（上滑淡出）：@keyframes 只能走样式表，见 a2ui-card-exit.css。
import "./a2ui-card-exit.css";
// Lucide 图标字体（子集）：Icon 组件以码点字形渲染，见 a2ui-card-font.css。
import "./a2ui-card-font.css";
import { LynxBridge } from "./bridge";
import {
  createCatalogComponents,
  mergeA2UICardTheme,
  type A2UICardTheme,
} from "./a2ui-card-catalog";

/** 宿主经 initData 注入的参数形状（与 ui.confirmResult 回传契约对齐）。 */
interface A2UICardInitData {
  token?: string;
  confirmationId?: string;
  /** A2UI v0.9 消息数组（小柯/服务端下发的协议消息流）。 */
  messages?: unknown[];
  /** 候选字段（生产模板经 {"path": "/payload/..."} 绑定）。 */
  payload?: unknown;
  /** 卡片状态文案（如「待确认」）。 */
  statusText?: unknown;
  /** 三语文案命名空间（label.confirm/cancel/...，模板零硬编码文案）。 */
  label?: unknown;
  /**
   * 可选主题覆写（A2UICardTheme 子集，明暗主题切换时由宿主注入）。属呈现层
   * 配置：不播种进渲染器数据模型，模板不允许 path 绑定主题键。
   */
  theme?: unknown;
}

/**
 * 把 initData 的契约命名空间播种进渲染器数据模型：在首条 createSurface 之后
 * 插入一条播种 updateDataModel（协议要求 surface 先建），模板自带
 * updateDataModel 时按消息序覆盖播种值。token 等非契约字段不进数据模型，
 * 避免凭据经绑定渗入 UI。
 */
function buildInitialMessages(
  rawMessages: unknown[],
  seed: Record<string, unknown>,
): unknown[] {
  if (Object.keys(seed).length === 0) return rawMessages;
  const messages = [...rawMessages];
  const surfaceIndex = messages.findIndex(
    (message) =>
      typeof message === "object" &&
      message !== null &&
      "createSurface" in message,
  );
  if (surfaceIndex < 0) return messages;
  const surfaceId = (
    messages[surfaceIndex] as { createSurface?: { surfaceId?: unknown } }
  ).createSurface?.surfaceId;
  if (typeof surfaceId !== "string" || surfaceId.length === 0) return messages;
  messages.splice(surfaceIndex + 1, 0, {
    version: "v0.9",
    updateDataModel: { surfaceId, path: "/", value: { ...seed } },
  });
  return messages;
}

// 生产构建压缩函数名，defineCatalog 靠 displayName ?? 函数名派生组件名；
// 压缩后函数名丢失会让 catalog 注册抛 Lynx 1101、整卡白屏（docs §9.1）。
// 这里用一处显式断言对齐声明差异，运行时行为与官方示例一致。
function catalogEntry(component: unknown): CatalogComponent {
  return component as CatalogComponent;
}

// 卡片化外壳：白底 + 圆角 + 阴影，浮在 theme.background 衬底上，模板根
// Column 零改动即获得卡片语境；answered 时降透明度防连点。圆角对齐
// AppRadius.card=14，内边距对齐 AppInsets.card=16。
function cardShellStyle(theme: A2UICardTheme): Record<string, string | number> {
  return {
    width: "100%",
    backgroundColor: theme.surface,
    borderRadius: "14px",
    padding: "16px",
    boxShadow: theme.cardShadow,
  };
}

function placeholderStyle(
  theme: A2UICardTheme,
): Record<string, string | number> {
  return {
    color: theme.onSurfaceMuted,
    fontSize: "13px",
    lineHeight: "18px",
    padding: "16px 4px",
  };
}

/**
 * A2UI 宿主卡片（小柯助手）：内嵌官方 @lynx-js/genui 的 <A2UI> 渲染器，
 * 渲染宿主经 Dart 侧 initialData 注入的 A2UI v0.9 消息流。
 *
 * catalog 即组件白名单（沙箱边界）：展示类组件 Text/Row/Column/Card/
 * Divider/Button/Icon/Image/List/Loading/Tabs/LineChart/PieChart/BarChart/
 * ScatterChart/RadarChart/FunnelChart/StatCard/RankList/ProgressRing/
 * ComparisonRow，全部为
 * 本地美化实现；输入类组件（TextField/RadioGroup/...）仍刻意排除（docs §4）。
 * Icon 用内置 Lucide 矢量数据渲染（原字体方案真机乱码，故排除；改矢量后解除）。
 */
export function A2UICard() {
  const initData = useInitData() as A2UICardInitData | undefined;
  const [answered, setAnswered] = useState(false);

  // 主题挂载期固定：initData 与 messages 一样视为挂载期常量。
  const theme = useMemo(() => mergeA2UICardTheme(initData?.theme), []);

  // 消息流只在挂载时经 initData 注入一次，store 随之只建一次；后续要支持
  // 多轮交互时，把小柯回包 push 进同一 store 即可。
  const store = useMemo(() => {
    const rawMessages = Array.isArray(initData?.messages)
      ? (initData!.messages as unknown[]).slice()
      : [];
    const seed: Record<string, unknown> = {};
    const seedKeys = [
      "payload",
      "confirmationId",
      "statusText",
      "label",
    ] as const;
    for (const key of seedKeys) {
      const value = initData?.[key];
      if (value !== undefined && value !== null) {
        seed[key] = value;
      }
    }
    return createMessageStore({
      initialMessages: normalizePayloadToMessages(
        buildInitialMessages(rawMessages, seed),
      ),
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps -- initData 挂载期常量
  }, []);

  // 美化版目录组件随主题一次性创建；displayName 显式钉住（docs §9.1）。
  const { catalog, components: catalogComponents } = useMemo(() => {
    const components = createCatalogComponents(theme);
    for (const [name, component] of Object.entries(components)) {
      (component as { displayName?: string }).displayName = name;
    }
    // basicFunctions 是 A2UI v0.9 基础目录的函数实现（CatalogFunctionEntry[]，
    // 可直接展开）；不展开的话消息里的 functionCall 数据绑定会解析失败。
    return {
      catalog: [
        ...basicFunctions,
        catalogEntry(components.Text),
        catalogEntry(components.Row),
        catalogEntry(components.Column),
        catalogEntry(components.Card),
        catalogEntry(components.Divider),
        catalogEntry(components.Button),
        catalogEntry(components.Icon),
        catalogEntry(components.Image),
        catalogEntry(components.List),
        catalogEntry(components.Loading),
        catalogEntry(components.Tabs),
        catalogEntry(components.LineChart),
        catalogEntry(components.PieChart),
        catalogEntry(components.BarChart),
        catalogEntry(components.ScatterChart),
        catalogEntry(components.RadarChart),
        catalogEntry(components.FunnelChart),
        catalogEntry(components.StatCard),
        catalogEntry(components.RankList),
        catalogEntry(components.ProgressRing),
        catalogEntry(components.ComparisonRow),
        catalogEntry(components.Timeline),
        catalogEntry(components.BadgeGroup),
        catalogEntry(components.Accordion),
        catalogEntry(components.AreaChart),
        catalogEntry(components.StackedBar),
        catalogEntry(components.DataTable),
        catalogEntry(components.Gauge),
        catalogEntry(components.CountUp),
      ] as readonly CatalogInput[],
      components,
    };
  }, [theme]);

  const handleAction = (payload: UserActionPayload) => {
    const action = payload.name;
    // 只处理确认/取消两个动作，其余事件（如表单 setValue）直接忽略。
    if (action !== "confirm" && action !== "cancel") return;
    if (answered) return;
    // 先置位再上报：对齐 confirm-card.tsx 的防连点语义，bridge 回调可能晚到。
    setAnswered(true);
    // 合并顺序刻意安排：context 先展开、契约字段后置，防止 context 里同名键
    // 覆盖 action/confirmationId/token。
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

  // 根节点用 scroll-view（Lynx 内置滚动原语，竖向）：内容超过可视高度时
  // 卡内自滚动（LynxView 本体不带滚动）。内层容器 minHeight 100% 保证
  // 短内容（确认卡）时衬底色仍铺满视口。
  return (
    <scroll-view
      style={{ width: "100%", height: "100%" }}
      scroll-orientation="vertical"
    >
      <view
        style={{
          width: "100%",
          minHeight: "100%",
          backgroundColor: theme.background,
          display: "flex",
          flexDirection: "column",
          padding: "12px",
        }}
      >
        <A2UI
          messageStore={store}
          catalogs={catalog}
          onAction={handleAction}
          wrapSurface={(children, _ctx) => (
            <view
              className={
                (initData?.appearance === "dark" ? "a2ui-dark " : "a2ui-light ") +
                (answered && theme.exitAnimation !== "none"
                  ? "a2ui-card-exit"
                  : "a2ui-anim-rise")
              }
              style={
                answered
                  ? { ...cardShellStyle(theme), opacity: 0.5 }
                  : cardShellStyle(theme)
              }
            >
              {children}
            </view>
          )}
          renderEmpty={() => (
            <text style={placeholderStyle(theme)}>正在加载卡片内容…</text>
          )}
          renderError={() => (
            <text style={placeholderStyle(theme)}>
              卡片内容加载失败，请退出后重试。
            </text>
          )}
          renderUnsupported={(info) => (
            <text style={placeholderStyle(theme)}>
              {`暂不支持的卡片元素：${info.tag}（${info.kind}）`}
            </text>
          )}
        />
      </view>
    </scroll-view>
  );
}
