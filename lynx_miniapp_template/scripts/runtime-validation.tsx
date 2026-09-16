import { useEffect, useInitData, useState } from "@lynx-js/react";
import { LynxBridge } from "../src/bridge";

function readApplySafeArea(value: unknown): boolean {
  return value === true || value === 1 || value === "1" || value === "true";
}

function readPx(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? n : 0;
}

// Reuse the example's bundled launcher PNG; no network or extra image fixture is needed.
const verificationImage = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAMAAABg3Am1AAAAGXRFWHRTb2Z0d2FyZQBBZG9iZSBJbWFnZVJlYWR5ccllPAAAAIpQTFRFAAAAAVebVMX4Kbb2VMX4AVebKbb2VMX4VMX4Kbb2VMX4VMX4VMX4AVebB1ePVMX4AVebBENyKbb2UcT4VMX4ADxrAUJ1AU2KAU6LAVSVAVSWAVWXAVaZAVaaAVeaAVebAy1LAzFRBUJuBU2ABlOJHom6H43AIZXLIprSIpzVKbb2Mbn2UcT4VMX4UU+PBQAAABV0Uk5TABAQICAwMDCPn5+vv8/Pz+/v7+/vb7KPEwAAAKVJREFUSMft1MkSgjAQRdGIA86igoKirSIOiP//ew6J3WwMnYULU3nL1LnVuwhh9/zwTpt4zjvv/G99d0gbePW+X3kJfd0Bjq8WPE8F138K6Xu3stbLQvmiwOK7fxXosdB5IVrkVaH3csq/CyP/LOYM35xRcB03GJ92B4vLMR2ZFOcs2YJBcTrEqw3wi3y/WK4B2EW+i+IUgF9ME8CxinYAVhR/sgfbkVbaxFzJpwAAAABJRU5ErkJggg==";

/** A/B fixtures exercise the real bundle, local state and both directions of the native bridge. */
export function RuntimeValidation({ variant }: { variant: "A" | "B" }) {
  const initData = useInitData() as {
    applySafeArea?: boolean | number | string;
    safeArea?: { top?: number; bottom?: number };
    menuButton?: { bottom?: number };
  };
  const applySafeArea = readApplySafeArea(initData?.applySafeArea);
  // 胶囊浮在全屏 Lynx 上；打开安全区时避开 menuButton 下沿和底部 Home Indicator。
  const paddingTop = applySafeArea
    ? readPx(initData?.menuButton?.bottom)
    : 20;
  const paddingBottom = applySafeArea
    ? readPx(initData?.safeArea?.bottom) + 20
    : 20;
  const [count, setCount] = useState(0);
  const [systemInfo, setSystemInfo] = useState("pending");
  const [hostEvents, setHostEvents] = useState(0);
  const [lastHostEvent, setLastHostEvent] = useState("none");
  const [eventStatus, setEventStatus] = useState("pending");
  const [imageStatus, setImageStatus] = useState("pending");
  const [blockedStatus, setBlockedStatus] = useState("pending");
  const [defaultStatus, setDefaultStatus] = useState("pending");

  const readSystemInfo = () => {
    setSystemInfo("pending");
    LynxBridge.getSystemInfo().then(
      info => setSystemInfo(JSON.stringify(info)),
      error => setSystemInfo(`ERROR: ${String(error)}`),
    );
  };

  const verifyBridgeBoundary = async () => {
    try {
      const first = await LynxBridge.getSystemInfo();
      setSystemInfo(JSON.stringify(first));
      try {
        await LynxBridge.setStorage("runtime-verification", variant);
        setBlockedStatus("UNEXPECTED");
        return;
      } catch (error) {
        setBlockedStatus(String(error).includes("not allowed") ? "blocked" : `ERROR: ${String(error)}`);
      }
      try {
        await LynxBridge.invoke("getSystemInfo");
        setDefaultStatus("UNEXPECTED");
        return;
      } catch (error) {
        setDefaultStatus(String(error).includes("not allowed") ? "blocked" : `ERROR: ${String(error)}`);
      }
      // A rejected module must not poison the next allowed call.
      const second = await LynxBridge.getSystemInfo();
      setSystemInfo(JSON.stringify(second));
    } catch (error) {
      setSystemInfo(`ERROR: ${String(error)}`);
    }
  };

  useEffect(() => {
    void verifyBridgeBoundary();
    const onPing = (data: unknown) => {
      setHostEvents(value => value + 1);
      setLastHostEvent(JSON.stringify(data) ?? "undefined");
    };
    try {
      LynxBridge.on("host-ping", onPing);
      setEventStatus("subscribed");
    } catch (error) {
      setEventStatus(`ERROR: ${String(error)}`);
    }
    return () => LynxBridge.off("host-ping", onPing);
  }, []);

  const buttonStyle = { padding: "16px", marginBottom: "12px", backgroundColor: variant === "A" ? "#14532d" : "#1e3a8a", borderRadius: "8px" };

  return (
    <view style={{
      paddingTop,
      paddingRight: 20,
      paddingBottom,
      paddingLeft: 20,
      minHeight: "100%",
      backgroundColor: "#ffffff",
      display: "flex",
      flexDirection: "column",
      width: "100%",
    }}>
      <text style={{ color: "#111827", fontSize: "24px", marginBottom: "16px" }}>Lynx runtime variant {variant}</text>
      <text style={{ color: "#111827", fontSize: "18px", marginBottom: "12px" }}>click-count: {count}</text>
      <view id="local-increment" style={buttonStyle} bindtap={() => setCount(value => value + 1)}>
        <text style={{ color: "#ffffff", fontSize: "18px" }}>Increment {variant}</text>
      </view>
      <view id="system-info" style={buttonStyle} bindtap={readSystemInfo}>
        <text style={{ color: "#ffffff", fontSize: "18px" }}>Call system.getSystemInfo</text>
      </view>
      <text style={{ color: "#111827", fontSize: "14px", marginBottom: "12px" }}>system-info: {systemInfo}</text>
      <text style={{ color: "#111827", fontSize: "16px", marginBottom: "8px" }}>host-events: {hostEvents}</text>
      <text style={{ color: "#111827", fontSize: "14px", marginBottom: "8px" }}>event-status: {eventStatus}</text>
      <text style={{ color: "#111827", fontSize: "14px" }}>host-ping: {lastHostEvent}</text>
      <image src={verificationImage} style={{ width: "48px", height: "48px", marginTop: "8px" }}
        bindload={() => setImageStatus("loaded")} binderror={() => setImageStatus("failed")} />
      <text style={{ color: "#111827", fontSize: "14px" }}>image-status: {imageStatus}</text>
      <text style={{ color: "#111827", fontSize: "14px" }}>storage-module: {blockedStatus}</text>
      <text style={{ color: "#111827", fontSize: "14px" }}>default-module: {defaultStatus}</text>
    </view>
  );
}
