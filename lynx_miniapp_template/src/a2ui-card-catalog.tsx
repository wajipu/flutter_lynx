import {
  createContext,
  useContext,
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
  function Text(props: StyledTextProps) {
    const variant = props.variant ?? "body";
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
          gap: "12px",
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
          border: `1px solid ${theme.border}`,
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
      opacity: enabled ? 1 : 0.4,
    };
    if (variant === "primary") {
      shellStyle.backgroundColor = theme.primary;
    } else {
      shellStyle.backgroundColor = "transparent";
    }
    return (
      <>
        <ButtonLabelContext.Provider value={{ variant, theme }}>
          <view style={shellStyle} bindtap={enabled ? handleClick : undefined}>
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
        <view style={{ ...skeletonStyle, width: "96%" }} />
        {variant === "block" ? (
          <view style={{ ...skeletonStyle, width: "68%" }} />
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
  function escapeXml(value: string): string {
    return value
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&apos;");
  }
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

  function buildLinearPath(points: Array<{ x: number; y: number }>): string {
    if (points.length === 0) return "";
    const first = points[0]!;
    const rest = points.slice(1);
    let path = `M ${first.x.toFixed(1)} ${first.y.toFixed(1)}`;
    for (const point of rest) {
      path += ` L ${point.x.toFixed(1)} ${point.y.toFixed(1)}`;
    }
    return path;
  }

  function buildStepPath(points: Array<{ x: number; y: number }>): string {
    if (points.length === 0) return "";
    const first = points[0]!;
    const rest = points.slice(1);
    let path = `M ${first.x.toFixed(1)} ${first.y.toFixed(1)}`;
    let prev = first;
    for (const point of rest) {
      path += ` L ${point.x.toFixed(1)} ${prev.y.toFixed(1)}`;
      path += ` L ${point.x.toFixed(1)} ${point.y.toFixed(1)}`;
      prev = point;
    }
    return path;
  }

  function buildNaturalPath(points: Array<{ x: number; y: number }>): string {
    if (points.length === 0) return "";
    if (points.length === 1) {
      const point = points[0]!;
      return `M ${point.x.toFixed(1)} ${point.y.toFixed(1)}`;
    }
    let path = `M ${points[0]!.x.toFixed(1)} ${points[0]!.y.toFixed(1)}`;
    for (let index = 0; index < points.length - 1; index += 1) {
      const p0 = points[index - 1] ?? points[index]!;
      const p1 = points[index]!;
      const p2 = points[index + 1]!;
      const p3 = points[index + 2] ?? p2;
      const cp1x = p1.x + (p2.x - p0.x) / 6;
      const cp1y = p1.y + (p2.y - p0.y) / 6;
      const cp2x = p2.x - (p3.x - p1.x) / 6;
      const cp2y = p2.y - (p3.y - p1.y) / 6;
      path += ` C ${cp1x.toFixed(1)} ${cp1y.toFixed(1)}, ${cp2x.toFixed(1)} ${cp2y.toFixed(1)}, ${p2.x.toFixed(1)} ${p2.y.toFixed(1)}`;
    }
    return path;
  }

  function buildPath(
    points: Array<{ x: number; y: number }>,
    variant: string,
  ): string {
    switch (variant) {
      case "step":
        return buildStepPath(points);
      case "natural":
        return buildNaturalPath(points);
      default:
        return buildLinearPath(points);
    }
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

  function LineChart(props: GenericComponentProps) {
    const [resolvedProps] = useResolvedProps(
      props,
      props.surface,
      props.dataContextPath,
    );
    const id = props.id;
    // 点选态：tap 某列热区 → 参考线 + 数据点放大 + 数值气泡；再 tap 取消。
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
    const variant =
      typeof resolvedProps["variant"] === "string"
        ? resolvedProps["variant"]
        : "natural";
    const showGrid = resolvedProps["showGrid"] !== false;
    const showLegend = resolvedProps["showLegend"] !== false;
    const heightValue = resolvedProps["height"];
    const height =
      typeof heightValue === "number" ? heightValue : LINE_DEFAULT_HEIGHT;
    // view 画布几何：与官方 SVG 版同一套数学，画布固定 300px 设计宽
    // （卡内内容宽约 334px，居中绘制）。本引擎不支持 SVG（image data URI 与
    // <svg> 元素实测均空白），线段用「中心点定位 + 旋转」的绝对定位 view 绘制。
    const canvasW = 300;
    const canvasMargin = { top: 8, right: 12, bottom: 8, left: 12 };
    const plotW = canvasW - canvasMargin.left - canvasMargin.right;
    const plotH = height - canvasMargin.top - canvasMargin.bottom;
    const maxPoints = labels.length;
    const allValues = series.flatMap((item) => item.values.slice(0, maxPoints));
    const { min: plotMin, max: plotMax } = minMax(allValues);
    const plotRange = plotMax - plotMin;
    const xStep = maxPoints > 1 ? plotW / (maxPoints - 1) : 0;
    const seriesPoints = series.map((item) =>
      item.values.slice(0, maxPoints).map((value, index) => ({
        x: canvasMargin.left + xStep * index,
        y:
          canvasMargin.top +
          plotH -
          (plotRange === 0 ? 0.5 : (value - plotMin) / plotRange) * plotH,
        color: item.color,
      })),
    );
    const gridLines = 4;
    const chartGrid = showGrid
      ? Array.from({ length: gridLines + 1 }, (_, index) => {
          const ratio = index / gridLines;
          return (
            <view
              key={`grid-${index}`}
              style={{
                position: "absolute",
                left: `${canvasMargin.left}px`,
                top: `${canvasMargin.top + plotH - ratio * plotH}px`,
                width: `${plotW}px`,
                height: "1px",
                backgroundColor: theme.border,
              }}
            />
          );
        })
      : null;
    const chartBaseline = (
      <view
        style={{
          position: "absolute",
          left: `${canvasMargin.left}px`,
          top: `${canvasMargin.top + plotH}px`,
          width: `${plotW}px`,
          height: "1.5px",
          backgroundColor: theme.onSurfaceMuted,
        }}
      />
    );
    const chartSegments = seriesPoints.map((points, seriesIndex) =>
      points.slice(0, -1).map((point, index) => {
        const next = points[index + 1]!;
        const dx = next.x - point.x;
        const dy = next.y - point.y;
        const len = Math.sqrt(dx * dx + dy * dy);
        const angleDeg = (Math.atan2(dy, dx) * 180) / Math.PI;
        return (
          <view
            key={`seg-${seriesIndex}-${index}`}
            className="a2ui-anim-fade"
            style={{
              position: "absolute",
              left: `${(point.x + next.x) / 2 - len / 2}px`,
              top: `${(point.y + next.y) / 2 - 1.25}px`,
              width: `${len}px`,
              height: "2.5px",
              borderRadius: "2px",
              backgroundColor: point.color,
              transform: `rotate(${angleDeg}deg)`,
              animationDelay: `${index * 70}ms`,
            }}
          />
        );
      }),
    );
    const chartDots = seriesPoints.map((points, seriesIndex) =>
      points.map((point, index) => {
        const selected = selectedDot === index;
        const dotOffset = selected ? 4.5 : 3.5;
        return (
          <view
            key={`dot-${seriesIndex}-${index}`}
            className="a2ui-anim-fade"
            style={{
              position: "absolute",
              left: `${point.x - dotOffset}px`,
              top: `${point.y - dotOffset}px`,
              width: `${selected ? 9 : 7}px`,
              height: `${selected ? 9 : 7}px`,
              borderRadius: `${selected ? 4.5 : 3.5}px`,
              backgroundColor: point.color,
              border: `1.5px solid ${selected ? theme.primary : theme.surface}`,
              animationDelay: `${index * 70 + 240}ms`,
            }}
          />
        );
      }),
    );
    // 选中列的参考线与数值气泡
    const guideX =
      selectedDot === null ? null : canvasMargin.left + xStep * selectedDot;
    const selectedLabel =
      selectedDot === null ? "" : String(labels[selectedDot] ?? "");
    const selectedValues =
      selectedDot === null
        ? []
        : series.map((item) => ({
            name: item.name,
            value: item.values[selectedDot] ?? 0,
          }));
    // 整列热区（30px 宽、全画布高），置于最上层保证可点
    const chartHitBoxes = maxPoints
      ? Array.from({ length: maxPoints }, (_, index) => {
          const hitX = canvasMargin.left + xStep * index;
          return (
            <view
              key={`hit-${index}`}
              style={{
                position: "absolute",
                left: `${hitX - 15}px`,
                top: "0px",
                width: "30px",
                height: `${height}px`,
                backgroundColor: "transparent",
              }}
              bindtap={() =>
                setSelectedDot(selectedDot === index ? null : index)
              }
            />
          );
        })
      : [];
    const visibleLabelIndices = sampleIndices(labels.length, 8);
    const { min, max } = minMax(
      series.flatMap((item) => item.values.slice(0, labels.length)),
    );
    const chartTitle =
      typeof resolvedProps["yLabel"] === "string"
        ? resolvedProps["yLabel"]
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
        <view
          style={{
            display: "flex",
            flexDirection: "row",
            alignItems: "center",
            justifyContent: "space-between",
            width: "100%",
          }}
        >
          <text
            style={{
              fontSize: "16px",
              lineHeight: "22px",
              fontWeight: "600",
              flexShrink: 0,
              color: theme.onSurface,
            }}
          >
            {chartTitle}
          </text>
          {typeof resolvedProps["xLabel"] === "string" &&
          resolvedProps["xLabel"].length > 0 ? (
            <text
              style={{
                fontSize: "11px",
                lineHeight: "16px",
                flexShrink: 0,
                color: theme.onSurfaceMuted,
              }}
            >
              {resolvedProps["xLabel"]}
            </text>
          ) : null}
        </view>

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
            height: `${height}px`,
            position: "relative",
            alignSelf: "center",
          }}
        >
          {chartGrid}
          {chartBaseline}
          {chartSegments}
          {chartDots}
          {selectedDot !== null && guideX !== null ? (
            <view
              style={{
                position: "absolute",
                left: `${guideX}px`,
                top: `${canvasMargin.top}px`,
                width: "1px",
                height: `${plotH}px`,
                backgroundColor: theme.primary,
                opacity: 0.35,
              }}
            />
          ) : null}
          {selectedDot !== null && guideX !== null ? (
            <view
              style={{
                position: "absolute",
                left: `${Math.min(Math.max(guideX - 55, 0), canvasW - 110)}px`,
                top: "2px",
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
                {`${selectedLabel}　${selectedValues
                  .map((v) => `${v.name} ${formatValue(Number(v.value) || 0)}`)
                  .join(" · ")}`}
              </text>
            </view>
          ) : null}
          {chartHitBoxes}
        </view>

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

        {showLegend ? (
          <view
            style={{
              display: "flex",
              flexDirection: "row",
              flexWrap: "wrap",
              gap: "8px 14px",
              width: "100%",
            }}
          >
            {series.map((item, index) => (
              <view
                key={item.name}
                style={{
                  display: "flex",
                  flexDirection: "row",
                  alignItems: "center",
                  gap: "6px",
                }}
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
            ))}
          </view>
        ) : null}
      </view>
    );
  }

  const PIE_SVG_WIDTH = 360;
  const PIE_SVG_HEIGHT = 220;
  const PIE_CENTER_X = PIE_SVG_WIDTH / 2;
  const PIE_CENTER_Y = PIE_SVG_HEIGHT / 2;
  const PIE_OUTER_RADIUS = 84;
  const PIE_DONUT_INNER_RADIUS = 52;

  function formatPercent(value: number): string {
    if (!Number.isFinite(value)) return "0%";
    return `${Number(value.toFixed(1))}%`;
  }

  // --- BarChart（柱状图）：宿主自有扩展组件（官方 basic catalog 无此组件），
  // props 与 LineChart 对齐（labels + series），view 绘制：柱体为绝对定位
  // 矩形 view，基线从 0 起（柱状图惯例，不做 min-max 截断）。支持点选整组
  // 高亮 + 数值气泡，机制与 LineChart 一致。作为白名单扩展项写入 Skill 约束。 ---

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
    // 图表级 colors 覆写：JSON 传 colors 数组则作为系列色板，不传用 Koklam 色板
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

    // 几何：300px 设计宽，组内并列柱体，柱宽自适应；顶部预留 18px 给
    // 柱顶数值标签（showValues 时最高的柱标签也不能越界被裁）。
    const canvasW = 300;
    const margin = { top: 26, right: 12, bottom: 8, left: 12 };
    const plotW = canvasW - margin.left - margin.right;
    const plotH = height - margin.top - margin.bottom;
    const groupCount = labels.length;
    const seriesCount = series.length || 1;
    const groupW = groupCount > 0 ? plotW / groupCount : 0;
    const groupPad = 6;
    const barGap = seriesCount > 1 ? 2 : 0;
    const barW = Math.max(
      4,
      Math.min(
        24,
        (groupW - groupPad * 2 - (seriesCount - 1) * barGap) / seriesCount,
      ),
    );
    const allValues = series.flatMap((item) =>
      item.values.slice(0, groupCount),
    );
    const maxValue = allValues.reduce((acc, v) => (v > acc ? v : acc), 0);
    const scaleMax = maxValue > 0 ? maxValue : 1;

    const gridLines = 4;
    const chartGrid = Array.from({ length: gridLines + 1 }, (_, index) => {
      const ratio = index / gridLines;
      return (
        <view
          key={`bgrid-${index}`}
          style={{
            position: "absolute",
            left: `${margin.left}px`,
            top: `${margin.top + plotH - ratio * plotH}px`,
            width: `${plotW}px`,
            height: "1px",
            backgroundColor: theme.border,
          }}
        />
      );
    });
    const chartBaseline = (
      <view
        style={{
          position: "absolute",
          left: `${margin.left}px`,
          top: `${margin.top + plotH}px`,
          width: `${plotW}px`,
          height: "1.5px",
          backgroundColor: theme.onSurfaceMuted,
        }}
      />
    );
    // 柱体：值域 [0, scaleMax]，高度按占比；基线从 0 起
    const chartBars = series.flatMap((item, seriesIndex) =>
      item.values.slice(0, groupCount).map((value, groupIndex) => {
        const h = Math.max(2, ((Number(value) || 0) / scaleMax) * plotH);
        const dimmed = selectedGroup !== null && selectedGroup !== groupIndex;
        const barX =
          margin.left +
          groupIndex * groupW +
          groupPad +
          seriesIndex * (barW + barGap);
        return (
          <view
            key={`bar-${seriesIndex}-${groupIndex}`}
            className="a2ui-anim-grow-y"
            style={{
              position: "absolute",
              left: `${barX}px`,
              top: `${margin.top + plotH - h}px`,
              width: `${barW}px`,
              height: `${h}px`,
              borderTopLeftRadius: "4px",
              borderTopRightRadius: "4px",
              backgroundColor: item.color,
              opacity: dimmed ? 0.35 : 1,
              transformOrigin: "50% 100%",
              animationDelay: `${groupIndex * 60}ms`,
            }}
          />
        );
      }),
    );
    // 柱顶数值（showValues 时）
    const chartValueLabels = showValues
      ? series.flatMap((item, seriesIndex) =>
          item.values.slice(0, groupCount).map((value, groupIndex) => {
            const h = Math.max(2, ((Number(value) || 0) / scaleMax) * plotH);
            const dimmed =
              selectedGroup !== null && selectedGroup !== groupIndex;
            const barX =
              margin.left +
              groupIndex * groupW +
              groupPad +
              seriesIndex * (barW + barGap);
            return (
              <text
                key={`bval-${seriesIndex}-${groupIndex}`}
                style={{
                  position: "absolute",
                  left: `${barX - 6}px`,
                  top: `${margin.top + plotH - h - 15}px`,
                  width: `${barW + 12}px`,
                  textAlign: "center",
                  fontSize: "10px",
                  lineHeight: "12px",
                  color: dimmed ? theme.onSurfaceMuted : theme.onSurface,
                }}
              >
                {formatValue(Number(value) || 0)}
              </text>
            );
          }),
        )
      : [];
    // 选中组的数值气泡
    const guideX =
      selectedGroup === null
        ? null
        : margin.left + selectedGroup * groupW + groupW / 2;
    const selectedLabel =
      selectedGroup === null ? "" : String(labels[selectedGroup] ?? "");
    const selectedValues =
      selectedGroup === null
        ? []
        : series.map((item) => ({
            name: item.name,
            value: item.values[selectedGroup] ?? 0,
          }));
    // 整组热区
    const chartHitBoxes = groupCount
      ? Array.from({ length: groupCount }, (_, index) => (
          <view
            key={`bhit-${index}`}
            style={{
              position: "absolute",
              left: `${margin.left + index * groupW}px`,
              top: "0px",
              width: `${groupW}px`,
              height: `${height}px`,
              backgroundColor: "transparent",
            }}
            bindtap={() =>
              setSelectedGroup(selectedGroup === index ? null : index)
            }
          />
        ))
      : [];

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
        <view
          style={{
            width: "300px",
            height: `${height}px`,
            position: "relative",
            alignSelf: "center",
          }}
        >
          {chartGrid}
          {chartBaseline}
          {chartBars}
          {chartValueLabels}
          {selectedGroup !== null && guideX !== null ? (
            <view
              style={{
                position: "absolute",
                left: `${Math.min(Math.max(guideX - 55, 0), canvasW - 110)}px`,
                top: "0px",
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
                {`${selectedLabel}　${selectedValues
                  .map((v) => `${v.name} ${formatValue(Number(v.value) || 0)}`)
                  .join(" · ")}`}
              </text>
            </view>
          ) : null}
          {chartHitBoxes}
        </view>

        <view
          style={{
            width: "300px",
            height: "16px",
            position: "relative",
            alignSelf: "center",
          }}
        >
          {labels.map((label, index) => (
            <text
              key={`${index}-${label ?? index}`}
              style={{
                position: "absolute",
                left: `${margin.left + index * groupW}px`,
                top: "0px",
                width: `${groupW}px`,
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

        {showLegend ? (
          <view
            style={{
              display: "flex",
              flexDirection: "row",
              flexWrap: "wrap",
              gap: "8px 14px",
              width: "100%",
            }}
          >
            {series.map((item) => (
              <view
                key={item.name}
                style={{
                  display: "flex",
                  flexDirection: "row",
                  alignItems: "center",
                  gap: "6px",
                }}
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
            ))}
          </view>
        ) : null}
      </view>
    );
  }

  // --- ScatterChart（散点图）/ RadarChart（雷达图）/ FunnelChart（漏斗图）：
  // 宿主自有扩展组件（官方 basic catalog 无），全部纯 view 绘制。 ---

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
    // 图表级 colors 覆写：JSON 传 colors 数组则作为系列色板，不传用 Koklam 色板
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
    const margin = { top: 8, right: 12, bottom: 8, left: 12 };
    const plotW = canvasW - margin.left - margin.right;
    const plotH = height - margin.top - margin.bottom;
    const maxPoints = labels.length;
    const allValues = series.flatMap((item) => item.values.slice(0, maxPoints));
    const { min: plotMin, max: plotMax } = minMax(allValues);
    const plotRange = plotMax - plotMin;
    const xStep = maxPoints > 1 ? plotW / (maxPoints - 1) : 0;
    const seriesPoints = series.map((item) =>
      item.values.slice(0, maxPoints).map((value, index) => ({
        x: margin.left + xStep * index,
        y:
          margin.top +
          plotH -
          (plotRange === 0 ? 0.5 : (value - plotMin) / plotRange) * plotH,
        color: item.color,
      })),
    );
    const gridLines = 4;
    const chartGrid = Array.from({ length: gridLines + 1 }, (_, index) => {
      const ratio = index / gridLines;
      return (
        <view
          key={`sgrid-${index}`}
          style={{
            position: "absolute",
            left: `${margin.left}px`,
            top: `${margin.top + plotH - ratio * plotH}px`,
            width: `${plotW}px`,
            height: "1px",
            backgroundColor: theme.border,
          }}
        />
      );
    });
    const chartBaseline = (
      <view
        style={{
          position: "absolute",
          left: `${margin.left}px`,
          top: `${margin.top + plotH}px`,
          width: `${plotW}px`,
          height: "1.5px",
          backgroundColor: theme.onSurfaceMuted,
        }}
      />
    );
    // 散点：9px 圆点（散点是主数据，比折线的数据点大）
    const chartDots = seriesPoints.map((points, seriesIndex) =>
      points.map((point, index) => {
        const selected = selectedDot === index;
        const dotSize = selected ? "11px" : "9px";
        const dotOffset = selected ? 5.5 : 4.5;
        return (
          <view
            key={`sdot-${seriesIndex}-${index}`}
            className="a2ui-anim-pop"
            style={{
              position: "absolute",
              left: `${point.x - dotOffset}px`,
              top: `${point.y - dotOffset}px`,
              width: dotSize,
              height: dotSize,
              borderRadius: `${dotOffset}px`,
              backgroundColor: point.color,
              opacity: selected || selectedDot === null ? 1 : 0.45,
              animationDelay: `${index * 70 + seriesIndex * 35}ms`,
            }}
          />
        );
      }),
    );
    const guideX =
      selectedDot === null ? null : margin.left + xStep * selectedDot;
    const selectedLabel =
      selectedDot === null ? "" : String(labels[selectedDot] ?? "");
    const selectedValues =
      selectedDot === null
        ? []
        : series.map((item) => ({
            name: item.name,
            value: item.values[selectedDot] ?? 0,
          }));
    const chartHitBoxes = maxPoints
      ? Array.from({ length: maxPoints }, (_, index) => (
          <view
            key={`shit-${index}`}
            style={{
              position: "absolute",
              left: `${margin.left + xStep * index - 15}px`,
              top: "0px",
              width: "30px",
              height: `${height}px`,
              backgroundColor: "transparent",
            }}
            bindtap={() => setSelectedDot(selectedDot === index ? null : index)}
          />
        ))
      : [];

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
            height: `${height}px`,
            position: "relative",
            alignSelf: "center",
          }}
        >
          {chartGrid}
          {chartBaseline}
          {chartDots}
          {selectedDot !== null && guideX !== null ? (
            <view
              style={{
                position: "absolute",
                left: `${guideX}px`,
                top: `${margin.top}px`,
                width: "1px",
                height: `${plotH}px`,
                backgroundColor: theme.primary,
                opacity: 0.35,
              }}
            />
          ) : null}
          {selectedDot !== null && guideX !== null ? (
            <view
              style={{
                position: "absolute",
                left: `${Math.min(Math.max(guideX - 55, 0), canvasW - 110)}px`,
                top: "2px",
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
                {`${selectedLabel}　${selectedValues
                  .map((v) => `${v.name} ${formatValue(Number(v.value) || 0)}`)
                  .join(" · ")}`}
              </text>
            </view>
          ) : null}
          {chartHitBoxes}
        </view>
        <view
          style={{
            display: "flex",
            flexDirection: "row",
            justifyContent: "space-between",
            width: "300px",
            alignSelf: "center",
          }}
        >
          {labels.map((label, index) => (
            <text
              key={`sax-${index}-${label ?? index}`}
              style={{
                fontSize: "11px",
                lineHeight: "16px",
                color: theme.onSurfaceMuted,
              }}
            >
              {label ?? ""}
            </text>
          ))}
        </view>
        {showLegend ? (
          <view
            style={{
              display: "flex",
              flexDirection: "row",
              flexWrap: "wrap",
              gap: "8px 14px",
              width: "100%",
            }}
          >
            {series.map((item) => (
              <view
                key={item.name}
                style={{
                  display: "flex",
                  flexDirection: "row",
                  alignItems: "center",
                  gap: "6px",
                }}
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
                    fontSize: "12px",
                    lineHeight: "16px",
                    color: theme.onSurfaceMuted,
                  }}
                >
                  {item.name}
                </text>
              </view>
            ))}
          </view>
        ) : null}
      </view>
    );
  }

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
    // 图表级 colors 覆写：JSON 传 colors 数组则作为系列色板，不传用 Koklam 色板
    const chartPalette = Array.isArray(resolvedProps["colors"])
      ? (resolvedProps["colors"] as string[])
      : DEFAULT_CHART_COLORS;
    const series = Array.isArray(seriesValue)
      ? normalizeSeries(seriesValue, chartPalette)
      : [];
    const showLegend = resolvedProps["showLegend"] !== false;
    const heightValue = resolvedProps["height"];
    const height = typeof heightValue === "number" ? heightValue : 250;

    // 画布：300×height，圆心居中，半径留出标签空间
    const canvasW = 300;
    const cx = canvasW / 2;
    const cy = height / 2;
    const radius = Math.min(110, height / 2 - 26);
    const axisCount = indicators.length;
    const rings = 4;
    const ringElements = Array.from({ length: rings }, (_, index) => {
      const r = (radius * (index + 1)) / rings;
      return (
        <view
          key={`rring-${index}`}
          className="a2ui-anim-pop"
          style={{
            position: "absolute",
            left: `${cx - r}px`,
            top: `${cy - r}px`,
            width: `${r * 2}px`,
            height: `${r * 2}px`,
            borderRadius: "50%",
            border: `1px solid ${theme.border}`,
            animationDelay: `${index * 70}ms`,
          }}
        />
      );
    });
    // 辐条：中心到外圈的细线（中心点定位 + 旋转）
    const spokeElements = indicators.map((_, index) => {
      const angleDeg = -90 + (index * 360) / Math.max(1, axisCount);
      return (
        <view
          key={`rspoke-${index}`}
          style={{
            position: "absolute",
            left: `${cx - 0.5}px`,
            top: `${cy - radius / 2}px`,
            width: "1px",
            height: `${radius}px`,
            backgroundColor: theme.border,
            transform: `rotate(${angleDeg + 90}deg)`,
          }}
        />
      );
    });
    // 指标标签：外圈外围 60px 宽居中文本
    const labelElements = indicators.map((indicator, index) => {
      const angleDeg = -90 + (index * 360) / Math.max(1, axisCount);
      const rad = (angleDeg * Math.PI) / 180;
      const lx = cx + (radius + 18) * Math.cos(rad);
      const ly = cy + (radius + 18) * Math.sin(rad);
      return (
        <text
          key={`rlabel-${index}`}
          style={{
            position: "absolute",
            left: `${lx - 30}px`,
            top: `${ly - 8}px`,
            width: "60px",
            textAlign: "center",
            fontSize: "11px",
            lineHeight: "16px",
            color: theme.onSurfaceMuted,
          }}
        >
          {String(indicator["name"] ?? "")}
        </text>
      );
    });
    // 数据多边形：顶点相连的线段 + 顶点圆点（未选系列淡化）
    const vertexAt = (seriesIndex: number, axisIndex: number) => {
      const indicator = (indicators[axisIndex] ?? {}) as Record<
        string,
        unknown
      >;
      const maxV = Number(indicator["max"]) || 1;
      const item = series[seriesIndex]!;
      const raw = Number(item.values[axisIndex]) || 0;
      const ratio = Math.max(0, Math.min(1, raw / maxV));
      const angleDeg = -90 + (axisIndex * 360) / Math.max(1, axisCount);
      const rad = (angleDeg * Math.PI) / 180;
      return {
        x: cx + radius * ratio * Math.cos(rad),
        y: cy + radius * ratio * Math.sin(rad),
      };
    };
    const polygonElements = series.flatMap((item, seriesIndex) => {
      const dimmed = selectedSeries !== null && selectedSeries !== seriesIndex;
      const count = Math.min(axisCount, item.values.length);
      const segments: Array<JSX.Element> = [];
      for (let index = 0; index < count; index += 1) {
        const a = vertexAt(seriesIndex, index);
        const b = vertexAt(seriesIndex, (index + 1) % count);
        const dx = b.x - a.x;
        const dy = b.y - a.y;
        const len = Math.sqrt(dx * dx + dy * dy);
        const angleDeg = (Math.atan2(dy, dx) * 180) / Math.PI;
        segments.push(
          <view
            key={`rpoly-${seriesIndex}-${index}`}
            style={{
              position: "absolute",
              left: `${(a.x + b.x) / 2 - len / 2}px`,
              top: `${(a.y + b.y) / 2 - 1.25}px`,
              width: `${len}px`,
              height: "2.5px",
              backgroundColor: item.color,
              opacity: dimmed ? 0.25 : 1,
              transform: `rotate(${angleDeg}deg)`,
            }}
          />,
        );
      }
      const dots = item.values.slice(0, count).map((_, axisIndex) => {
        const v = vertexAt(seriesIndex, axisIndex);
        return (
          <view
            key={`rdot-${seriesIndex}-${axisIndex}`}
            style={{
              position: "absolute",
              left: `${v.x - 3}px`,
              top: `${v.y - 3}px`,
              width: "6px",
              height: "6px",
              borderRadius: "3px",
              backgroundColor: item.color,
              opacity: dimmed ? 0.25 : 1,
            }}
          />
        );
      });
      // 整个多边形包在 scale 包裹层里从圆心向外撑开（子元素的内联
      // rotate/定位不受影响）；多系列依次进场
      return (
        <view
          key={`rpoly-${seriesIndex}`}
          className="a2ui-anim-grow"
          style={{
            position: "absolute",
            left: "0px",
            top: "0px",
            width: "100%",
            height: "100%",
            animationDelay: `${seriesIndex * 150}ms`,
          }}
        >
          {segments}
          {dots}
        </view>
      );
    });
    // 图例行可点选系列
    const legend = showLegend ? (
      <view
        style={{
          display: "flex",
          flexDirection: "row",
          flexWrap: "wrap",
          gap: "8px 14px",
          width: "100%",
          justifyContent: "center",
        }}
      >
        {series.map((item, index) => (
          <view
            key={`rlegend-${item.name}`}
            style={{
              display: "flex",
              flexDirection: "row",
              alignItems: "center",
              gap: "6px",
            }}
            bindtap={() =>
              setSelectedSeries(selectedSeries === index ? null : index)
            }
          >
            <view
              style={{
                width: "10px",
                height: "10px",
                borderRadius: "5px",
                backgroundColor: item.color,
                opacity:
                  selectedSeries === null || selectedSeries === index
                    ? 1
                    : 0.35,
              }}
            />
            <text
              style={{
                fontSize: "12px",
                lineHeight: "16px",
                color:
                  selectedSeries === index
                    ? theme.onSurface
                    : theme.onSurfaceMuted,
              }}
            >
              {item.name}
            </text>
          </view>
        ))}
      </view>
    ) : null;

    return (
      <view
        key={id}
        style={{
          width: "100%",
          display: "flex",
          flexDirection: "column",
          gap: "8px",
          minWidth: 0,
          alignItems: "center",
        }}
      >
        <view
          style={{
            width: "300px",
            height: `${height}px`,
            position: "relative",
          }}
        >
          {ringElements}
          {spokeElements}
          {polygonElements}
          {labelElements}
        </view>
        {legend}
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

  function PieChart(props: GenericComponentProps) {
    const [resolvedProps] = useResolvedProps(
      props,
      props.surface,
      props.dataContextPath,
    );
    const id = props.id;
    // 点选态：tap 扇形/图例 → 该扇形保持高亮、其余淡化；再 tap 取消。
    const [selectedSlice, setSelectedSlice] = useState<number | null>(null);

    const dataValue = resolvedProps["data"];
    const slices = Array.isArray(dataValue)
      ? (dataValue as Array<Record<string, unknown>>)
      : [];
    const variant =
      typeof resolvedProps["variant"] === "string"
        ? resolvedProps["variant"]
        : "pie";
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
    const heightValue = resolvedProps["height"];
    const height = typeof heightValue === "number" ? heightValue : 220;
    const palette = Array.isArray(resolvedProps["colors"])
      ? (resolvedProps["colors"] as string[])
      : DEFAULT_CHART_COLORS;

    // 环形几何（切线线段逼近）：外径 84；donut 内径 52 / pie 小孔 14；
    // 每 3° 一段 +1px 重叠补隙，静态实心平滑。段全程不透明（透明淡入会让
    // 重叠区显双份深斑——用户实测反馈），生长动效在扇形包裹层上做 scale。
    const outerRadius = 84;
    const innerRadius = variant === "donut" ? 52 : 14;
    const ringMid = (outerRadius + innerRadius) / 2;
    const ringThickness = outerRadius - innerRadius;
    const segStep = 3;
    const polarAt = (angleDeg: number, r: number) => {
      const rad = ((angleDeg - 90) * Math.PI) / 180;
      return {
        x: PIE_CENTER_X + r * Math.cos(rad),
        y: PIE_CENTER_Y + r * Math.sin(rad),
      };
    };
    const ringGroups: Array<JSX.Element> = [];
    if (total > 0) {
      let cursor = 0; // 自 12 点钟顺时针累计角度
      slices.forEach((slice, sliceIndex) => {
        const value = Math.max(0, Number(slice["value"]) || 0);
        if (value <= 0) return;
        const sliceAngle = (value / total) * 360;
        const segCount = Math.max(1, Math.round(sliceAngle / segStep));
        const color =
          typeof slice["color"] === "string"
            ? slice["color"]
            : palette[sliceIndex % palette.length] ?? DEFAULT_CHART_COLORS[0]!;
        const dimmed = selectedSlice !== null && selectedSlice !== sliceIndex;
        const segments: Array<JSX.Element> = [];
        for (let i = 0; i < segCount; i += 1) {
          const a1 = cursor + (i * sliceAngle) / segCount;
          const a2 = cursor + ((i + 1) * sliceAngle) / segCount;
          const p1 = polarAt(a1, ringMid);
          const p2 = polarAt(a2, ringMid);
          const dx = p2.x - p1.x;
          const dy = p2.y - p1.y;
          const len = Math.sqrt(dx * dx + dy * dy) + 1;
          const angleDeg = (Math.atan2(dy, dx) * 180) / Math.PI;
          segments.push(
            <view
              key={`rseg-${sliceIndex}-${i}`}
              style={{
                position: "absolute",
                left: `${(p1.x + p2.x) / 2 - len / 2}px`,
                top: `${(p1.y + p2.y) / 2 - ringThickness / 2}px`,
                width: `${len}px`,
                height: `${ringThickness}px`,
                backgroundColor: color,
                opacity: dimmed ? 0.3 : 1,
                transform: `rotate(${angleDeg}deg)`,
              }}
              bindtap={() =>
                setSelectedSlice(
                  selectedSlice === sliceIndex ? null : sliceIndex,
                )
              }
            />,
          );
        }
        // 扇形整体包 scale 包裹层：从圆心向外生长（0→100），逐扇形错峰
        ringGroups.push(
          <view
            key={`rgrp-${sliceIndex}`}
            className="a2ui-anim-grow"
            style={{
              position: "absolute",
              left: "0px",
              top: "0px",
              width: "100%",
              height: "100%",
              animationDelay: `${sliceIndex * 130}ms`,
            }}
          >
            {segments}
          </view>,
        );
        cursor += sliceAngle;
      });
    }

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
            flexDirection: "row",
            alignItems: "center",
            justifyContent: "space-between",
          }}
        >
          <view style={{ display: "flex", flexDirection: "column", gap: "2px" }}>
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
          <view
            style={{
              display: "flex",
              flexDirection: "column",
              alignItems: "flex-end",
            }}
          >
            <text
              style={{
                fontSize: "11px",
                lineHeight: "16px",
                color: theme.onSurfaceMuted,
              }}
            >
              合计
            </text>
            <text
              style={{
                fontSize: "17px",
                lineHeight: "22px",
                fontWeight: "700",
                color: theme.onSurface,
              }}
            >
              {formatValue(total)}
            </text>
          </view>
        </view>

        <view
          style={{
            width: "300px",
            height: `${height}px`,
            position: "relative",
            alignSelf: "center",
          }}
        >
          {ringGroups}
          {total > 0 ? (
            <view
              style={{
                position: "absolute",
                left: `${PIE_CENTER_X - innerRadius}px`,
                top: `${PIE_CENTER_Y - innerRadius}px`,
                width: `${innerRadius * 2}px`,
                height: `${innerRadius * 2}px`,
                borderRadius: "50%",
                backgroundColor: theme.surface,
              }}
            />
          ) : null}
        </view>

        <view
          style={{
            width: "100%",
            display: "flex",
            flexDirection: "column",
            gap: "8px",
          }}
        >
          {slices.map((slice, index) => {
            const value = Math.max(0, Number(slice["value"]) || 0);
            const percent = total > 0 ? (value / total) * 100 : 0;
            const color =
              typeof slice["color"] === "string"
                ? slice["color"]
                : palette[index % palette.length] ?? DEFAULT_CHART_COLORS[0]!;
            const dimmed = selectedSlice !== null && selectedSlice !== index;
            return (
              <view
                key={`legend-${String(slice["name"] ?? "")}-${index}`}
                style={{
                  width: "100%",
                  display: "flex",
                  flexDirection: "row",
                  alignItems: "center",
                  gap: "8px",
                  opacity: dimmed ? 0.4 : 1,
                }}
                bindtap={() =>
                  setSelectedSlice(selectedSlice === index ? null : index)
                }
              >
                <view
                  style={{
                    width: "10px",
                    height: "10px",
                    borderRadius: "2px",
                    backgroundColor: color,
                    flexShrink: 0,
                  }}
                />
                <text
                  style={{
                    fontSize: "13px",
                    lineHeight: "18px",
                    color: theme.onSurface,
                  }}
                >
                  {String(slice["name"] ?? "")}
                </text>
                <text
                  style={{
                    fontSize: "13px",
                    lineHeight: "18px",
                    fontWeight: selectedSlice === index ? "600" : "400",
                    color:
                      selectedSlice === index
                        ? theme.primary
                        : theme.onSurfaceMuted,
                    marginLeft: "auto",
                  }}
                >
                  {showPercentages
                    ? `${formatValue(value)}（${formatPercent(percent)}）`
                    : formatValue(value)}
                </text>
              </view>
            );
          })}
        </view>
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
  };
}
