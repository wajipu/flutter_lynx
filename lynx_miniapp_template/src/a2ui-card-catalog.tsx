import {
  createContext,
  useContext,
  useSyncExternalStore,
} from "@lynx-js/react";
import { NodeRenderer, useChecks, useDataBinding } from "@lynx-js/genui/a2ui";
import type {
  ComponentInstance,
  GenericComponentProps,
  Resource,
  ResourceInfo,
  Surface,
} from "@lynx-js/genui/a2ui";

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
}

/** 默认亮色主题：与 confirm-card.tsx 在真机验证过的色板同源（#1677ff 系）。 */
export const defaultA2UICardTheme: A2UICardTheme = {
  background: "#f7f8fa",
  surface: "#ffffff",
  surfaceMuted: "#f2f3f5",
  onSurface: "#1f2329",
  onSurfaceMuted: "#86909c",
  primary: "#1677ff",
  onPrimary: "#ffffff",
  border: "#e5e6eb",
  divider: "#f0f1f3",
  cardShadow: "0 4px 16px rgba(29, 35, 46, 0.06)",
};

/**
 * 合并宿主注入的主题覆写：只接受主题里已有的键且值非空字符串，其余
 * （未知键、非字符串、空值）一律忽略——initData 是宿主可信通道，但
 * 仍按白名单收敛，防止宿主误传把整块样式打挂。
 */
export function mergeA2UICardTheme(overrides: unknown): A2UICardTheme {
  const theme: Record<string, string> = { ...defaultA2UICardTheme };
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

// 字号/字重/行高层级：h1..h5、body、caption（官方 caption 只有 10px 太小，
// 提升到 12px 并配弱化色，拉开与 body 的层级）。
const TEXT_VARIANTS = {
  h1: { fontSize: "24px", lineHeight: "32px", fontWeight: "700" },
  h2: { fontSize: "20px", lineHeight: "28px", fontWeight: "700" },
  h3: { fontSize: "17px", lineHeight: "24px", fontWeight: "600" },
  h4: { fontSize: "15px", lineHeight: "22px", fontWeight: "600" },
  h5: { fontSize: "13px", lineHeight: "18px", fontWeight: "600" },
  body: { fontSize: "14px", lineHeight: "22px", fontWeight: "400" },
  caption: { fontSize: "12px", lineHeight: "17px", fontWeight: "400" },
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
                style={{ flex: `${weight} ${weight} 0`, minWidth: 0 }}
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
                style={{ flex: `${weight} ${weight} 0`, minHeight: 0 }}
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
          borderRadius: "16px",
          padding: "16px",
          border: `1px solid ${theme.border}`,
        };
      case "filled":
        return {
          ...base,
          backgroundColor: theme.surfaceMuted,
          borderRadius: "16px",
          padding: "16px",
        };
      case "ghost":
        return { ...base, backgroundColor: "transparent" };
      default:
        return {
          ...base,
          backgroundColor: theme.surface,
          borderRadius: "16px",
          padding: "16px",
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
      flex: 1,
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
      style = { ...style, flex: "1 1 0" };
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

  return { Text, Row, Column, Card, Divider, Button, Image, List, Loading };
}
