import { useState } from "@lynx-js/react";
import { useInitData } from "@lynx-js/react";
import { LynxBridge } from "./bridge";
import "./confirm-card.css";

function readText(value: unknown, fallback = ""): string {
  return typeof value === "string" && value.length > 0 ? value : fallback;
}

function readDanger(value: unknown): boolean {
  // 过桥后 bool 常变成 1/0，卡片按数字判断，不用 === true。
  return value === true || value === 1 || value === "1";
}

/** 确认动作的回传形状：宿主 showConfirmCardSheet 用它 resolve Future。 */
export interface ConfirmCardResult {
  action: "confirm" | "cancel";
}

/**
 * 确认卡片（小柯助手③）：模板随 App 版本内置，宿主经 templateBytes 直喂加载，
 * 不经云端打包/审核下发链。文案全部由宿主 initData 注入（宿主负责三语），
 * 卡片只负责渲染与回传，回传通道为 ui.confirmResult Bridge 调用。
 */
export function ConfirmCard() {
  const initData = useInitData() as {
    title?: string;
    message?: string;
    confirmText?: string;
    cancelText?: string;
    danger?: unknown;
  };
  const [answered, setAnswered] = useState(false);

  const title = readText(initData?.title, "确认操作");
  const message = readText(initData?.message);
  const confirmText = readText(initData?.confirmText, "确认");
  const cancelText = readText(initData?.cancelText, "取消");
  const danger = readDanger(initData?.danger);

  const answer = (action: "confirm" | "cancel") => {
    if (answered) return;
    // 先置位再上报：bridge 回调可能晚到，避免连点发出两次结果。
    setAnswered(true);
    LynxBridge.invoke<ConfirmCardResult>(
      "confirmResult",
      { action },
      "ui",
    ).catch(() => {
      // 上报失败恢复可点，宿主未收到结果时用户仍可重试或划掉半屏。
      setAnswered(false);
    });
  };

  return (
    <view class="confirm-card">
      <view class="confirm-card-body">
        <text class="confirm-card-title">{title}</text>
        {message.length > 0 && (
          <text class="confirm-card-message">{message}</text>
        )}
      </view>
      <view class="confirm-card-actions">
        <view
          class={
            "confirm-card-btn confirm-card-btn-secondary" +
            (answered ? " confirm-card-btn-disabled" : "")
          }
          bindtap={() => answer("cancel")}
        >
          <text class="confirm-card-btn-secondary-text">{cancelText}</text>
        </view>
        <view
          class={
            "confirm-card-btn " +
            (danger ? "confirm-card-btn-danger" : "confirm-card-btn-primary") +
            (answered ? " confirm-card-btn-disabled" : "")
          }
          bindtap={() => answer("confirm")}
        >
          <text class="confirm-card-btn-primary-text">{confirmText}</text>
        </view>
      </view>
    </view>
  );
}
