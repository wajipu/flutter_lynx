/**
 * Type-safe JSBridge client SDK for Lynx Mini Programs communicating with Flutter host (KManager).
 */

interface GlobalEventEmitter {
  addListener(eventName: string, listener: (event: FlutterEvent) => void): void;
  removeListener(eventName: string, listener: (event: FlutterEvent) => void): void;
}

interface FlutterEvent {
  name: string;
  data: any;
}

declare const lynx: {
  getJSModule?: (name: "GlobalEventEmitter") => GlobalEventEmitter;
};

declare const NativeModules: {
  LynxBridge?: {
    call(module: string, method: string, params: Record<string, any>, callId: string,
      callback: (response: BridgeResponse) => void): void;
  };
};

export interface BridgeResponse<T = any> {
  callId: string;
  code: number;
  message: string;
  data?: T;
}

export interface HostSafeArea {
  top: number;
  bottom: number;
  left: number;
  right: number;
}

export interface HostMenuButton {
  width: number;
  height: number;
  top: number;
  left: number;
  right: number;
  bottom: number;
}

export interface SystemInfo {
  platform: string;
  osVersion: string;
  screenWidth: number;
  screenHeight: number;
  pixelRatio: number;
  language: string;
  statusBarHeight: number;
  safeArea: HostSafeArea;
  menuButton: HostMenuButton;
}

export interface SystemInfo {
  platform: string;
  osVersion: string;
  screenWidth: number;
  screenHeight: number;
  pixelRatio: number;
  language: string;
  statusBarHeight: number;
  safeArea: HostSafeArea;
  menuButton: HostMenuButton;
}

// --- data 模块（koklam-docs features/merchant-mobile-app/13）---
//
// 宿主代调 Cloud 并把 `R` 解包为 `{code, msg, data}` 信封交给 JS；
// 码表沿用 Cloud R：200 成功、401 会话失效（宿主引导重登）、其余非 200 一律失败态。
// `msg` 已由宿主/Cloud 按 content-language 解析，bundle 不自行翻译错误文案。

export interface DataEnvelope<T> {
  code: number;
  msg: string;
  data: T | null;
}

/** data.inventoryAlertList 返回项（13 号文 §10.1 暂定形状，以 Cloud 实现为准）。 */
export interface InventoryAlertItem {
  /** Cloud 的 Long 可能序列化为字符串，两种形态都接受。 */
  productId: number | string;
  specId: number | string | null;
  /** 商品/规格名，宿主按请求语言解析后的单语言展示字段。 */
  name: string;
  quantity: number;
  threshold: number;
  unit: string | null;
  /** 预警判定时间。 */
  detectedAt: string;
}

/** data.paymentStatsOverview 返回（Cloud GET /system/payment/stats/overview VO）。 */
export interface PaymentStatsOverview {
  date: string;
  orderCount: number;
  totalAmount: number | null;
  discountAmount: number | null;
  /** 本次抵扣金额之和，不含找零，不是净营收；卡面命名「收款合计」。 */
  paidAmount: number;
  depositAmount: number | null;
  totalRevenue: number;
  cashAmount: number;
  creditAmount: number;
  averageAmount: number;
}

export class LynxBridge {
  private static nextCallId = 0;
  private static eventListeners = new Map<string, Set<(data: any) => void>>();
  private static globalEmitter: GlobalEventEmitter | undefined;

  private static handleFlutterEvent(event: FlutterEvent): void {
    if (!event || typeof event.name !== "string") return;
    LynxBridge.eventListeners.get(event.name)?.forEach(callback => callback(event.data));
  }

  /**
   * Low-level invoke method
   */
  static invoke<T = any>(method: string, params: Record<string, any> = {}, module = "default"): Promise<T> {
    return new Promise((resolve, reject) => {
      const nativeBridge = typeof NativeModules === "undefined" ? undefined : NativeModules.LynxBridge;
      if (!nativeBridge || typeof nativeBridge.call !== "function") {
        reject(new Error("NativeModules.LynxBridge is unavailable"));
        return;
      }
      const callId = `call_${Date.now()}_${++LynxBridge.nextCallId}`;
      // Each invocation owns its native callback; no mock reply or shared pending-response map.
      nativeBridge.call(module, method, params, callId, response => {
        if (!response || response.callId !== callId || typeof response.code !== "number") {
          reject(new Error("Invalid LynxBridge response"));
        } else if (response.code === 0) {
          resolve(response.data as T);
        } else {
          reject(new Error(response.message || `Bridge invocation failed: ${response.code}`));
        }
      });
    });
  }

  // --- Convenience Mini-Program APIs ---

  static getSystemInfo(): Promise<SystemInfo> {
    return LynxBridge.invoke<SystemInfo>("getSystemInfo", {}, "system");
  }

  static scanQRCode(): Promise<{ code: string }> {
    return LynxBridge.invoke<{ code: string }>("scanQRCode", {}, "scanner");
  }

  // --- data 模块白名单方法（13 号文 §4 第一批；新增必须先补文档） ---

  /**
   * 业务数据统一走 data 模块：宿主把 Cloud R 信封放进 data 返回。
   * 信封 code 非 200 不是传输失败，由调用方按三态约定渲染 empty/error。
   */
  static invokeData<T>(method: string, params: Record<string, any> = {}): Promise<DataEnvelope<T>> {
    return LynxBridge.invoke<DataEnvelope<T>>(method, params, "data");
  }

  /** 未读消息总数：`{}` → `{total}`。 */
  static messageUnreadTotal(): Promise<DataEnvelope<{ total: number }>> {
    return LynxBridge.invokeData<{ total: number }>("messageUnreadTotal");
  }

  /** 库存预警列表（当前门店 top 20）：`{}` → `{list}`。 */
  static inventoryAlertList(): Promise<DataEnvelope<{ list: InventoryAlertItem[] }>> {
    return LynxBridge.invokeData<{ list: InventoryAlertItem[] }>("inventoryAlertList");
  }

  /** 收款概览：`{}` → Cloud 支付统计 VO。 */
  static paymentStatsOverview(): Promise<DataEnvelope<PaymentStatsOverview>> {
    return LynxBridge.invokeData<PaymentStatsOverview>("paymentStatsOverview");
  }

  static showToast(title: string, icon: "success" | "error" | "none" = "none", duration = 1500): Promise<void> {
    return LynxBridge.invoke<void>("showToast", { title, icon, duration }, "ui");
  }

  static showModal(title: string, content: string, showCancel = true): Promise<{ confirm: boolean; cancel: boolean }> {
    return LynxBridge.invoke<{ confirm: boolean; cancel: boolean }>("showModal", { title, content, showCancel }, "ui");
  }

  static setStorage(key: string, data: any): Promise<void> {
    return LynxBridge.invoke<void>("setStorage", { key, data }, "storage");
  }

  static getStorage<T = any>(key: string): Promise<{ data: T }> {
    return LynxBridge.invoke<{ data: T }>("getStorage", { key }, "storage");
  }

  static on(eventName: string, callback: (data: any) => void): void {
    // GlobalEventEmitter exists only on the background thread. Call on() from useEffect or an event handler.
    if (!LynxBridge.globalEmitter) {
      if (typeof lynx === "undefined" || typeof lynx.getJSModule !== "function") {
        throw new Error("Lynx GlobalEventEmitter is unavailable on this thread");
      }
      const emitter = lynx.getJSModule("GlobalEventEmitter");
      if (!emitter || typeof emitter.addListener !== "function" || typeof emitter.removeListener !== "function") {
        throw new Error("Lynx GlobalEventEmitter is unavailable");
      }
      emitter.addListener("onFlutterEvent", LynxBridge.handleFlutterEvent);
      LynxBridge.globalEmitter = emitter;
    }
    if (!LynxBridge.eventListeners.has(eventName)) {
      LynxBridge.eventListeners.set(eventName, new Set());
    }
    LynxBridge.eventListeners.get(eventName)!.add(callback);
  }

  static off(eventName: string, callback: (data: any) => void): void {
    const listeners = LynxBridge.eventListeners.get(eventName);
    listeners?.delete(callback);
    if (listeners?.size === 0) LynxBridge.eventListeners.delete(eventName);
    if (LynxBridge.eventListeners.size === 0 && LynxBridge.globalEmitter) {
      LynxBridge.globalEmitter.removeListener("onFlutterEvent", LynxBridge.handleFlutterEvent);
      LynxBridge.globalEmitter = undefined;
    }
  }
}
