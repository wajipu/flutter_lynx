import { useEffect, useInitData, useState } from "@lynx-js/react";
import type { ReactNode } from "react";
import { LynxBridge } from "./bridge";
import type { InventoryAlertItem } from "./bridge";
import "./workbench-miso-demo.css";

type HostInitData = {
  entryKey?: string;
  displayType?: number | string;
  applySafeArea?: boolean | number | string;
  safeArea?: { bottom?: number };
  menuButton?: { bottom?: number };
};

function readApplySafeArea(value: unknown): boolean {
  return value === true || value === 1 || value === "1" || value === "true";
}

function readPx(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? n : 0;
}

function asText(value: unknown): string {
  return typeof value === "string" ? value : String(value ?? "");
}

// 文案只打包已确认语言（zh_CN）；语言目录读点落地前不做语言选择器（13 号文 §6）。
const I18N = {
  alertTitle: "库存预警",
  alertCopy: "当前门店待补货商品，打开时实时获取。",
  alertLoading: "正在获取库存预警…",
  alertEmpty: "没有待处理的库存预警",
  alertErrorPrefix: "加载失败",
  alertRetry: "重试",
  alertRelogin: "登录已失效，请在宿主 App 重新登录后重试。",
  alertQuantityLabel: "当前库存",
  alertThresholdLabel: "预警阈值",
} as const;

function formatDetectedAt(value: string): string {
  return value.replace("T", " ").slice(0, 16);
}

type AlertState =
  | { phase: "loading" }
  | { phase: "empty" }
  | { phase: "error"; msg: string; code: number }
  | { phase: "ready"; items: InventoryAlertItem[] };

function AlertRow({ item }: { item: InventoryAlertItem }) {
  const unit = item.unit ?? "";
  return (
    <view className="miso-card">
      <text className="miso-card-title">{item.name}</text>
      <text className="miso-alert-meta">
        {I18N.alertQuantityLabel} {item.quantity}
        {unit} · {I18N.alertThresholdLabel} {item.threshold}
        {unit}
      </text>
      {item.detectedAt ? (
        <text className="miso-alert-time">{formatDetectedAt(item.detectedAt)}</text>
      ) : null}
    </view>
  );
}

/// 库存预警：每次打开都经 data Bridge 重新代调（13 号文 §5），任何状态不写死业务数值。
function InventoryAlertSection() {
  const [state, setState] = useState<AlertState>({ phase: "loading" });
  const [attempt, setAttempt] = useState(0);

  useEffect(() => {
    let alive = true;
    setState({ phase: "loading" });
    LynxBridge.inventoryAlertList()
      .then((envelope) => {
        if (!alive) return;
        if (envelope.code === 200 && envelope.data) {
          const list = envelope.data.list ?? [];
          setState(
            list.length > 0
              ? { phase: "ready", items: list }
              : { phase: "empty" },
          );
        } else {
          setState({
            phase: "error",
            msg: envelope.msg || `${I18N.alertErrorPrefix} (${envelope.code})`,
            code: envelope.code,
          });
        }
      })
      .catch((error: unknown) => {
        if (!alive) return;
        const message = error instanceof Error ? error.message : String(error);
        setState({ phase: "error", msg: message, code: -1 });
      });
    return () => {
      alive = false;
    };
  }, [attempt]);

  return (
    <view className="miso-section">
      <text className="miso-section-title">{I18N.alertTitle}</text>
      <text className="miso-section-copy">{I18N.alertCopy}</text>
      {state.phase === "loading" ? (
        <view className="miso-card">
          <view className="miso-skeleton-line" />
          <view className="miso-skeleton-line short" />
        </view>
      ) : null}
      {state.phase === "empty" ? (
        <view className="miso-card">
          <text className="miso-alert-empty">{I18N.alertEmpty}</text>
        </view>
      ) : null}
      {state.phase === "error" ? (
        <view className="miso-card">
          <text className="miso-alert-error-text">{state.msg}</text>
          {state.code === 401 ? (
            <text className="miso-alert-error-text">{I18N.alertRelogin}</text>
          ) : null}
          <TapView
            className="miso-retry"
            onTap={() => setAttempt((n) => n + 1)}
          >
            <text className="miso-reset-text">{I18N.alertRetry}</text>
          </TapView>
        </view>
      ) : null}
      {state.phase === "ready" ? (
        <view>
          {state.items.map((item, index) => (
            <AlertRow key={`${item.productId}:${item.specId ?? index}`} item={item} />
          ))}
        </view>
      ) : null}
    </view>
  );
}

function TapView({
  className,
  onTap,
  children,
}: {
  className?: string;
  onTap: () => void;
  children: ReactNode;
}) {
  return (
    <view className={className} flatten={false} bindtap={onTap}>
      {children}
    </view>
  );
}

function Counter({ compact }: { compact: boolean }) {
  const [count, setCount] = useState(0);
  return (
    <view>
      <view className="miso-counter">
        <TapView className="miso-counter-btn" onTap={() => setCount((n) => n - 1)}>
          <text className="miso-counter-btn-text">−</text>
        </TapView>
        <text className="miso-counter-value">{count}</text>
        <TapView className="miso-counter-btn" onTap={() => setCount((n) => n + 1)}>
          <text className="miso-counter-btn-text">+</text>
        </TapView>
      </view>
      {!compact && (
        <TapView className="miso-reset" onTap={() => setCount(0)}>
          <text className="miso-reset-text">reset</text>
        </TapView>
      )}
    </view>
  );
}

function InlineCard() {
  return (
    <view className="miso-inline">
      <view>
        <text className="miso-inline-kicker">miso.ui · Lynx 4.1</text>
        <text className="miso-inline-title">工作台计数器</text>
      </view>
      <Counter compact />
    </view>
  );
}

function HomePage({ paddingTop, paddingBottom }: { paddingTop: number; paddingBottom: number }) {
  const [heroHint, setHeroHint] = useState("");
  return (
    <scroll-view
      scroll-orientation="vertical"
      scroll-y
      className="miso-page"
      style={{
        width: "100%",
        height: "100%",
        paddingTop,
        paddingRight: 16,
        paddingBottom,
        paddingLeft: 16,
      }}
    >
      <InventoryAlertSection />

      <view className="miso-hero">
        <view className="miso-mark">
          <text className="miso-mark-text">λ</text>
        </view>
        <text className="miso-kicker">🍜 A tasty Haskell UI framework</text>
        <text className="miso-title">The React framework</text>
        <text className="miso-title">for Haskell.</text>
        <text className="miso-lead">
          用 haskell-miso.org 和 miso.ui 的深色组件，做给工作台的 Lynx 演示。
        </text>
        <view className="miso-actions">
          <TapView className="miso-btn miso-btn-primary" onTap={() => setHeroHint("started")}>
            <text className="miso-btn-text miso-btn-text-primary">Get started</text>
          </TapView>
          <TapView className="miso-btn miso-btn-ghost" onTap={() => setHeroHint("ui")}>
            <text className="miso-btn-text miso-btn-text-ghost">miso.ui</text>
          </TapView>
        </view>
        {heroHint === "started" ? (
          <text className="miso-lead">计数器可以点，整页可以上下滑。</text>
        ) : null}
        {heroHint === "ui" ? (
          <text className="miso-lead">上面的库存预警卡片来自宿主代调的真实数据。</text>
        ) : null}
        <view className="miso-terminal">
          <text className="miso-terminal-line">$ git clone https://github.com/haskell-miso/miso-sampler</text>
          <text className="miso-terminal-line">$ nix develop .#wasm --command bash -c 'make all'</text>
        </view>
      </view>

      <view className="miso-section">
        <text className="miso-section-title">Your first miso application</text>
        <text className="miso-section-copy">model、update、view。一个 Component 就是整页。</text>
        <view className="miso-card">
          <Counter compact={false} />
        </view>
      </view>

      <view className="miso-alert">
        <text className="miso-alert-text">本包声明 Lynx 4.1.0 / Bridge API 2，宿主按 system,data 模块加载。</text>
      </view>
    </scroll-view>
  );
}

export default function WorkbenchMisoDemo() {
  const initData = useInitData() as HostInitData;
  const entryKey = asText(initData.entryKey);
  const displayType = Number(initData.displayType);
  const inline = displayType === 2 || entryKey === "counter";
  if (inline) {
    return <InlineCard />;
  }
  const sheet = displayType === 3 || entryKey === "sheet";
  const applySafeArea = readApplySafeArea(initData.applySafeArea);
  const paddingTop = sheet ? 8 : applySafeArea ? readPx(initData.menuButton?.bottom) + 12 : 20;
  const paddingBottom = applySafeArea ? readPx(initData.safeArea?.bottom) + (sheet ? 16 : 24) : sheet ? 16 : 24;
  return <HomePage paddingTop={paddingTop} paddingBottom={paddingBottom} />;
}
