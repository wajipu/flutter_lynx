import {
  createContext,
  useContext,
  useEffect,
  useState,
  useSyncExternalStore,
} from "@lynx-js/react";
import {
  NodeRenderer,
  useChecks,
  useDataBinding,
  useResolvedProps,
} from "@lynx-js/genui/a2ui";
import type {
  ComponentInstance,
  GenericComponentProps,
  Resource,
  ResourceInfo,
  Surface,
} from "@lynx-js/genui/a2ui";
import { ICON_CODEPOINTS, ICON_FONT_FAMILY } from "./a2ui-card-icon-font";

/**
 * A2UI 目录组件的实现层美化（呈现层）。
 *
 * 语义与官方 @lynx-js/genui basic catalog 完全一致：数据绑定（useDataBinding）、
 * 动作门控（isValid && checks 求值后才 bindtap）、子组件解析（surface.resources /
 * NodeRenderer）、weight 权重布局、markdown 透传等行为逐字复刻官方实现——
 * 只把 className + CSS 换成内联样式（真机引擎上验证过的写法），并按确认卡
 * 场景调整字号层级 / 间距 / 圆角 / 配色。白名单组件集合不变。
 *
 * 颜色全部来自 A2UICardTheme：默认亮色板开箱舒适，宿主可经 initData.theme
 * 覆写任意键（kmanager 明暗主题切换时按主题注入）。
 */

/** 主题色板。宿主经 initData.theme 注入时只需给出要覆写的键。 */
export interface A2UICardTheme {
  /** 卡片之外的衬底色（页面/半屏底）。 */
  background: string;
  /** 卡片表面色。 */
  surface: string;
  /** 次级表面：filled 卡片、骨架屏、图片占位。 */
  surfaceMuted: string;
  /** 主文本（标题/字段值）。 */
  onSurface: string;
  /** 弱化文本（caption/字段标签）。 */
  onSurfaceMuted: string;
  /** 品牌主色（primary 按钮底色 / borderless 按钮文字色）。 */
  primary: string;
  /** 主色之上的文本色。 */
  onPrimary: string;
  /** outlined 卡片边框。 */
  border: string;
  /** 分隔线。 */
  divider: string;
  /** elevated 卡片阴影（完整 box-shadow 值；空串表示关闭阴影）。 */
  cardShadow: string;
  /**
   * 提交离场动效："fade-up"（默认，320ms 上滑淡出后交给宿主关闭）或
   * "none"（关闭动效，提交后仅降透明防连点——in-chat 等卡片不离场、
   * 提交后转终态只读卡的场景用）。
   */
  exitAnimation: string;
}

/** 默认亮色主题：Koklam 编辑风（kmanager AppTheme 亮色 token 同源）。 */
export const lightA2UICardTheme: A2UICardTheme = {
  background: "#FAFAFA", // lightPaper
  surface: "#FFFFFF", // lightSurface
  surfaceMuted: "#F4F4F5", // lightSubtle
  onSurface: "#171D1F", // lightInk
  onSurfaceMuted: "#747A76", // lightMuted
  primary: "#126652", // brandGreen（Spring Green）
  onPrimary: "#FFFFFF",
  // 亮色模式容器刻意不描边（宿主约定）；outlined 卡退化为分隔线色细边。
  border: "#EDEDEA", // lightDivider
  divider: "#EDEDEA", // lightDivider
  cardShadow: "0 2px 8px rgba(23, 29, 31, 0.04)",
  exitAnimation: "fade-up",
};

/** 暗色主题：Koklam 暗色 token 同源，宿主明暗切换时按 base 注入。 */
export const darkA2UICardTheme: A2UICardTheme = {
  background: "#09090B", // darkBackground
  surface: "#18181B", // darkSurface
  surfaceMuted: "#27272A", // darkSubtle
  onSurface: "#F5F7F1", // darkInk
  onSurfaceMuted: "#AEB8B2", // darkMuted
  primary: "#34D399", // darkBrandBright
  onPrimary: "#09090B",
  border: "#202020", // darkBorder
  divider: "#202020", // darkBorder
  cardShadow: "none",
  exitAnimation: "fade-up",
};

/** 兼容别名：默认主题即亮色。 */
export const defaultA2UICardTheme = lightA2UICardTheme;

/**
 * 合并宿主注入的主题覆写：只接受主题里已有的键且值非空字符串，其余
 * （未知键、非字符串、空值）一律忽略——initData 是宿主可信通道，但
 * 仍按白名单收敛，防止宿主误传把整块样式打挂。明暗切换时宿主可传
 * base=darkA2UICardTheme 再叠加覆写。
 */
export function mergeA2UICardTheme(
  overrides: unknown,
  base: A2UICardTheme = lightA2UICardTheme,
): A2UICardTheme {
  const theme: Record<string, string> = { ...base };
  if (overrides && typeof overrides === "object" && !Array.isArray(overrides)) {
    for (const [key, value] of Object.entries(overrides)) {
      if (key in theme && typeof value === "string" && value.length > 0) {
        theme[key] = value;
      }
    }
  }
  return theme as A2UICardTheme;
}

/** 语义色调基色：取 Tailwind 600 档，软徽章文字与浅面都从这里推导。 */
const SEMANTIC_TONE: Record<"success" | "warning" | "danger", string> = {
  success: "#16A34A",
  warning: "#D97706",
  danger: "#DC2626",
};

/** #RRGGBB 色向目标色按比例混合（t=0 全源色，t=1 全目标色）。
 *  软徽章用 surface 当底混出浅色面、onSurface 当墨混出可读文字：
 *  亮色主题把语义色压深、暗色主题提亮，两个模式都不需要第二套硬编码色板。 */
function mixHex(source: string, target: string, t: number): string {
  const parse = (value: string): [number, number, number] => {
    const raw = value.replace("#", "");
    const full =
      raw.length === 3
        ? raw
            .split("")
            .map((c) => c + c)
            .join("")
        : raw;
    const num = Number.parseInt(full.slice(0, 6).padEnd(6, "0"), 16);
    return [(num >> 16) & 255, (num >> 8) & 255, num & 255];
  };
  const [sr, sg, sb] = parse(source);
  const [tr, tg, tb] = parse(target);
  const channel = (from: number, to: number) =>
    Math.max(0, Math.min(255, Math.round(from + (to - from) * t)));
  return `#${[channel(sr, tr), channel(sg, tg), channel(sb, tb)]
    .map((v) => v.toString(16).padStart(2, "0"))
    .join("")}`;
}

// --- Props 类型：与官方内置组件的 Props 对齐（官方类型未导出，这里按
// dist/catalog/*/index.d.ts 声明复刻，运行时行为一致）。 ---

interface StyledTextProps extends GenericComponentProps {
  text: string;
  variant?: "h1" | "h2" | "h3" | "h4" | "h5" | "caption" | "body" | "markdown";
  emphasis?: "medium" | "strong";
}

interface StyledButtonProps extends GenericComponentProps {
  child: string;
  variant?: "primary" | "borderless";
  isValid?: boolean;
  action:
    | {
        event: { name: string; context?: Record<string, unknown> };
      }
    | {
        functionCall: {
          call: string;
          args: Record<string, unknown>;
          returnType?: string;
        };
      };
  checks?: Array<{ condition: unknown; message: string }>;
}

interface StyledStackProps extends GenericComponentProps {
  children?: string[] | { componentId: string; path: string };
  justify?:
    | "start"
    | "center"
    | "end"
    | "stretch"
    | "spaceBetween"
    | "spaceAround"
    | "spaceEvenly";
  align?: "start" | "center" | "end" | "stretch";
}

interface StyledCardProps extends GenericComponentProps {
  child: string;
  variant?: "elevated" | "outlined" | "filled" | "ghost";
  weight?: number;
}

interface StyledDividerProps extends GenericComponentProps {
  axis?: "horizontal" | "vertical";
}

interface StyledImageProps extends GenericComponentProps {
  url: string;
  fit?: "contain" | "cover" | "fill" | "none" | "scale-down";
  mode?: "scaleToFill" | "aspectFit" | "aspectFill" | "center";
  variant?:
    | "icon"
    | "avatar"
    | "smallFeature"
    | "mediumFeature"
    | "largeFeature"
    | "header";
  weight?: number;
}

interface StyledListProps extends GenericComponentProps {
  children?: string[] | { componentId: string; path: string };
  direction?: "horizontal" | "vertical";
  align?: "start" | "center" | "end" | "stretch";
}

interface StyledLoadingProps extends GenericComponentProps {
  variant?: "inline" | "block";
}

interface StyledIconProps extends GenericComponentProps {
  /** A2UI basic catalog 图标名（Material 语，如 "check"/"warning"），经 LUCIDE 映射渲染。 */
  name: string;
  size?: "sm" | "md" | "lg";
  color?: "primary" | "muted" | "inherit";
}

interface StyledTabsProps extends GenericComponentProps {
  tabs?: Array<{ title: string; child: string }>;
}

// 官方 CSS 用 .button .text-* 后代选择器把按钮内文字反色；内联样式优先级
// 高于样式继承，无法被父级覆写，因此用 context 把按钮态传给子 Text。
interface ButtonLabelState {
  variant: "primary" | "borderless";
  theme: A2UICardTheme;
}
const ButtonLabelContext = createContext<ButtonLabelState | null>(null);

// 官方 distribution-stretch 在 CSS 里没有对应规则（落到默认 flex-start），
// 这里保持同一行为：stretch 不产生 justifyContent。
type FlexJustify =
  | "flex-start"
  | "center"
  | "flex-end"
  | "space-between"
  | "space-around"
  | "space-evenly";

function toJustify(
  value:
    | "start"
    | "center"
    | "end"
    | "stretch"
    | "spaceBetween"
    | "spaceAround"
    | "spaceEvenly",
): FlexJustify {
  switch (value) {
    case "start":
      return "flex-start";
    case "center":
      return "center";
    case "end":
      return "flex-end";
    case "spaceBetween":
      return "space-between";
    case "spaceAround":
      return "space-around";
    case "spaceEvenly":
      return "space-evenly";
    default:
      return "flex-start";
  }
}

function toAlign(
  value: "start" | "center" | "end" | "stretch",
): "flex-start" | "center" | "flex-end" | "stretch" {
  switch (value) {
    case "start":
      return "flex-start";
    case "center":
      return "center";
    case "end":
      return "flex-end";
    default:
      return "stretch";
  }
}

// 字号/字重/行高层级：对齐 kmanager AppTypography（Apple HIG 刻度，全应用
// 禁止低于 11pt）：h1→title2(22) h2→title3(20，弹窗主标) h3→headline(17 导航/
// 卡片标题) h4→body-strong(15) h5→footnote-strong(13) body→body(15)
// caption→caption1(12，字段标签/徽章)。
const TEXT_VARIANTS = {
  h1: { fontSize: "22px", lineHeight: "30px", fontWeight: "700" },
  h2: { fontSize: "20px", lineHeight: "28px", fontWeight: "700" },
  h3: { fontSize: "17px", lineHeight: "22px", fontWeight: "600" },
  h4: { fontSize: "15px", lineHeight: "22px", fontWeight: "600" },
  h5: { fontSize: "13px", lineHeight: "18px", fontWeight: "600" },
  body: { fontSize: "15px", lineHeight: "22px", fontWeight: "400" },
  caption: { fontSize: "12px", lineHeight: "16px", fontWeight: "400" },
} as const;

type TextVariant = keyof typeof TEXT_VARIANTS;

/**
 * 构建美化版目录组件集。theme 在挂载期固定（initData 为挂载期常量），
 * 组件闭包引用它，随 factory 一次性创建。
 */
export function createCatalogComponents(theme: A2UICardTheme) {
  // outlined 卡边框：宿主未注入可用描边（空值/transparent；kmanager 亮色
  // border 为 transparent、经宿主 css 映射会落成 #000000）时退化为分隔线色
  // 细边——亮色容器不描边是宿主约定，卡片 hairline 观感由 divider 承担。
  const outlinedBorder = ["", "transparent", "#000000", "#00000000"].includes(
    theme.border.trim().toLowerCase(),
  )
    ? theme.divider
    : theme.border;
  function Text(props: StyledTextProps) {
    const variant = props.variant ?? "body";
    // 空文本折叠为 null：终态卡宿主将 /statusText 置空、状态改由壳层
    // terminalBadge 徽章承担，标题位不能留 lineHeight 空盒；对其他模板
    // 而言空字符串本就无内容可渲染，行为一致。
    if (props.text === undefined || props.text === null || props.text === "") {
      return null;
    }
    // markdown 走原生 x-markdown，与官方行为一致。
    if (variant === "markdown") {
      return <x-markdown content={props.text} />;
    }
    const inButton = useContext(ButtonLabelContext);
    let style: Record<string, string | number>;
    if (inButton) {
      // 按钮内文字随 variant 反色、加大到 15px/600（确认卡主按钮观感）。
      style = {
        fontSize: "15px",
        lineHeight: "20px",
        fontWeight: "600",
        flexShrink: 0,
        color:
          inButton.variant === "primary"
            ? inButton.theme.onPrimary
            : inButton.theme.primary,
      };
    } else {
      const base = TEXT_VARIANTS[variant as TextVariant];
      const weight =
        props.emphasis === "strong"
          ? "700"
          : props.emphasis === "medium"
            ? "600"
            : base.fontWeight;
      style = {
        fontSize: base.fontSize,
        lineHeight: base.lineHeight,
        fontWeight: weight,
        flexShrink: 0,
        color: variant === "caption" ? theme.onSurfaceMuted : theme.onSurface,
      };
    }
    return (
      <text key={props.id} style={style}>
        {props.text}
      </text>
    );
  }

  function Row(props: StyledStackProps) {
    const children = props.children;
    const surface = props.surface;
    const dataContextPath = props.dataContextPath;
    const justify = props.justify ?? "start";
    const align = props.align ?? "stretch";
    // 官方 Row 不支持动态模板 children（非数组时按空处理），保持一致。
    const explicitChildren = Array.isArray(children) ? children : [];
    return (
      <view
        style={{
          width: "100%",
          display: "flex",
          flexDirection: "row",
          flexWrap: "nowrap",
          gap: "8px",
          minWidth: 0,
          justifyContent: toJustify(justify),
          alignItems: toAlign(align),
        }}
      >
        {explicitChildren.map((childId) => {
          const child = surface.components.get(childId);
          if (!child) return null;
          const childWithContext = dataContextPath
            ? { ...child, dataContextPath: dataContextPath }
            : child;
          const weight = child.weight;
          if (typeof weight === "number" && weight > 0) {
            return (
              <view
                key={childId}
                style={{ flex: `${weight} ${weight} 0%`, minWidth: 0 }}
              >
                <NodeRenderer component={childWithContext} surface={surface} />
              </view>
            );
          }
          return (
            <NodeRenderer
              key={childId}
              component={childWithContext}
              surface={surface}
            />
          );
        })}
      </view>
    );
  }

  // 官方 Column 的 buildChild：静态 id 数组或动态模板（path + componentId）
  // 两种形态，逐字复刻。
  function buildChild(
    surface: StyledStackProps["surface"],
    childId: string,
    dataContextPath: string | undefined,
    childPath?: string,
    key: string = childId,
  ): { key: string; component: Record<string, unknown> } | null {
    const child = surface.components.get(childId);
    if (!child) return null;
    let childWithContext = child;
    if (childPath) {
      childWithContext = { ...child, dataContextPath: childPath };
    } else if (dataContextPath) {
      childWithContext = { ...child, dataContextPath };
    }
    return { key, component: childWithContext };
  }

  function Column(props: StyledStackProps) {
    const {
      children,
      surface,
      dataContextPath,
      justify = "start",
      align = "stretch",
    } = props;
    const isDynamic =
      children && !Array.isArray(children) && typeof children === "object";
    const template = isDynamic
      ? (children as { componentId: string; path: string })
      : undefined;
    const [columnData, , fullPath] = useDataBinding(
      template ? { path: template.path } : undefined,
      surface,
      dataContextPath,
      [],
    );
    const childList = Array.isArray(children)
      ? children.map((childId) => buildChild(surface, childId, dataContextPath))
      : (Array.isArray(columnData) ? columnData : []).map(
          (item: unknown, index: number) => {
            const key =
              item && typeof item === "object" && "key" in item
                ? String((item as Record<string, unknown>)["key"])
                : `${index}`;
            const itemPath = `${fullPath}/${index}`;
            return buildChild(
              surface,
              template?.componentId ?? "",
              dataContextPath,
              itemPath,
              key,
            );
          },
        );
    return (
      <view
        style={{
          width: "100%",
          display: "flex",
          flexDirection: "column",
          gap: "10px",
          minWidth: 0,
          justifyContent: toJustify(justify),
          alignItems: toAlign(align),
        }}
      >
        {childList.map((item) => {
          if (!item) return null;
          const weight = item.component.weight;
          if (typeof weight === "number" && weight > 0) {
            return (
              <view
                key={item.key}
                style={{ flex: `${weight} ${weight} 0%`, minHeight: 0 }}
              >
                <NodeRenderer component={item.component} surface={surface} />
              </view>
            );
          }
          return (
            <NodeRenderer
              key={item.key}
              component={item.component}
              surface={surface}
            />
          );
        })}
      </view>
    );
  }

  function cardStyle(
    variant: "elevated" | "outlined" | "filled" | "ghost",
    weighted: boolean,
  ): Record<string, string | number> {
    const base: Record<string, string | number> = {
      width: weighted ? "auto" : "100%",
      display: "flex",
      flexDirection: "column",
      boxSizing: "border-box",
      flexShrink: 0,
      minWidth: 0,
      gap: "10px",
    };
    switch (variant) {
      case "outlined":
        return {
          ...base,
          backgroundColor: theme.surface,
          borderRadius: "14px", // AppRadius.card
          padding: "16px", // AppInsets.card
          border: `1px solid ${outlinedBorder}`,
        };
      case "filled":
        return {
          ...base,
          backgroundColor: theme.surfaceMuted,
          borderRadius: "14px", // AppRadius.card
          padding: "16px", // AppInsets.card
        };
      case "ghost":
        return { ...base, backgroundColor: "transparent" };
      default:
        return {
          ...base,
          backgroundColor: theme.surface,
          borderRadius: "14px", // AppRadius.card
          padding: "16px", // AppInsets.card
          boxShadow: theme.cardShadow,
        };
    }
  }

  function Card(props: StyledCardProps) {
    const { child: childId, surface, dataContextPath } = props;
    const childComponent = surface.components.get(childId);
    const childWithContext =
      childComponent && dataContextPath
        ? { ...childComponent, dataContextPath }
        : childComponent;
    const variant = props.variant ?? "elevated";
    const weighted = typeof props.weight === "number";
    return (
      <view style={cardStyle(variant, weighted)}>
        {childWithContext && (
          <NodeRenderer component={childWithContext} surface={surface} />
        )}
      </view>
    );
  }

  function Button(props: StyledButtonProps) {
    const {
      action,
      child,
      id,
      isValid = true,
      surface,
      sendAction,
      variant = "primary",
      dataContextPath,
    } = props;
    const checks = props.checks;
    const { ok, firstFailureMessage } = useChecks({
      checks,
      componentId: id ?? "",
      surface,
      dataContextPath,
    });
    // 与官方一致：isValid（模型侧禁用）与 checks 求值同时通过才可点。
    const enabled = isValid && ok;
    // 按压降透明反馈（Elements ghost 态口径）：透明度由内联样式驱动，
    // 平滑过渡走 .a2ui-btn-press；禁用态维持 0.4，不叠加按压态。
    const [pressed, setPressed] = useState(false);
    const setPress = (down: boolean) => {
      if (enabled) setPressed(down);
    };
    const handleClick = () => {
      if (enabled && action) {
        void sendAction?.(action);
      }
    };
    const childResource = child ? surface.resources.get(child) : undefined;
    const shellStyle: Record<string, string | number> = {
      // flex:1 让并排按钮等分宽度（对齐 confirm-card 真机验证过的动作排布）；
      // 确认卡按钮都放在动作 Row 里，Column 直挂 Button 不在既定模板形态内。
      flex: "1 1 0%",
      height: "44px",
      display: "flex",
      flexDirection: "row",
      alignItems: "center",
      justifyContent: "center",
      borderRadius: "12px",
      paddingLeft: "16px",
      paddingRight: "16px",
      opacity: enabled ? (pressed ? 0.7 : 1) : 0.4,
    };
    if (variant === "primary") {
      shellStyle.backgroundColor = theme.primary;
    } else {
      shellStyle.backgroundColor = "transparent";
    }
    return (
      <>
        <ButtonLabelContext.Provider value={{ variant, theme }}>
          <view
            style={shellStyle}
            className="a2ui-btn-press"
            bindtap={enabled ? handleClick : undefined}
            bindtouchstart={enabled ? () => setPress(true) : undefined}
            bindtouchend={enabled ? () => setPress(false) : undefined}
            bindtouchcancel={enabled ? () => setPress(false) : undefined}
          >
            {childResource ? (
              <ResourceChild resource={childResource} surface={surface} />
            ) : (
              <text
                style={{
                  fontSize: "15px",
                  lineHeight: "20px",
                  fontWeight: "600",
                  color:
                    variant === "primary" ? theme.onPrimary : theme.primary,
                }}
              >
                Button
              </text>
            )}
          </view>
        </ButtonLabelContext.Provider>
        {!ok && firstFailureMessage ? (
          <text
            style={{
              marginTop: "4px",
              fontSize: "12px",
              lineHeight: "17px",
              color: "#d92d20",
            }}
          >
            {firstFailureMessage}
          </text>
        ) : null}
      </>
    );
  }

  function Divider(props: StyledDividerProps) {
    const axis = props.axis ?? "horizontal";
    return axis === "vertical" ? (
      <view
        key={props.id}
        style={{ width: "1px", height: "100%", backgroundColor: theme.divider }}
      />
    ) : (
      <view
        key={props.id}
        style={{
          width: "100%",
          height: "1px",
          flexShrink: 0,
          backgroundColor: theme.divider,
        }}
      />
    );
  }

  // fit → mode 的映射与官方一致（mode 显式给定时优先生效）。
  function mapFitToMode(
    fit: string,
  ): "scaleToFill" | "aspectFit" | "aspectFill" | "center" {
    switch (fit) {
      case "contain":
      case "scale-down":
        return "aspectFit";
      case "fill":
        return "scaleToFill";
      case "none":
        return "center";
      default:
        return "aspectFill";
    }
  }

  function imageStyle(
    variant: NonNullable<StyledImageProps["variant"]>,
    weighted: boolean,
  ): Record<string, string | number> {
    const base: Record<string, string | number> = {
      flexShrink: 0,
      overflow: "hidden",
      borderRadius: "12px",
      backgroundColor: theme.surfaceMuted,
    };
    let style: Record<string, string | number> = base;
    switch (variant) {
      case "icon":
        style = {
          ...base,
          width: "24px",
          height: "24px",
          borderRadius: "0px",
          backgroundColor: "transparent",
        };
        break;
      case "avatar":
        style = {
          ...base,
          width: "40px",
          height: "40px",
          borderRadius: "20px",
        };
        break;
      case "smallFeature":
        style = { ...base, maxWidth: "120px" };
        break;
      case "largeFeature":
        style = { ...base, maxHeight: "400px" };
        break;
      case "header":
        style = { ...base, width: "100%", height: "200px" };
        break;
      default:
        style = { ...base, maxWidth: "240px" };
    }
    if (weighted) {
      style = { ...style, flex: "1 1 0%" };
    }
    return style;
  }

  function Image(props: StyledImageProps) {
    const fit = props.fit ?? "fit";
    const mode = props.mode ?? mapFitToMode(fit);
    const variant = props.variant ?? "mediumFeature";
    const weighted = typeof props.weight === "number";
    return (
      <image
        key={props.id}
        style={imageStyle(variant, weighted)}
        auto-size={true}
        src={props.url ?? ""}
        mode={mode}
      />
    );
  }

  function List(props: StyledListProps) {
    const {
      children,
      surface,
      dataContextPath,
      direction = "vertical",
      align = "stretch",
    } = props;
    const isDynamic =
      children && !Array.isArray(children) && typeof children === "object";
    const template = isDynamic
      ? (children as { componentId: string; path: string })
      : undefined;
    const [listData, , fullPath] = useDataBinding(
      template ? { path: template.path } : undefined,
      surface,
      dataContextPath,
      [],
    );
    let content: Array<{
      key: string;
      component: Record<string, unknown>;
    } | null> = [];
    if (Array.isArray(children)) {
      content = children.map((childId) => {
        const child = surface.components.get(childId);
        if (!child) return null;
        const childWithContext = dataContextPath
          ? { ...child, dataContextPath: dataContextPath }
          : child;
        return { key: childId, component: childWithContext };
      });
    } else if (template) {
      const items = Array.isArray(listData) ? listData : [];
      content = items.map((item: unknown, index: number) => {
        const child = surface.components.get(template.componentId);
        if (!child) return null;
        const key =
          item && typeof item === "object" && "key" in item
            ? String((item as Record<string, unknown>)["key"])
            : `${index}`;
        const itemPath = `${fullPath}/${index}`;
        const childWithContext = { ...child, dataContextPath: itemPath };
        return { key, component: childWithContext };
      });
    }
    return (
      <list
        style={{
          width: "100%",
          height: "420px",
          display: "flex",
          flexDirection: direction === "vertical" ? "column" : "row",
          gap: "8px",
          minWidth: 0,
          alignItems: toAlign(align),
        }}
        scroll-orientation={
          direction === "vertical" ? "vertical" : "horizontal"
        }
        list-type="single"
        span-count={1}
      >
        {content.map((item) => {
          if (!item) return null;
          return (
            <list-item key={item.key} item-key={item.key}>
              <NodeRenderer component={item.component} surface={surface} />
            </list-item>
          );
        })}
      </list>
    );
  }

  function Loading(props: StyledLoadingProps) {
    const variant = props.variant ?? "inline";
    const skeletonStyle: Record<string, string | number> = {
      height: "14px",
      borderRadius: "999px",
      backgroundColor: theme.surfaceMuted,
    };
    return (
      <view
        style={{
          width: "100%",
          display: "flex",
          flexDirection: "column",
          alignItems: "stretch",
          justifyContent: "center",
          flexShrink: 0,
          gap: "10px",
          minHeight: variant === "block" ? "48px" : "14px",
          paddingTop: variant === "block" ? "6px" : "0px",
          paddingBottom: variant === "block" ? "6px" : "0px",
        }}
      >
        {/* Elements/zinc Skeleton 口径：占位条脉冲呼吸（类移除即静止）。 */}
        <view className="a2ui-skeleton" style={{ ...skeletonStyle, width: "96%" }} />
        {variant === "block" ? (
          <view
            className="a2ui-skeleton"
            style={{ ...skeletonStyle, width: "68%" }}
          />
        ) : null}
      </view>
    );
  }

  // 官方 Icon 靠 Material Icons 字体连字渲染，真机无字体源会输出乱码文本；
  // 本引擎 image 不支持 SVG data URI、<svg> 元素也不渲染（实测，见探针记录），
  // 因此改为 Lucide 图标字体子集（5.5KB woff2，@font-face base64 加载）：
  // name 映射码点，以 <text> 字形渲染——颜色随主题文本色，天然支持明暗主题。
  // 未映射的名字静默渲染空。
  function Icon(props: StyledIconProps) {
    const { id, name, size = "md", color = "inherit" } = props;
    const glyph = typeof name === "string" ? ICON_CODEPOINTS[name] : undefined;
    if (!glyph) return null;
    // 尺寸对齐 AppIconSize：sm 16 / md 20 / lg 24。
    const px = size === "sm" ? "16px" : size === "lg" ? "24px" : "20px";
    const colorValue =
      color === "primary"
        ? theme.primary
        : color === "muted"
          ? theme.onSurfaceMuted
          : theme.onSurface;
    return (
      <text
        key={id}
        style={{
          fontFamily: ICON_FONT_FAMILY,
          fontSize: px,
          lineHeight: px,
          color: colorValue,
          flexShrink: 0,
        }}
      >
        {glyph}
      </text>
    );
  }

  // --- Tabs / LineChart / PieChart：官方实现逐字移植，呈现层 Koklam 化。 ---

  function Tabs(props: StyledTabsProps) {
    const { surface, tabs } = props;
    const [selectedIndex, setSelectedIndex] = useState(0);
    const list = Array.isArray(tabs) ? tabs : [];
    const activeIndex =
      list.length > 0 ? Math.min(selectedIndex, list.length - 1) : 0;
    const activeTab = list[activeIndex];
    if (list.length === 0) {
      return <view style={{ width: "100%" }} />;
    }
    const activeChild = activeTab?.child
      ? surface.components.get(activeTab.child)
      : undefined;
    return (
      <view
        style={{
          width: "100%",
          display: "flex",
          flexDirection: "column",
          minWidth: 0,
        }}
      >
        <view
          style={{
            display: "flex",
            flexDirection: "row",
            gap: "12px",
            marginBottom: "12px",
            width: "100%",
          }}
        >
          {list.map((tab, index) => {
            const active = index === activeIndex;
            return (
              <view
                key={`${index}-${tab.child}`}
                style={{
                  paddingLeft: "2px",
                  paddingRight: "2px",
                  paddingTop: "8px",
                  paddingBottom: "10px",
                  borderBottom: active
                    ? `2px solid ${theme.primary}`
                    : `2px solid transparent`,
                }}
                bindtap={() => setSelectedIndex(index)}
              >
                <text
                  style={{
                    fontSize: "14px",
                    lineHeight: "20px",
                    fontWeight: "600",
                    flexShrink: 0,
                    color: active ? theme.primary : theme.onSurfaceMuted,
                  }}
                >
                  {tab.title}
                </text>
              </view>
            );
          })}
        </view>
        {activeChild && (
          <NodeRenderer component={activeChild} surface={surface} />
        )}
      </view>
    );
  }

  const DEFAULT_CHART_COLORS = [
    "#126652", // brandGreen
    "#F2B66D", // springWarm（暖琥珀）
    "#B98E79", // segmentDot（陶土）
    "#C5E1D4", // lightLime（浅青柠）
    "#145743", // tabActive（深绿）
    "#059669", // brandBright（翠绿）
  ];
  function formatValue(value: number): string {
    if (!Number.isFinite(value)) return "0";
    const rounded =
      Math.abs(value) >= 1000 ? Math.round(value) : Number(value.toFixed(1));
    return String(rounded);
  }

  const LINE_SVG_WIDTH = 360;
  const LINE_DEFAULT_HEIGHT = 240;
  const LINE_MARGIN = { top: 16, right: 16, bottom: 24, left: 16 };

  function normalizeSeries(
    series: unknown[],
    palette: string[],
  ): Array<{ name: string; values: number[]; color: string }> {
    return series.map((item, index) => {
      const record = (item ?? {}) as Record<string, unknown>;
      return {
        name: String(record["name"] ?? ""),
        values: Array.isArray(record["values"])
          ? (record["values"] as number[])
          : [],
        color:
          typeof record["color"] === "string"
            ? record["color"]
            : (palette[index % palette.length] ?? "#126652"),
      };
    });
  }





  function sampleIndices(count: number, maxLabels: number): number[] {
    if (count <= 0) return [];
    if (count <= maxLabels) {
      return Array.from({ length: count }, (_, index) => index);
    }
    const step = Math.ceil(count / maxLabels);
    const indices: number[] = [];
    for (let index = 0; index < count; index += step) {
      indices.push(index);
    }
    const last = count - 1;
    if (indices[indices.length - 1] !== last) {
      indices.push(last);
    }
    return Array.from(new Set(indices));
  }

  function minMax(values: number[]): { min: number; max: number } {
    if (values.length === 0) return { min: 0, max: 1 };
    let min = values[0]!;
    let max = values[0]!;
    for (const value of values) {
      if (value < min) min = value;
      if (value > max) max = value;
    }
    if (min === max) {
      min -= 1;
      max += 1;
    }
    return { min, max };
  }

  // --- 图表家族（2026-10-12 引擎级重写：纯流内布局）---
  // 深链二分 + 壳层探针结论：本 Lynx 引擎静默不支持 position:absolute
  // （探针 view 不渲染、无 JS 异常），原「300px 画布 + 绝对定位摆放」的
  // 九个图表组件整体塌掉。全部改为纯流内 flex：柱状/堆叠用等权列 + 底对
  // 齐，线/散点/面积用等宽列 + px 垫高表达点位，环形/仪表/饼图降级为条形
  // 表达。动效只挂纯 opacity 的 a2ui-anim-fade（真机已验证可跑；grow/pop
  // 依赖 transform 未验证，不挂在数据形状上）。引擎恢复 absolute 后可回
  // 滚本提交找回画布实现。

  // 图例行（流内）：色点 + 名称；onTap 传入时可点选（雷达系列切换）。
  function chartLegend(
    items: Array<{ name: string; color: string }>,
    onTap?: (index: number) => void,
    selectedIndex?: number | null,
  ): JSX.Element | null {
    if (items.length === 0) return null;
    return (
      <view
        style={{
          display: "flex",
          flexDirection: "row",
          flexWrap: "wrap",
          gap: "8px 14px",
          width: "100%",
        }}
      >
        {items.map((item, index) => {
          const dimmed =
            selectedIndex !== null &&
            selectedIndex !== undefined &&
            selectedIndex !== index;
          return (
            <view
              key={`lg-${item.name}-${index}`}
              style={{
                display: "flex",
                flexDirection: "row",
                alignItems: "center",
                gap: "6px",
                opacity: dimmed ? 0.4 : 1,
              }}
              bindtap={onTap ? () => onTap(index) : undefined}
            >
              <view
                style={{
                  width: "10px",
                  height: "10px",
                  borderRadius: "2px",
                  backgroundColor: item.color,
                }}
              />
              <text
                style={{
                  fontSize: "12px",
                  lineHeight: "16px",
                  color: theme.onSurfaceMuted,
                }}
              >
                {item.name}
              </text>
            </view>
          );
        })}
      </view>
    );
  }

  // 选中读出条（流内）：原画布浮动气泡的替代，选中态出现在图与轴标签之间。
  function chartReadout(
    label: string,
    values: Array<{ name: string; value: number }>,
  ): JSX.Element | null {
    if (!label) return null;
    return (
      <view
        style={{
          alignSelf: "center",
          display: "flex",
          flexDirection: "row",
          borderRadius: "6px",
          backgroundColor: theme.onSurface,
          paddingLeft: "8px",
          paddingRight: "8px",
          paddingTop: "4px",
          paddingBottom: "4px",
        }}
      >
        <text
          style={{
            fontSize: "10px",
            lineHeight: "13px",
            color: theme.surface,
          }}
        >
          {`${label}　${values
            .map((v) => `${v.name} ${formatValue(v.value)}`)
            .join(" · ")}`}
        </text>
      </view>
    );
  }

  // 基线（流内）：原画布内绝对定位基线的替代，独立一行居中。
  function chartBaseline(): JSX.Element {
    return (
      <view
        style={{
          width: "300px",
          height: "1.5px",
          alignSelf: "center",
          backgroundColor: theme.onSurfaceMuted,
        }}
      />
    );
  }

  function LineChart(props: GenericComponentProps) {
    const [resolvedProps] = useResolvedProps(
      props,
      props.surface,
      props.dataContextPath,
    );
    const id = props.id;
    // 点选态：tap 某列 → 读出条显示该列各系列数值；再 tap 取消。
    const [selectedDot, setSelectedDot] = useState<number | null>(null);
    const labelsValue = resolvedProps["labels"];
    const labels = Array.isArray(labelsValue) ? labelsValue : [];
    const seriesValue = resolvedProps["series"];
    // 图表级 colors 覆写：JSON 传 colors 数组则作为系列色板，不传用 Koklam 色板
    const chartPalette = Array.isArray(resolvedProps["colors"])
      ? (resolvedProps["colors"] as string[])
      : DEFAULT_CHART_COLORS;
    const series = Array.isArray(seriesValue)
      ? normalizeSeries(seriesValue, chartPalette)
      : [];
    const showLegend = resolvedProps["showLegend"] !== false;
    const heightValue = resolvedProps["height"];
    const height =
      typeof heightValue === "number" ? heightValue : LINE_DEFAULT_HEIGHT;
    const chartTitle =
      typeof resolvedProps["yLabel"] === "string"
        ? resolvedProps["yLabel"]
        : "";
    // 纯流内几何：等宽列表达 x 轴，「数据点 + 茎」棒棒糖形态表达 y；
    // 原折线段依赖引擎缺失的 absolute + rotate，降级为棒棒糖，趋势由相邻
    // 列高差读出，min/max 头行保留刻度感。showGrid/variant 不再生效。
    const plotH = Math.max(60, height - 40);
    const maxPoints = labels.length;
    const allValues = series.flatMap((item) => item.values.slice(0, maxPoints));
    const { min: plotMin, max: plotMax } = minMax(allValues);
    const plotRange = plotMax - plotMin;
    const pointColumns = labels.slice(0, maxPoints).map((_, index) => {
      const selected = selectedDot === index;
      return (
        <view
          key={`lcol-${index}`}
          style={{
            flex: "1 1 0%",
            height: `${plotH}px`,
            display: "flex",
            flexDirection: "row",
            alignItems: "flex-end",
            justifyContent: "center",
            gap: "3px",
            minWidth: 0,
          }}
          bindtap={() =>
            setSelectedDot(selectedDot === index ? null : index)
          }
        >
          {series.map((item, seriesIndex) => {
            const value = Number(item.values[index]) || 0;
            const ratio =
              plotRange === 0 ? 0.5 : (value - plotMin) / plotRange;
            const stemH = Math.max(2, ratio * (plotH - 18));
            return (
              <view
                key={`lpop-${seriesIndex}-${index}`}
                className="a2ui-anim-fade"
                style={{
                  display: "flex",
                  flexDirection: "column",
                  alignItems: "center",
                  animationDelay: `${index * 70 + seriesIndex * 35}ms`,
                }}
              >
                <view
                  style={{
                    width: `${selected ? 10 : 8}px`,
                    height: `${selected ? 10 : 8}px`,
                    borderRadius: "5px",
                    backgroundColor: item.color,
                    border: `1.5px solid ${selected ? theme.primary : theme.surface}`,
                  }}
                />
                <view
                  style={{
                    width: "2.5px",
                    height: `${stemH}px`,
                    backgroundColor: item.color,
                    opacity: 0.5,
                  }}
                />
              </view>
            );
          })}
        </view>
      );
    });
    const selectedLabel =
      selectedDot === null ? "" : String(labels[selectedDot] ?? "");
    const selectedValues =
      selectedDot === null
        ? []
        : series.map((item) => ({
            name: item.name,
            value: item.values[selectedDot] ?? 0,
          }));
    const visibleLabelIndices = sampleIndices(labels.length, 8);
    const { min, max } = minMax(
      series.flatMap((item) => item.values.slice(0, labels.length)),
    );
    return (
      <view
        key={id}
        style={{
          width: "100%",
          display: "flex",
          flexDirection: "column",
          gap: "8px",
          minWidth: 0,
        }}
      >
        {chartTitle ? (
          <text
            style={{
              fontSize: "16px",
              lineHeight: "22px",
              fontWeight: "600",
              color: theme.onSurface,
            }}
          >
            {chartTitle}
          </text>
        ) : null}
        <view
          style={{
            display: "flex",
            flexDirection: "row",
            justifyContent: "space-between",
            width: "100%",
          }}
        >
          <text
            style={{
              fontSize: "11px",
              lineHeight: "16px",
              color: theme.onSurfaceMuted,
            }}
          >
            {formatValue(min)}
          </text>
          <text
            style={{
              fontSize: "11px",
              lineHeight: "16px",
              color: theme.onSurfaceMuted,
            }}
          >
            {formatValue(max)}
          </text>
        </view>
        <view
          style={{
            width: "300px",
            display: "flex",
            flexDirection: "row",
            alignItems: "flex-end",
            alignSelf: "center",
          }}
        >
          {pointColumns}
        </view>
        {chartBaseline()}
        {chartReadout(selectedLabel, selectedValues)}
        <view
          style={{
            display: "flex",
            flexDirection: "row",
            justifyContent: "space-between",
            width: "100%",
          }}
        >
          {visibleLabelIndices.map((index) => (
            <text
              key={`${index}-${labels[index] ?? index}`}
              style={{
                fontSize: "11px",
                lineHeight: "16px",
                color:
                  selectedDot === index
                    ? theme.onSurface
                    : theme.onSurfaceMuted,
              }}
            >
              {labels[index] ?? ""}
            </text>
          ))}
        </view>
        {showLegend ? chartLegend(series) : null}
      </view>
    );
  }


  function formatPercent(value: number): string {
    if (!Number.isFinite(value)) return "0%";
    return `${Number(value.toFixed(1))}%`;
  }

  // --- BarChart（柱状图）：宿主自有扩展组件（官方 basic catalog 无此组件），
  // props 与 LineChart 对齐（labels + series），view 绘制：柱体为绝对定位
  // 矩形 view，基线从 0 起（柱状图惯例，不做 min-max 截断）。支持点选整组
  // 高亮 + 数值气泡，机制与 LineChart 一致。作为白名单扩展项写入 Skill 约束。 ---

  // --- BarChart（柱状图）：宿主自有扩展组件（官方 basic catalog 无此组件），
  // props 与 LineChart 对齐（labels + series）。纯流内：等权组列 + 底对齐
  // 柱体，网格线降级去掉、基线独立成行；点选整组高亮 + 读出条。 ---
  function BarChart(props: GenericComponentProps) {
    const [resolvedProps] = useResolvedProps(
      props,
      props.surface,
      props.dataContextPath,
    );
    const id = props.id;
    const [selectedGroup, setSelectedGroup] = useState<number | null>(null);
    const labelsValue = resolvedProps["labels"];
    const labels = Array.isArray(labelsValue) ? labelsValue : [];
    const seriesValue = resolvedProps["series"];
    const chartPalette = Array.isArray(resolvedProps["colors"])
      ? (resolvedProps["colors"] as string[])
      : DEFAULT_CHART_COLORS;
    const series = Array.isArray(seriesValue)
      ? normalizeSeries(seriesValue, chartPalette)
      : [];
    const showLegend = resolvedProps["showLegend"] !== false;
    // 协议层把布尔字面量序列化为数字（实测 true → 1），按真值归一判断。
    const showValues = Boolean(resolvedProps["showValues"]);
    const heightValue = resolvedProps["height"];
    const height = typeof heightValue === "number" ? heightValue : 200;
    const chartTitle =
      typeof resolvedProps["yLabel"] === "string"
        ? resolvedProps["yLabel"]
        : "";
    const canvasW = 300;
    const plotW = canvasW - 24;
    const plotH = Math.max(60, height - 24);
    const groupCount = labels.length;
    const groupW = groupCount > 0 ? plotW / groupCount : 0;
    const barGap = series.length > 1 ? 2 : 0;
    const barW = Math.max(
      4,
      Math.min(
        24,
        (groupW - 12 - (series.length - 1) * barGap) / (series.length || 1),
      ),
    );
    // 柱状图惯例：基线从 0 起，不做 min-max 截断。
    const allValues = series.flatMap((item) => item.values.slice(0, groupCount));
    const maxValue = allValues.reduce((acc, v) => (v > acc ? v : acc), 0);
    const scaleMax = maxValue > 0 ? maxValue : 1;
    const groupColumns = labels.slice(0, groupCount).map((_, groupIndex) => {
      const dimmed = selectedGroup !== null && selectedGroup !== groupIndex;
      return (
        <view
          key={`bgrp-${groupIndex}`}
          style={{
            flex: "1 1 0%",
            height: `${plotH}px`,
            display: "flex",
            flexDirection: "row",
            alignItems: "flex-end",
            justifyContent: "center",
            gap: `${barGap}px`,
            minWidth: 0,
            opacity: dimmed ? 0.35 : 1,
          }}
          bindtap={() =>
            setSelectedGroup(selectedGroup === groupIndex ? null : groupIndex)
          }
        >
          {series.map((item, seriesIndex) => {
            const v = Number(item.values[groupIndex]) || 0;
            const h = Math.max(2, (v / scaleMax) * (plotH - 20));
            return (
              <view
                key={`bar-${seriesIndex}-${groupIndex}`}
                style={{
                  display: "flex",
                  flexDirection: "column",
                  alignItems: "center",
                }}
              >
                {showValues ? (
                  <text
                    style={{
                      fontSize: "10px",
                      lineHeight: "12px",
                      marginBottom: "2px",
                      color: dimmed ? theme.onSurfaceMuted : theme.onSurface,
                    }}
                  >
                    {formatValue(v)}
                  </text>
                ) : null}
                <view
                  className="a2ui-anim-fade"
                  style={{
                    width: `${barW}px`,
                    height: `${h}px`,
                    borderTopLeftRadius: "4px",
                    borderTopRightRadius: "4px",
                    backgroundColor: item.color,
                    animationDelay: `${groupIndex * 60}ms`,
                  }}
                />
              </view>
            );
          })}
        </view>
      );
    });
    const selectedLabel =
      selectedGroup === null ? "" : String(labels[selectedGroup] ?? "");
    const selectedValues =
      selectedGroup === null
        ? []
        : series.map((item) => ({
            name: item.name,
            value: item.values[selectedGroup] ?? 0,
          }));
    return (
      <view
        key={id}
        style={{
          width: "100%",
          display: "flex",
          flexDirection: "column",
          gap: "8px",
          minWidth: 0,
        }}
      >
        {chartTitle ? (
          <text
            style={{
              fontSize: "16px",
              lineHeight: "22px",
              fontWeight: "600",
              color: theme.onSurface,
            }}
          >
            {chartTitle}
          </text>
        ) : null}
        <view
          style={{
            width: "300px",
            display: "flex",
            flexDirection: "row",
            alignItems: "flex-end",
            alignSelf: "center",
          }}
        >
          {groupColumns}
        </view>
        {chartBaseline()}
        {chartReadout(selectedLabel, selectedValues)}
        <view
          style={{
            width: "300px",
            display: "flex",
            flexDirection: "row",
            alignSelf: "center",
          }}
        >
          {labels.slice(0, groupCount).map((label, index) => (
            <text
              key={`${index}-${label ?? index}`}
              style={{
                flex: "1 1 0%",
                textAlign: "center",
                fontSize: "11px",
                lineHeight: "16px",
                color:
                  selectedGroup === index
                    ? theme.onSurface
                    : theme.onSurfaceMuted,
              }}
            >
              {label ?? ""}
            </text>
          ))}
        </view>
        {showLegend ? chartLegend(series) : null}
      </view>
    );
  }

  // --- ScatterChart（散点图）/ RadarChart（雷达图）/ FunnelChart（漏斗图）：
  // 宿主自有扩展组件（官方 basic catalog 无），全部纯 view 绘制。 ---

  // --- ScatterChart（散点图）：等宽列 + px 垫高让点浮在真实高度；
  // 未选中系列淡化，点选列出读出条。 ---
  function ScatterChart(props: GenericComponentProps) {
    const [resolvedProps] = useResolvedProps(
      props,
      props.surface,
      props.dataContextPath,
    );
    const id = props.id;
    const [selectedDot, setSelectedDot] = useState<number | null>(null);
    const labelsValue = resolvedProps["labels"];
    const labels = Array.isArray(labelsValue) ? labelsValue : [];
    const seriesValue = resolvedProps["series"];
    const chartPalette = Array.isArray(resolvedProps["colors"])
      ? (resolvedProps["colors"] as string[])
      : DEFAULT_CHART_COLORS;
    const series = Array.isArray(seriesValue)
      ? normalizeSeries(seriesValue, chartPalette)
      : [];
    const showLegend = resolvedProps["showLegend"] !== false;
    const heightValue = resolvedProps["height"];
    const height = typeof heightValue === "number" ? heightValue : 200;
    const chartTitle =
      typeof resolvedProps["yLabel"] === "string"
        ? resolvedProps["yLabel"]
        : "";
    const plotH = Math.max(60, height - 40);
    const maxPoints = labels.length;
    const allValues = series.flatMap((item) => item.values.slice(0, maxPoints));
    const { min: plotMin, max: plotMax } = minMax(allValues);
    const plotRange = plotMax - plotMin;
    const pointColumns = labels.slice(0, maxPoints).map((_, index) => {
      const selected = selectedDot === index;
      return (
        <view
          key={`scol-${index}`}
          style={{
            flex: "1 1 0%",
            height: `${plotH}px`,
            display: "flex",
            flexDirection: "row",
            justifyContent: "center",
            gap: "3px",
            minWidth: 0,
          }}
          bindtap={() =>
            setSelectedDot(selectedDot === index ? null : index)
          }
        >
          {series.map((item, seriesIndex) => {
            const value = Number(item.values[index]) || 0;
            const ratio =
              plotRange === 0 ? 0.5 : (value - plotMin) / plotRange;
            const topPad = Math.max(0, ratio * (plotH - 16));
            return (
              <view
                key={`sdot-${seriesIndex}-${index}`}
                className="a2ui-anim-fade"
                style={{
                  display: "flex",
                  flexDirection: "column",
                  animationDelay: `${index * 70 + seriesIndex * 35}ms`,
                }}
              >
                <view style={{ height: `${topPad}px` }} />
                <view
                  style={{
                    width: `${selected ? 11 : 9}px`,
                    height: `${selected ? 11 : 9}px`,
                    borderRadius: "5px",
                    backgroundColor: item.color,
                    opacity: selected || selectedDot === null ? 1 : 0.45,
                  }}
                />
              </view>
            );
          })}
        </view>
      );
    });
    const selectedLabel =
      selectedDot === null ? "" : String(labels[selectedDot] ?? "");
    const selectedValues =
      selectedDot === null
        ? []
        : series.map((item) => ({
            name: item.name,
            value: item.values[selectedDot] ?? 0,
          }));
    const visibleLabelIndices = sampleIndices(labels.length, 8);
    return (
      <view
        key={id}
        style={{
          width: "100%",
          display: "flex",
          flexDirection: "column",
          gap: "8px",
          minWidth: 0,
        }}
      >
        {chartTitle ? (
          <text
            style={{
              fontSize: "16px",
              lineHeight: "22px",
              fontWeight: "600",
              color: theme.onSurface,
            }}
          >
            {chartTitle}
          </text>
        ) : null}
        <view
          style={{
            width: "300px",
            display: "flex",
            flexDirection: "row",
            alignSelf: "center",
          }}
        >
          {pointColumns}
        </view>
        {chartBaseline()}
        {chartReadout(selectedLabel, selectedValues)}
        <view
          style={{
            display: "flex",
            flexDirection: "row",
            justifyContent: "space-between",
            width: "100%",
          }}
        >
          {visibleLabelIndices.map((index) => (
            <text
              key={`${index}-${labels[index] ?? index}`}
              style={{
                fontSize: "11px",
                lineHeight: "16px",
                color:
                  selectedDot === index
                    ? theme.onSurface
                    : theme.onSurfaceMuted,
              }}
            >
              {labels[index] ?? ""}
            </text>
          ))}
        </view>
        {showLegend ? chartLegend(series) : null}
      </view>
    );
  }

  // --- RadarChart（雷达图）：环形多边形依赖 absolute + rotate，降级为
  // 「逐指标横向条」——每个指标一根轨道，各系列按 max 归一填色，图例点选
  // 淡化其他系列。 ---
  function RadarChart(props: GenericComponentProps) {
    const [resolvedProps] = useResolvedProps(
      props,
      props.surface,
      props.dataContextPath,
    );
    const id = props.id;
    const [selectedSeries, setSelectedSeries] = useState<number | null>(null);
    const indicatorsValue = resolvedProps["indicators"];
    const indicators = Array.isArray(indicatorsValue)
      ? (indicatorsValue as Array<Record<string, unknown>>)
      : [];
    const seriesValue = resolvedProps["series"];
    const chartPalette = Array.isArray(resolvedProps["colors"])
      ? (resolvedProps["colors"] as string[])
      : DEFAULT_CHART_COLORS;
    const series = Array.isArray(seriesValue)
      ? normalizeSeries(seriesValue, chartPalette)
      : [];
    const showLegend = resolvedProps["showLegend"] !== false;
    const axisRows = indicators.map((indicator, axisIndex) => {
      const record = (indicator ?? {}) as Record<string, unknown>;
      const maxV = Number(record["max"]) || 1;
      return (
        <view
          key={`rax-${axisIndex}-${String(record["name"] ?? "")}`}
          style={{
            width: "100%",
            display: "flex",
            flexDirection: "row",
            alignItems: "center",
            gap: "8px",
          }}
        >
          <text
            style={{
              width: "72px",
              textAlign: "right",
              fontSize: "11px",
              lineHeight: "16px",
              color: theme.onSurfaceMuted,
            }}
          >
            {String(record["name"] ?? "")}
          </text>
          <view
            style={{
              flex: "1 1 0%",
              display: "flex",
              flexDirection: "column",
              gap: "3px",
              minWidth: 0,
            }}
          >
            {series.map((item, seriesIndex) => {
              const raw = Number(item.values[axisIndex]) || 0;
              const ratio = Math.max(0, Math.min(1, raw / maxV));
              const dimmed =
                selectedSeries !== null && selectedSeries !== seriesIndex;
              return (
                <view
                  key={`rbar-${seriesIndex}`}
                  className="a2ui-anim-fade"
                  style={{
                    height: "8px",
                    width: "100%",
                    borderRadius: "4px",
                    backgroundColor: theme.surfaceMuted,
                    overflow: "hidden",
                    animationDelay: `${axisIndex * 50 + seriesIndex * 30}ms`,
                  }}
                >
                  <view
                    style={{
                      height: "100%",
                      width: `${(ratio * 100).toFixed(1)}%`,
                      borderRadius: "4px",
                      backgroundColor: item.color,
                      opacity: dimmed ? 0.35 : 1,
                    }}
                  />
                </view>
              );
            })}
          </view>
        </view>
      );
    });
    return (
      <view
        key={id}
        style={{
          width: "100%",
          display: "flex",
          flexDirection: "column",
          gap: "10px",
          minWidth: 0,
        }}
      >
        {axisRows}
        {showLegend
          ? chartLegend(
              series,
              (index) =>
                setSelectedSeries(
                  selectedSeries === index ? null : index,
                ),
              selectedSeries,
            )
          : null}
      </view>
    );
  }

  function FunnelChart(props: GenericComponentProps) {
    const [resolvedProps] = useResolvedProps(
      props,
      props.surface,
      props.dataContextPath,
    );
    const id = props.id;
    // 图表级 colors 覆写（同 LineChart；不传用 Koklam 色板）
    const chartPalette = Array.isArray(resolvedProps["colors"])
      ? (resolvedProps["colors"] as string[])
      : DEFAULT_CHART_COLORS;
    const [selectedSlice, setSelectedSlice] = useState<number | null>(null);
    const dataValue = resolvedProps["data"];
    const slices = Array.isArray(dataValue)
      ? (dataValue as Array<Record<string, unknown>>)
      : [];
    const title =
      typeof resolvedProps["title"] === "string" && resolvedProps["title"]
        ? resolvedProps["title"]
        : "";
    const showValues = resolvedProps["showValues"] !== false;
    const palette = Array.isArray(resolvedProps["colors"])
      ? (resolvedProps["colors"] as string[])
      : DEFAULT_CHART_COLORS;

    // 环形几何：外径 84，donut 内径 52 / pie 内径 14（小孔近似实心）；
    // 圆环拆成每 SEG_STEP 度一段的切线矩形，段中心在弧中点、旋转对齐切线。

    const maxValue = slices.reduce(
      (acc, slice) => Math.max(acc, Number(slice["value"]) || 0),
      0,
    );
    const firstValue = Number(slices[0]?.["value"]) || 0;

    return (
      <view
        key={id}
        style={{
          width: "100%",
          display: "flex",
          flexDirection: "column",
          gap: "8px",
          minWidth: 0,
        }}
      >
        {title ? (
          <text
            style={{
              fontSize: "16px",
              lineHeight: "22px",
              fontWeight: "600",
              color: theme.onSurface,
            }}
          >
            {title}
          </text>
        ) : null}
        {slices.map((slice, index) => {
          const value = Math.max(0, Number(slice["value"]) || 0);
          const ratio = maxValue > 0 ? value / maxValue : 0;
          const firstRatio = firstValue > 0 ? value / firstValue : 0;
          const dimmed = selectedSlice !== null && selectedSlice !== index;
          const color =
            typeof slice["color"] === "string"
              ? slice["color"]
              : (chartPalette[index % chartPalette.length] ??
                DEFAULT_CHART_COLORS[0]!);
          return (
            <view
              key={`funnel-${String(slice["name"] ?? "")}-${index}`}
              style={{
                width: "100%",
                display: "flex",
                flexDirection: "row",
                alignItems: "center",
                gap: "8px",
                opacity: dimmed ? 0.4 : 1,
                animationDelay: `${index * 70}ms`,
              }}
              bindtap={() =>
                setSelectedSlice(selectedSlice === index ? null : index)
              }
            >
              <text
                style={{
                  width: "64px",
                  fontSize: "12px",
                  lineHeight: "16px",
                  color: theme.onSurfaceMuted,
                  flexShrink: 0,
                }}
              >
                {String(slice["name"] ?? "")}
              </text>
              <view
                className="a2ui-anim-grow-x"
                style={{
                  width: `${Math.max(8, ratio * 170)}px`,
                  height: "26px",
                  borderRadius: "4px",
                  backgroundColor: color,
                  display: "flex",
                  flexDirection: "row",
                  alignItems: "center",
                  justifyContent: "center",
                  animationDelay: `${index * 90}ms`,
                }}
              >
                {showValues ? (
                  <text
                    style={{
                      fontSize: "11px",
                      lineHeight: "14px",
                      fontWeight: "600",
                      color: theme.surface,
                    }}
                  >
                    {formatValue(value)}
                  </text>
                ) : null}
              </view>
              {index > 0 ? (
                <text
                  style={{
                    fontSize: "11px",
                    lineHeight: "16px",
                    color: theme.onSurfaceMuted,
                  }}
                >
                  {firstRatio > 0 ? `${formatPercent(firstRatio * 100)}` : ""}
                </text>
              ) : null}
            </view>
          );
        })}
      </view>
    );
  }

  // --- PieChart（饼/环图）：扇形段依赖 absolute + rotate，降级为「构成
  // 条 + 明细行」——一条按占比分色的横向构成条 + 可点选的逐扇形明细。 ---
  function PieChart(props: GenericComponentProps) {
    const [resolvedProps] = useResolvedProps(
      props,
      props.surface,
      props.dataContextPath,
    );
    const id = props.id;
    // 点选态：tap 构成条分段/明细行 → 该扇形保持高亮、其余淡化；再 tap 取消。
    const [selectedSlice, setSelectedSlice] = useState<number | null>(null);
    const dataValue = resolvedProps["data"];
    const slices = Array.isArray(dataValue)
      ? (dataValue as Array<Record<string, unknown>>)
      : [];
    const title =
      typeof resolvedProps["title"] === "string" && resolvedProps["title"]
        ? resolvedProps["title"]
        : "";
    const total = slices.reduce(
      (sum, slice) => sum + Math.max(0, Number(slice["value"]) || 0),
      0,
    );
    const subtitle =
      typeof resolvedProps["subtitle"] === "string" && resolvedProps["subtitle"]
        ? resolvedProps["subtitle"]
        : slices.length > 0
          ? `${slices.length} 项 • ${formatValue(total)} 合计`
          : "暂无数据";
    const showPercentages = resolvedProps["showPercentages"] !== false;
    const palette = Array.isArray(resolvedProps["colors"])
      ? (resolvedProps["colors"] as string[])
      : DEFAULT_CHART_COLORS;
    const activeSlices = slices
      .map((slice, sliceIndex) => ({
        sliceIndex,
        value: Math.max(0, Number(slice["value"]) || 0),
        name: String(slice["name"] ?? ""),
        color:
          typeof slice["color"] === "string"
            ? slice["color"]
            : (palette[sliceIndex % palette.length] ??
              DEFAULT_CHART_COLORS[0]!),
      }))
      .filter((item) => item.value > 0);
    return (
      <view
        key={id}
        style={{
          width: "100%",
          display: "flex",
          flexDirection: "column",
          gap: "12px",
          minWidth: 0,
        }}
      >
        <view
          style={{
            width: "100%",
            display: "flex",
            flexDirection: "column",
            gap: "2px",
          }}
        >
          <text
            style={{
              fontSize: "16px",
              lineHeight: "22px",
              fontWeight: "600",
              color: theme.onSurface,
            }}
          >
            {title}
          </text>
          <text
            style={{
              fontSize: "11px",
              lineHeight: "16px",
              color: theme.onSurfaceMuted,
            }}
          >
            {subtitle}
          </text>
        </view>
        {total > 0 ? (
          <view
            style={{
              width: "100%",
              height: "18px",
              display: "flex",
              flexDirection: "row",
              borderRadius: "9px",
              overflow: "hidden",
            }}
          >
            {activeSlices.map((item) => {
              const dimmed =
                selectedSlice !== null && selectedSlice !== item.sliceIndex;
              return (
                <view
                  key={`cseg-${item.sliceIndex}`}
                  className="a2ui-anim-fade"
                  style={{
                    flex: `${item.value} 1 0%`,
                    minWidth: "2px",
                    backgroundColor: item.color,
                    opacity: dimmed ? 0.35 : 1,
                    animationDelay: `${item.sliceIndex * 90}ms`,
                  }}
                  bindtap={() =>
                    setSelectedSlice(
                      selectedSlice === item.sliceIndex
                        ? null
                        : item.sliceIndex,
                    )
                  }
                />
              );
            })}
          </view>
        ) : null}
        {activeSlices
          .filter(
            (item) => selectedSlice === null || selectedSlice === item.sliceIndex,
          )
          .map((item) => {
            const pct = total > 0 ? (item.value / total) * 100 : 0;
            return (
              <view
                key={`crow-${item.sliceIndex}`}
                style={{
                  width: "100%",
                  display: "flex",
                  flexDirection: "row",
                  alignItems: "center",
                  gap: "8px",
                }}
                bindtap={() =>
                  setSelectedSlice(
                    selectedSlice === item.sliceIndex ? null : item.sliceIndex,
                  )
                }
              >
                <view
                  style={{
                    width: "10px",
                    height: "10px",
                    borderRadius: "5px",
                    backgroundColor: item.color,
                  }}
                />
                <text
                  style={{
                    flex: "1 1 0%",
                    fontSize: "13px",
                    lineHeight: "18px",
                    color: theme.onSurface,
                    minWidth: 0,
                  }}
                >
                  {item.name}
                </text>
                <text
                  style={{
                    fontSize: "12px",
                    lineHeight: "16px",
                    color: theme.onSurfaceMuted,
                  }}
                >
                  {`${formatValue(item.value)}${
                    showPercentages ? ` · ${formatPercent(pct)}` : ""
                  }`}
                </text>
              </view>
            );
          })}
      </view>
    );
  }

  // --- KPI 组件四件套：StatCard / RankList / ProgressRing / ComparisonRow。
  // 宿主自有扩展组件（官方 basic catalog 无），全部 view 绘制 + 主题注入。
  // 数据 prop 支持 path 绑定（渲染器解析）；颜色三级回滚与其他图表一致。 ---

  const asText = (v: unknown): string =>
    typeof v === "string" ? v : typeof v === "number" ? String(v) : "";

  function StatCard(props: GenericComponentProps) {
    const [resolvedProps] = useResolvedProps(
      props,
      props.surface,
      props.dataContextPath,
    );
    const id = props.id;
    const label = asText(resolvedProps["label"]);
    const value = asText(resolvedProps["value"]);
    const delta = asText(resolvedProps["delta"]);
    const trend = resolvedProps["trend"] === "down" ? "down" : "up";
    const caption = asText(resolvedProps["caption"]);
    const trendColor = trend === "down" ? "#d92d20" : theme.primary;
    return (
      <view
        key={id}
        style={{
          width: "100%",
          display: "flex",
          flexDirection: "column",
          gap: "4px",
          minWidth: 0,
        }}
      >
        {label ? (
          <text
            style={{
              fontSize: "12px",
              lineHeight: "16px",
              color: theme.onSurfaceMuted,
            }}
          >
            {label}
          </text>
        ) : null}
        <text
          style={{
            fontSize: "28px",
            lineHeight: "36px",
            fontWeight: "700",
            color: theme.onSurface,
          }}
        >
          {value}
        </text>
        {delta || caption ? (
          <view
            style={{
              display: "flex",
              flexDirection: "row",
              alignItems: "center",
              gap: "6px",
            }}
          >
            {delta ? (
              <text
                style={{
                  fontSize: "12px",
                  lineHeight: "16px",
                  fontWeight: "600",
                  color: trendColor,
                }}
              >
                {`${trend === "down" ? "▼" : "▲"} ${delta}`}
              </text>
            ) : null}
            {caption ? (
              <text
                style={{
                  fontSize: "12px",
                  lineHeight: "16px",
                  color: theme.onSurfaceMuted,
                }}
              >
                {caption}
              </text>
            ) : null}
          </view>
        ) : null}
      </view>
    );
  }

  function RankList(props: GenericComponentProps) {
    const [resolvedProps] = useResolvedProps(
      props,
      props.surface,
      props.dataContextPath,
    );
    const id = props.id;
    const itemsValue = resolvedProps["items"];
    const items = Array.isArray(itemsValue)
      ? (itemsValue as Array<Record<string, unknown>>)
      : [];
    const title =
      typeof resolvedProps["title"] === "string" && resolvedProps["title"]
        ? resolvedProps["title"]
        : "";
    const showRank = resolvedProps["showRank"] !== false;
    const maxValue = items.reduce(
      (acc, item) => Math.max(acc, Number(item["value"]) || 0),
      0,
    );
    // 名次徽章（Elements 口径收敛）：第 1 名品牌实底强调，2-3 名与 4+ 同为
    // muted 面弱化，不再使用金/银/铜硬编码色板。
    const rankBadge = (rank: number) => {
      if (rank === 1) {
        return { backgroundColor: theme.primary, color: theme.onPrimary };
      }
      return {
        backgroundColor: theme.surfaceMuted,
        color: theme.onSurfaceMuted,
      };
    };
    return (
      <view
        key={id}
        style={{
          width: "100%",
          display: "flex",
          flexDirection: "column",
          gap: "10px",
          minWidth: 0,
        }}
      >
        {title ? (
          <text
            style={{
              fontSize: "16px",
              lineHeight: "22px",
              fontWeight: "600",
              color: theme.onSurface,
            }}
          >
            {title}
          </text>
        ) : null}
        {items.map((item, index) => {
          const value = Number(item["value"]) || 0;
          const ratio = maxValue > 0 ? value / maxValue : 0;
          const label = asText(item["label"]) || formatValue(value);
          const badge = rankBadge(index + 1);
          return (
            <view
              key={`rank-${String(item["name"] ?? "")}-${index}`}
              style={{
                width: "100%",
                display: "flex",
                flexDirection: "column",
                gap: "4px",
              }}
            >
              <view
                style={{
                  width: "100%",
                  display: "flex",
                  flexDirection: "row",
                  alignItems: "center",
                  gap: "8px",
                }}
              >
                {showRank ? (
                  <view
                    style={{
                      width: "20px",
                      height: "20px",
                      borderRadius: "10px",
                      backgroundColor: badge.backgroundColor,
                      display: "flex",
                      alignItems: "center",
                      justifyContent: "center",
                      flexShrink: 0,
                    }}
                  >
                    <text
                      style={{
                        fontSize: "11px",
                        lineHeight: "14px",
                        fontWeight: "600",
                        color: badge.color,
                      }}
                    >
                      {String(index + 1)}
                    </text>
                  </view>
                ) : null}
                <text
                  style={{
                    fontSize: "13px",
                    lineHeight: "18px",
                    color: theme.onSurface,
                    flexShrink: 0,
                  }}
                >
                  {String(item["name"] ?? "")}
                </text>
                <view
                  style={{
                    flex: "1 1 0%",
                    height: "8px",
                    borderRadius: "4px",
                    backgroundColor: theme.surfaceMuted,
                    minWidth: 0,
                  }}
                >
                  <view
                    style={{
                      width: `${Math.min(100, ratio * 100)}%`,
                      height: "8px",
                      borderRadius: "4px",
                      backgroundColor:
                        typeof item["color"] === "string"
                          ? item["color"]
                          : theme.primary,
                    }}
                  />
                </view>
                <text
                  style={{
                    fontSize: "12px",
                    lineHeight: "16px",
                    color: theme.onSurfaceMuted,
                    flexShrink: 0,
                  }}
                >
                  {label}
                </text>
              </view>
            </view>
          );
        })}
      </view>
    );
  }

  // --- ProgressRing（进度环）：环弧依赖 absolute + rotate，降级为「数值
  // + 横向进度条」；height 语义由环直径调整为条长（120–240 夹取不变）。 ---
  function ProgressRing(props: GenericComponentProps) {
    const [resolvedProps] = useResolvedProps(
      props,
      props.surface,
      props.dataContextPath,
    );
    const id = props.id;
    const valueValue = resolvedProps["value"];
    const percent = Math.max(0, Math.min(100, Number(valueValue) || 0));
    const label = asText(resolvedProps["label"]);
    const caption = asText(resolvedProps["caption"]);
    const color =
      typeof resolvedProps["color"] === "string" && resolvedProps["color"]
        ? resolvedProps["color"]
        : theme.primary;
    const heightValue = resolvedProps["height"];
    const barLength = Math.max(
      120,
      Math.min(typeof heightValue === "number" ? heightValue : 180, 240),
    );
    return (
      <view
        key={id}
        style={{
          width: "100%",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          gap: "8px",
        }}
      >
        <text
          style={{
            fontSize: "26px",
            lineHeight: "32px",
            fontWeight: "700",
            color: theme.onSurface,
          }}
        >
          {`${percent}%`}
        </text>
        {label ? (
          <text
            style={{
              fontSize: "12px",
              lineHeight: "16px",
              color: theme.onSurfaceMuted,
            }}
          >
            {label}
          </text>
        ) : null}
        <view
          style={{
            width: `${barLength}px`,
            height: "14px",
            display: "flex",
            flexDirection: "row",
            borderRadius: "999px",
            backgroundColor: theme.surfaceMuted,
            overflow: "hidden",
          }}
        >
          <view
            className="a2ui-anim-fade"
            style={{
              height: "100%",
              width: `${percent}%`,
              borderRadius: "999px",
              backgroundColor: color,
            }}
          />
        </view>
        {caption ? (
          <text
            style={{
              fontSize: "12px",
              lineHeight: "16px",
              color: theme.onSurfaceMuted,
            }}
          >
            {caption}
          </text>
        ) : null}
      </view>
    );
  }

  function ComparisonRow(props: GenericComponentProps) {
    const [resolvedProps] = useResolvedProps(
      props,
      props.surface,
      props.dataContextPath,
    );
    const id = props.id;
    const label = asText(resolvedProps["label"]);
    const currentValue = Number(resolvedProps["current"]) || 0;
    const previousValue = Number(resolvedProps["previous"]) || 0;
    const currentLabel = asText(resolvedProps["currentLabel"]) || "本期";
    const previousLabel = asText(resolvedProps["previousLabel"]) || "上期";
    const unit = asText(resolvedProps["unit"]);
    const maxValue = Math.max(currentValue, previousValue, 1);
    const diff = currentValue - previousValue;
    const diffPct =
      previousValue > 0 ? Math.round((diff / previousValue) * 100) : null;
    const diffColor = diff >= 0 ? theme.primary : "#d92d20";
    const diffText =
      diffPct === null ? "" : `${diff >= 0 ? "▲ +" : "▼ "}${diffPct}%`;
    const row = (
      rowLabel: string,
      value: number,
      barColor: string,
      valueColor: string,
    ) => (
      <view
        style={{
          width: "100%",
          display: "flex",
          flexDirection: "row",
          alignItems: "center",
          gap: "8px",
        }}
      >
        <text
          style={{
            width: "32px",
            fontSize: "12px",
            lineHeight: "16px",
            color: theme.onSurfaceMuted,
            flexShrink: 0,
          }}
        >
          {rowLabel}
        </text>
        <view
          style={{
            flex: "1 1 0%",
            height: "12px",
            borderRadius: "6px",
            backgroundColor: theme.surfaceMuted,
            minWidth: 0,
          }}
        >
          <view
            style={{
              width: `${(value / maxValue) * 100}%`,
              height: "12px",
              borderRadius: "6px",
              backgroundColor: barColor,
            }}
          />
        </view>
        <text
          style={{
            fontSize: "13px",
            lineHeight: "18px",
            fontWeight: "600",
            color: valueColor,
            flexShrink: 0,
          }}
        >
          {`${formatValue(value)}${unit}`}
        </text>
      </view>
    );
    return (
      <view
        key={id}
        style={{
          width: "100%",
          display: "flex",
          flexDirection: "column",
          gap: "8px",
          minWidth: 0,
        }}
      >
        {label ? (
          <view
            style={{
              width: "100%",
              display: "flex",
              flexDirection: "row",
              justifyContent: "space-between",
              alignItems: "center",
            }}
          >
            <text
              style={{
                fontSize: "15px",
                lineHeight: "20px",
                fontWeight: "600",
                color: theme.onSurface,
              }}
            >
              {label}
            </text>
            {diffText ? (
              <text
                style={{
                  fontSize: "12px",
                  lineHeight: "16px",
                  fontWeight: "600",
                  color: diffColor,
                }}
              >
                {`较${previousLabel} ${diffText}`}
              </text>
            ) : null}
          </view>
        ) : null}
        {row(currentLabel, currentValue, theme.primary, theme.onSurface)}
        {row(
          previousLabel,
          previousValue,
          theme.onSurfaceMuted,
          theme.onSurfaceMuted,
        )}
      </view>
    );
  }

  // --- Timeline / BadgeGroup / Accordion：B 组流程与状态类组件，宿主自有
  // 扩展（官方 basic catalog 无），全部 view 绘制 + 主题注入。 ---

  function Timeline(props: GenericComponentProps) {
    const [resolvedProps] = useResolvedProps(
      props,
      props.surface,
      props.dataContextPath,
    );
    const id = props.id;
    const stepsValue = resolvedProps["steps"];
    const steps = Array.isArray(stepsValue)
      ? (stepsValue as Array<Record<string, unknown>>)
      : [];
    const title =
      typeof resolvedProps["title"] === "string" && resolvedProps["title"]
        ? resolvedProps["title"]
        : "";
    return (
      <view
        key={id}
        style={{
          width: "100%",
          display: "flex",
          flexDirection: "column",
          gap: "8px",
          minWidth: 0,
        }}
      >
        {title ? (
          <text
            style={{
              fontSize: "16px",
              lineHeight: "22px",
              fontWeight: "600",
              color: theme.onSurface,
            }}
          >
            {title}
          </text>
        ) : null}
        {steps.map((step, index) => {
          const last = index === steps.length - 1;
          // status：done（实心点+实线）/ current（空心环+实线）/ pending（灰点+虚位）
          const status =
            typeof step["status"] === "string"
              ? step["status"]
              : last
                ? "current"
                : "done";
          const dotColor =
            status === "pending" ? theme.surfaceMuted : theme.primary;
          return (
            <view
              key={`tl-${index}`}
              className="a2ui-anim-rise"
              style={{
                width: "100%",
                display: "flex",
                flexDirection: "row",
                gap: "10px",
                animationDelay: `${index * 70}ms`,
              }}
            >
              <view
                style={{
                  width: "16px",
                  display: "flex",
                  flexDirection: "column",
                  alignItems: "center",
                  flexShrink: 0,
                }}
              >
                <view
                  style={{
                    width: status === "current" ? "12px" : "10px",
                    height: status === "current" ? "12px" : "10px",
                    marginTop: "3px",
                    borderRadius: "50%",
                    backgroundColor:
                      status === "current"
                        ? theme.surface
                        : dotColor,
                    border:
                      status === "current"
                        ? `3px solid ${theme.primary}`
                        : `2px solid ${status === "pending" ? theme.border : theme.primary}`,
                  }}
                />
                {!last ? (
                  <view
                    style={{
                      width: "2px",
                      flex: "1 1 0%",
                      minHeight: "14px",
                      backgroundColor:
                        status === "pending" ? theme.border : theme.primary,
                    }}
                  />
                ) : null}
              </view>
              <view
                style={{
                  flex: "1 1 0%",
                  paddingBottom: "12px",
                  minWidth: 0,
                }}
              >
                <text
                  style={{
                    fontSize: "14px",
                    lineHeight: "20px",
                    fontWeight: "600",
                    color:
                      status === "pending"
                        ? theme.onSurfaceMuted
                        : theme.onSurface,
                  }}
                >
                  {String(step["title"] ?? "")}
                </text>
                {typeof step["desc"] === "string" && step["desc"] ? (
                  <text
                    style={{
                      fontSize: "12px",
                      lineHeight: "17px",
                      color: theme.onSurfaceMuted,
                    }}
                  >
                    {step["desc"]}
                  </text>
                ) : null}
                {typeof step["time"] === "string" && step["time"] ? (
                  <text
                    style={{
                      fontSize: "11px",
                      lineHeight: "16px",
                      color: theme.onSurfaceMuted,
                    }}
                  >
                    {step["time"]}
                  </text>
                ) : null}
              </view>
            </view>
          );
        })}
      </view>
    );
  }

  function BadgeGroup(props: GenericComponentProps) {
    const [resolvedProps] = useResolvedProps(
      props,
      props.surface,
      props.dataContextPath,
    );
    const id = props.id;
    const itemsValue = resolvedProps["items"];
    const items = Array.isArray(itemsValue)
      ? (itemsValue as Array<Record<string, unknown>>)
      : [];
    // 语义色调 → 主题映射；以 # 开头的原始色值也接受（宿主可信通道）。
    // Elements/zinc muted 徽章口径：语义色只出 ~14% 浅面 + 向正文色混色的
    // 文字，明暗两版都由 surface/onSurface 推导（亮色压深、暗色提亮），
    // 不引入第二套硬编码色板；primary 保持实底（品牌强调），# 原色透传不变。
    const toneStyle = (tone: string): { bg: string; text: string } => {
      switch (tone) {
        case "primary":
          return { bg: theme.primary, text: theme.onPrimary };
        case "success":
        case "warning":
        case "danger":
          return {
            bg: mixHex(SEMANTIC_TONE[tone], theme.surface, 0.86),
            text: mixHex(SEMANTIC_TONE[tone], theme.onSurface, 0.35),
          };
        case "neutral":
          return { bg: theme.surfaceMuted, text: theme.onSurfaceMuted };
        default:
          if (tone.startsWith("#")) return { bg: tone, text: theme.onPrimary };
          return { bg: theme.surfaceMuted, text: theme.onSurfaceMuted };
      }
    };
    return (
      <view
        key={id}
        style={{
          width: "100%",
          display: "flex",
          flexDirection: "row",
          flexWrap: "wrap",
          gap: "8px",
          minWidth: 0,
        }}
      >
        {items.map((item, index) => {
          const tone =
            typeof item["tone"] === "string" ? item["tone"] : "neutral";
          const style = toneStyle(tone);
          return (
            <view
              key={`badge-${index}-${String(item["text"] ?? "")}`}
              className="a2ui-anim-pop"
              style={{
                paddingLeft: "10px",
                paddingRight: "10px",
                paddingTop: "5px",
                paddingBottom: "5px",
                borderRadius: "999px",
                backgroundColor: style.bg,
                animationDelay: `${index * 50}ms`,
              }}
            >
              <text
                style={{
                  fontSize: "12px",
                  lineHeight: "16px",
                  fontWeight: "500",
                  color: style.text,
                }}
              >
                {String(item["text"] ?? "")}
              </text>
            </view>
          );
        })}
      </view>
    );
  }

  function Accordion(props: GenericComponentProps) {
    const [resolvedProps] = useResolvedProps(
      props,
      props.surface,
      props.dataContextPath,
    );
    const id = props.id;
    const panelsValue = resolvedProps["panels"];
    const panels = Array.isArray(panelsValue)
      ? (panelsValue as Array<Record<string, unknown>>)
      : [];
    const defaultOpenRaw = resolvedProps["defaultOpen"];
    const [openIndex, setOpenIndex] = useState<number | null>(
      typeof defaultOpenRaw === "number" ? defaultOpenRaw : null,
    );
    return (
      <view
        key={id}
        style={{
          width: "100%",
          display: "flex",
          flexDirection: "column",
          minWidth: 0,
        }}
      >
        {panels.map((panel, index) => {
          const open = openIndex === index;
          return (
            <view
              key={`acc-${index}`}
              style={{
                width: "100%",
                display: "flex",
                flexDirection: "column",
                borderBottom: `1px solid ${theme.divider}`,
              }}
            >
              <view
                style={{
                  width: "100%",
                  display: "flex",
                  flexDirection: "row",
                  justifyContent: "space-between",
                  alignItems: "center",
                  paddingTop: "10px",
                  paddingBottom: "10px",
                }}
                bindtap={() =>
                  setOpenIndex(open ? null : index)
                }
              >
                <text
                  style={{
                    fontSize: "14px",
                    lineHeight: "20px",
                    fontWeight: "600",
                    color: theme.onSurface,
                  }}
                >
                  {String(panel["title"] ?? "")}
                </text>
                <text
                  style={{
                    fontSize: "12px",
                    color: theme.onSurfaceMuted,
                    transform: `rotate(${open ? 0 : -90}deg)`,
                  }}
                >
                  {"▾"}
                </text>
              </view>
              {open ? (
                <view
                  className="a2ui-anim-fade"
                  style={{ paddingBottom: "10px" }}
                >
                  <text
                    style={{
                      fontSize: "13px",
                      lineHeight: "20px",
                      color: theme.onSurfaceMuted,
                    }}
                  >
                    {String(panel["content"] ?? "")}
                  </text>
                </view>
              ) : null}
            </view>
          );
        })}
      </view>
    );
  }

  // --- C 组：AreaChart / StackedBar / DataTable / Gauge / CountUp。
  // 宿主自有扩展组件，全部 view 绘制 + 主题注入 + 颜色三级回滚。 ---

  // --- AreaChart（面积图）：面积填充依赖 absolute 覆盖，降级与折线图同
  // 构的棒棒糖列（数据点 + 茎），面积观感不再保留。 ---
  function AreaChart(props: GenericComponentProps) {
    const [resolvedProps] = useResolvedProps(
      props,
      props.surface,
      props.dataContextPath,
    );
    const id = props.id;
    const labelsValue = resolvedProps["labels"];
    const labels = Array.isArray(labelsValue) ? labelsValue : [];
    const seriesValue = resolvedProps["series"];
    const chartPalette = Array.isArray(resolvedProps["colors"])
      ? (resolvedProps["colors"] as string[])
      : DEFAULT_CHART_COLORS;
    const series = Array.isArray(seriesValue)
      ? normalizeSeries(seriesValue, chartPalette)
      : [];
    const showLegend = resolvedProps["showLegend"] !== false;
    const heightValue = resolvedProps["height"];
    const height = typeof heightValue === "number" ? heightValue : 200;
    const chartTitle =
      typeof resolvedProps["yLabel"] === "string"
        ? resolvedProps["yLabel"]
        : "";
    const plotH = Math.max(60, height - 40);
    const maxPoints = labels.length;
    const allValues = series.flatMap((item) => item.values.slice(0, maxPoints));
    const { min: plotMin, max: plotMax } = minMax(allValues);
    const plotRange = plotMax - plotMin;
    const pointColumns = labels.slice(0, maxPoints).map((_, index) => (
      <view
        key={`acol-${index}`}
        style={{
          flex: "1 1 0%",
          height: `${plotH}px`,
          display: "flex",
          flexDirection: "row",
          alignItems: "flex-end",
          justifyContent: "center",
          gap: "3px",
          minWidth: 0,
        }}
      >
        {series.map((item, seriesIndex) => {
          const value = Number(item.values[index]) || 0;
          const ratio = plotRange === 0 ? 0.5 : (value - plotMin) / plotRange;
          const stemH = Math.max(2, ratio * (plotH - 16));
          return (
            <view
              key={`apop-${seriesIndex}-${index}`}
              className="a2ui-anim-fade"
              style={{
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                animationDelay: `${index * 60 + seriesIndex * 30}ms`,
              }}
            >
              <view
                style={{
                  width: "6px",
                  height: "6px",
                  borderRadius: "3px",
                  backgroundColor: item.color,
                }}
              />
              <view
                style={{
                  width: "2.5px",
                  height: `${stemH}px`,
                  backgroundColor: item.color,
                  opacity: 0.4,
                }}
              />
            </view>
          );
        })}
      </view>
    ));
    const { min, max } = minMax(
      series.flatMap((item) => item.values.slice(0, labels.length)),
    );
    const visibleLabelIndices = sampleIndices(labels.length, 8);
    return (
      <view
        key={id}
        style={{
          width: "100%",
          display: "flex",
          flexDirection: "column",
          gap: "8px",
          minWidth: 0,
        }}
      >
        {chartTitle ? (
          <text
            style={{
              fontSize: "16px",
              lineHeight: "22px",
              fontWeight: "600",
              color: theme.onSurface,
            }}
          >
            {chartTitle}
          </text>
        ) : null}
        <view
          style={{
            display: "flex",
            flexDirection: "row",
            justifyContent: "space-between",
            width: "100%",
          }}
        >
          <text
            style={{
              fontSize: "11px",
              lineHeight: "16px",
              color: theme.onSurfaceMuted,
            }}
          >
            {formatValue(min)}
          </text>
          <text
            style={{
              fontSize: "11px",
              lineHeight: "16px",
              color: theme.onSurfaceMuted,
            }}
          >
            {formatValue(max)}
          </text>
        </view>
        <view
          style={{
            width: "300px",
            display: "flex",
            flexDirection: "row",
            alignItems: "flex-end",
            alignSelf: "center",
          }}
        >
          {pointColumns}
        </view>
        {chartBaseline()}
        <view
          style={{
            display: "flex",
            flexDirection: "row",
            justifyContent: "space-between",
            width: "100%",
          }}
        >
          {visibleLabelIndices.map((index) => (
            <text
              key={`${index}-${labels[index] ?? index}`}
              style={{
                fontSize: "11px",
                lineHeight: "16px",
                color: theme.onSurfaceMuted,
              }}
            >
              {labels[index] ?? ""}
            </text>
          ))}
        </view>
        {showLegend ? chartLegend(series) : null}
      </view>
    );
  }

  // --- StackedBar（堆叠柱）：组内各系列自下而上累加；纯流内用「倒序系列
  // + 底对齐列」表达堆叠，网格线降级去掉，点选组出读出条。 ---
  function StackedBar(props: GenericComponentProps) {
    const [resolvedProps] = useResolvedProps(
      props,
      props.surface,
      props.dataContextPath,
    );
    const id = props.id;
    const [selectedGroup, setSelectedGroup] = useState<number | null>(null);
    const labelsValue = resolvedProps["labels"];
    const labels = Array.isArray(labelsValue) ? labelsValue : [];
    const seriesValue = resolvedProps["series"];
    const chartPalette = Array.isArray(resolvedProps["colors"])
      ? (resolvedProps["colors"] as string[])
      : DEFAULT_CHART_COLORS;
    const series = Array.isArray(seriesValue)
      ? normalizeSeries(seriesValue, chartPalette)
      : [];
    const showLegend = resolvedProps["showLegend"] !== false;
    const heightValue = resolvedProps["height"];
    const height = typeof heightValue === "number" ? heightValue : 200;
    const chartTitle =
      typeof resolvedProps["yLabel"] === "string"
        ? resolvedProps["yLabel"]
        : "";
    const canvasW = 300;
    const plotW = canvasW - 24;
    const plotH = Math.max(60, height - 24);
    const groupCount = labels.length;
    const groupW = groupCount > 0 ? plotW / groupCount : 0;
    const barW = Math.max(8, Math.min(36, groupW - 12));
    // 堆叠：每组各系列自下而上累加，总量基准 = 组内合计的最大值。
    const groupTotals = labels.map((_, g) =>
      series.reduce(
        (sum, item) => sum + Math.max(0, Number(item.values[g]) || 0),
        0,
      ),
    );
    const scaleMax = Math.max(1, ...groupTotals);
    // 倒序渲染：column 自上而下 = 系列自上而下，flex-end 底对齐后首个系列
    // 恰好贴基线，与「自下而上累加」语义一致。
    const reversedSeries = series.slice().reverse();
    const groupColumns = labels.slice(0, groupCount).map((_, groupIndex) => {
      const dimmed = selectedGroup !== null && selectedGroup !== groupIndex;
      return (
        <view
          key={`sbgrp-${groupIndex}`}
          style={{
            flex: "1 1 0%",
            height: `${plotH}px`,
            display: "flex",
            flexDirection: "column",
            justifyContent: "flex-end",
            alignItems: "center",
            minWidth: 0,
            opacity: dimmed ? 0.35 : 1,
          }}
          bindtap={() =>
            setSelectedGroup(selectedGroup === groupIndex ? null : groupIndex)
          }
        >
          {reversedSeries.map((item, reverseIndex) => {
            const v = Math.max(0, Number(item.values[groupIndex]) || 0);
            const segH = (v / scaleMax) * (plotH - 8);
            if (segH <= 0) return null;
            return (
              <view
                key={`sbseg-${reverseIndex}-${groupIndex}`}
                style={{
                  width: `${barW}px`,
                  height: `${segH}px`,
                  backgroundColor: item.color,
                }}
              />
            );
          })}
        </view>
      );
    });
    const selectedLabel =
      selectedGroup === null ? "" : String(labels[selectedGroup] ?? "");
    const selectedValues =
      selectedGroup === null
        ? []
        : series.map((item) => ({
            name: item.name,
            value: item.values[selectedGroup] ?? 0,
          }));
    return (
      <view
        key={id}
        style={{
          width: "100%",
          display: "flex",
          flexDirection: "column",
          gap: "8px",
          minWidth: 0,
        }}
      >
        {chartTitle ? (
          <text
            style={{
              fontSize: "16px",
              lineHeight: "22px",
              fontWeight: "600",
              color: theme.onSurface,
            }}
          >
            {chartTitle}
          </text>
        ) : null}
        <view
          style={{
            width: "300px",
            display: "flex",
            flexDirection: "row",
            alignItems: "flex-end",
            alignSelf: "center",
          }}
        >
          {groupColumns}
        </view>
        {chartBaseline()}
        {chartReadout(selectedLabel, selectedValues)}
        <view
          style={{
            width: "300px",
            display: "flex",
            flexDirection: "row",
            alignSelf: "center",
          }}
        >
          {labels.slice(0, groupCount).map((label, index) => (
            <text
              key={`${index}-${label ?? index}`}
              style={{
                flex: "1 1 0%",
                textAlign: "center",
                fontSize: "11px",
                lineHeight: "16px",
                color:
                  selectedGroup === index
                    ? theme.onSurface
                    : theme.onSurfaceMuted,
              }}
            >
              {label ?? ""}
            </text>
          ))}
        </view>
        {showLegend ? chartLegend(series) : null}
      </view>
    );
  }

  function DataTable(props: GenericComponentProps) {
    const [resolvedProps] = useResolvedProps(
      props,
      props.surface,
      props.dataContextPath,
    );
    const id = props.id;
    const [selectedRow, setSelectedRow] = useState<number | null>(null);
    const headersValue = resolvedProps["headers"];
    const headers = Array.isArray(headersValue)
      ? (headersValue as string[])
      : [];
    const rowsValue = resolvedProps["rows"];
    const rows = Array.isArray(rowsValue)
      ? (rowsValue as string[][])
      : [];
    const title =
      typeof resolvedProps["title"] === "string" && resolvedProps["title"]
        ? resolvedProps["title"]
        : "";
    const cell = (text: string, last: boolean, head: boolean) => (
      <text
        style={{
          flex: "1 1 0%",
          fontSize: head ? "12px" : "13px",
          lineHeight: head ? "16px" : "18px",
          fontWeight: head ? "600" : "400",
          textAlign: last ? "right" : "left",
          color: head ? theme.onSurfaceMuted : theme.onSurface,
        }}
      >
        {text}
      </text>
    );
    return (
      <view
        key={id}
        style={{
          width: "100%",
          display: "flex",
          flexDirection: "column",
          minWidth: 0,
        }}
      >
        {title ? (
          <text
            style={{
              fontSize: "15px",
              lineHeight: "20px",
              fontWeight: "600",
              marginBottom: "8px",
              color: theme.onSurface,
            }}
          >
            {title}
          </text>
        ) : null}
        <view
          style={{
            width: "100%",
            display: "flex",
            flexDirection: "row",
            gap: "10px",
            paddingBottom: "6px",
            borderBottom: `1.5px solid ${theme.onSurfaceMuted}`,
          }}
        >
          {headers.map((h, i) => cell(String(h), i === headers.length - 1, true))}
        </view>
        {rows.map((row, r) => (
          <view
            key={`drow-${r}`}
            style={{
              width: "100%",
              display: "flex",
              flexDirection: "row",
              gap: "10px",
              paddingTop: "8px",
              paddingBottom: "8px",
              borderBottom: `1px solid ${theme.divider}`,
              opacity: selectedRow === null || selectedRow === r ? 1 : 0.45,
            }}
            bindtap={() => setSelectedRow(selectedRow === r ? null : r)}
          >
            {row.map((cellText, c) => cell(String(cellText), c === row.length - 1, false))}
          </view>
        ))}
      </view>
    );
  }

  // --- Gauge（仪表盘）：半圆弧 + 数值覆盖依赖 absolute + rotate，降级为
  // 「数值 + 横向仪表条 + 0/100 刻度」。 ---
  function Gauge(props: GenericComponentProps) {
    const [resolvedProps] = useResolvedProps(
      props,
      props.surface,
      props.dataContextPath,
    );
    const id = props.id;
    const valueValue = resolvedProps["value"];
    const percent = Math.max(0, Math.min(100, Number(valueValue) || 0));
    const label = asText(resolvedProps["label"]);
    const color =
      typeof resolvedProps["color"] === "string" && resolvedProps["color"]
        ? resolvedProps["color"]
        : theme.primary;
    return (
      <view
        key={id}
        style={{
          width: "100%",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          gap: "4px",
        }}
      >
        <text
          style={{
            fontSize: "26px",
            lineHeight: "32px",
            fontWeight: "700",
            color: theme.onSurface,
          }}
        >
          {`${percent}%`}
        </text>
        {label ? (
          <text
            style={{
              fontSize: "11px",
              lineHeight: "16px",
              color: theme.onSurfaceMuted,
            }}
          >
            {label}
          </text>
        ) : null}
        <view
          style={{
            width: "240px",
            height: "14px",
            display: "flex",
            flexDirection: "row",
            borderRadius: "999px",
            backgroundColor: theme.surfaceMuted,
            overflow: "hidden",
            marginTop: "4px",
          }}
        >
          <view
            className="a2ui-anim-fade"
            style={{
              height: "100%",
              width: `${percent}%`,
              backgroundColor: color,
            }}
          />
        </view>
        <view
          style={{
            width: "240px",
            display: "flex",
            flexDirection: "row",
            justifyContent: "space-between",
          }}
        >
          <text
            style={{
              fontSize: "10px",
              lineHeight: "14px",
              color: theme.onSurfaceMuted,
            }}
          >
            0
          </text>
          <text
            style={{
              fontSize: "10px",
              lineHeight: "14px",
              color: theme.onSurfaceMuted,
            }}
          >
            100
          </text>
        </view>
      </view>
    );
  }

  function CountUp(props: GenericComponentProps) {
    const [resolvedProps] = useResolvedProps(
      props,
      props.surface,
      props.dataContextPath,
    );
    const id = props.id;
    const target = Number(resolvedProps["value"]) || 0;
    const label = asText(resolvedProps["label"]);
    const prefix = asText(resolvedProps["prefix"]);
    const suffix = asText(resolvedProps["suffix"]);
    const duration = 900;
    const [display, setDisplay] = useState(0);
    useEffect(() => {
      const startedAt = Date.now();
      let timer: ReturnType<typeof setTimeout> | undefined;
      const tick = () => {
        const t = Math.min(1, (Date.now() - startedAt) / duration);
        const eased = 1 - Math.pow(1 - t, 3);
        setDisplay(Math.round(target * eased));
        if (t < 1) {
          timer = setTimeout(tick, 30);
        }
      };
      timer = setTimeout(tick, 30);
      return () => timer !== undefined && clearTimeout(timer);
    }, [target]);
    return (
      <view
        key={id}
        style={{
          width: "100%",
          display: "flex",
          flexDirection: "column",
          gap: "2px",
        }}
      >
        {label ? (
          <text
            style={{
              fontSize: "12px",
              lineHeight: "16px",
              color: theme.onSurfaceMuted,
            }}
          >
            {label}
          </text>
        ) : null}
        <text
          style={{
            fontSize: "28px",
            lineHeight: "36px",
            fontWeight: "700",
            color: theme.onSurface,
          }}
        >
          {`${prefix}${formatValue(display)}${suffix}`}
        </text>
      </view>
    );
  }

  // 官方 Button 用内部导出的 A2UIRenderer 渲染子组件资源（该导出不对包外
  // 开放）。这里用公开 API 逐行为复刻：useSyncExternalStore 订阅资源快照，
  // pending 显示骨架（官方默认兜底）、error 显示文本、surfaceUpdate 交给
  // NodeRenderer。资源只承载同 surface 内的子组件（按钮 label），不涉及
  // beginRendering 建面路径。
  function ResourceChild(props: {
    resource: Resource<ResourceInfo>;
    surface: Surface;
  }) {
    const { resource, surface } = props;
    const snapshot = useSyncExternalStore(
      resource.subscribe,
      resource.getSnapshot,
      resource.getSnapshot,
    );
    const data = snapshot.value as
      | { type?: string; component?: ComponentInstance; surface?: Surface }
      | undefined;
    if (snapshot.status === "pending" && data === undefined) {
      return Loading({ variant: "block" });
    }
    if (snapshot.status === "error") {
      return (
        <text style={{ color: theme.onSurfaceMuted, fontSize: "12px" }}>
          {`Error: ${String(snapshot.error)}`}
        </text>
      );
    }
    if (!data) return null;
    if (data.type === "surfaceUpdate" && data.component) {
      return (
        <NodeRenderer
          component={data.component}
          surface={data.surface ?? surface}
        />
      );
    }
    return null;
  }

  return {
    Text,
    Row,
    Column,
    Card,
    Divider,
    Button,
    Icon,
    Image,
    List,
    Loading,
    Tabs,
    LineChart,
    PieChart,
    BarChart,
    ScatterChart,
    RadarChart,
    FunnelChart,
    StatCard,
    RankList,
    ProgressRing,
    ComparisonRow,
    Timeline,
    BadgeGroup,
    Accordion,
    AreaChart,
    StackedBar,
    DataTable,
    Gauge,
    CountUp,
  };
}
