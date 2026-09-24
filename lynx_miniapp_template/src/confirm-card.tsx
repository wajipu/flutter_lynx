import { useState } from "@lynx-js/react";
import { useInitData } from "@lynx-js/react";
import { LynxBridge } from "./bridge";

/** 确认动作的回传形状：宿主 showConfirmCardSheet 用它 resolve Future。 */
export interface ConfirmCardResult {
  action: "confirm" | "cancel";
}

// 文案直接写在代码里：小柯输出什么代码就渲染什么内容。
const title = "确认补货 25 件？";
const message = "商品：冰鲜柠檬茶（大杯）\n当前库存 3，低于阈值 10";
const confirmText = "确认补货";
const cancelText = "再想想";
const danger = false;

// 样式全部内联，对齐 runtime-validation 页（已在真机引擎上验证过的写法）。
const containerStyle = {
  width: "100%",
  minHeight: "100%",
  backgroundColor: "#ffffff",
  display: "flex",
  flexDirection: "column",
  padding: "20px 16px 16px 16px",
};

const titleStyle = {
  color: "#1f2329",
  fontSize: "17px",
  fontWeight: "600",
};

const messageStyle = {
  color: "#646a73",
  fontSize: "14px",
  marginTop: "8px",
};

const actionsStyle = {
  display: "flex",
  flexDirection: "row",
  marginTop: "20px",
};

function buttonStyle(
  background: string,
  answered: boolean,
  side: "left" | "right",
) {
  return {
    flex: 1,
    height: "44px",
    display: "flex",
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "center",
    borderRadius: "10px",
    backgroundColor: background,
    marginLeft: side === "right" ? "6px" : "0px",
    marginRight: side === "left" ? "6px" : "0px",
    opacity: answered ? 0.5 : 1,
  };
}

const primaryTextStyle = {
  fontSize: "16px",
  fontWeight: "600",
  color: "#ffffff",
};

const secondaryTextStyle = {
  fontSize: "16px",
  fontWeight: "600",
  color: "#4e5969",
};

/**
 * 确认卡片（小柯助手③）：模板随 App 版本内置，宿主经 templateBytes 直喂加载。
 * 内容自包含在本代码里；宿主参数（token/初始化数据）经 initData 注入，
 * 回传时随 ui.confirmResult 透传，宿主可校验来源。
 */
export function ConfirmCard() {
  const initData = useInitData() as { token?: string } | undefined;
  const [answered, setAnswered] = useState(false);

  const answer = (action: "confirm" | "cancel") => {
    if (answered) return;
    // 先置位再上报：bridge 回调可能晚到，避免连点发出两次结果。
    setAnswered(true);
    // 宿主经 initData 注入的 token 随结果回传，宿主端可校验来源与登录态。
    LynxBridge.invoke<ConfirmCardResult>(
      "confirmResult",
      { action, token: initData?.token ?? "" },
      "ui",
    ).catch(() => {
      // 上报失败恢复可点，宿主未收到结果时用户仍可重试或划掉半屏。
      setAnswered(false);
    });
  };

  return (
    <view style={containerStyle}>
      <text style={titleStyle}>{title}</text>
      <text style={messageStyle}>{message}</text>
      <view style={actionsStyle}>
        <view
          style={buttonStyle("#f2f3f5", answered, "left")}
          bindtap={() => answer("cancel")}
        >
          <text style={secondaryTextStyle}>{cancelText}</text>
        </view>
        <view
          style={buttonStyle(danger ? "#ff4d4f" : "#1677ff", answered, "right")}
          bindtap={() => answer("confirm")}
        >
          <text style={primaryTextStyle}>{confirmText}</text>
        </view>
      </view>
    </view>
  );
}
