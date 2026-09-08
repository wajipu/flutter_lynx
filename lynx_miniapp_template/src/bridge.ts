/**
 * Type-safe JSBridge client SDK for Lynx Mini Programs communicating with Flutter host (KManager).
 */

declare const lynx: any;

export interface BridgeResponse<T = any> {
  callId: string;
  code: number;
  message: string;
  data?: T;
}

export interface SystemInfo {
  platform: string;
  osVersion: string;
  screenWidth: number;
  screenHeight: number;
  pixelRatio: number;
  language: string;
}

export interface UserInfo {
  userId?: string;
  userName?: string;
  phone?: string;
  token?: string;
  roles?: string[];
  [key: string]: any;
}

export interface RequestOptions {
  url: string;
  method?: "GET" | "POST" | "PUT" | "DELETE";
  data?: any;
  headers?: Record<string, string>;
}

export class LynxBridge {
  private static callbackMap = new Map<string, (res: BridgeResponse) => void>();
  private static eventListeners = new Map<string, Set<(data: any) => void>>();

  static {
    // Listen for custom events dispatched from Flutter Host
    if (typeof lynx !== "undefined" && lynx.getJSModule) {
      try {
        const globalEmitter = lynx.getJSModule("GlobalEventEmitter");
        if (globalEmitter && globalEmitter.addListener) {
          globalEmitter.addListener("onFlutterEvent", (event: { name: string; data: any }) => {
            const listeners = LynxBridge.eventListeners.get(event.name);
            if (listeners) {
              listeners.forEach((cb) => cb(event.data));
            }
          });
        }
      } catch (_) {}
    }
  }

  /**
   * Low-level invoke method
   */
  static invoke<T = any>(method: string, params: Record<string, any> = {}, module = "default"): Promise<T> {
    const callId = "call_" + Date.now() + "_" + Math.floor(Math.random() * 10000);

    return new Promise((resolve, reject) => {
      LynxBridge.callbackMap.set(callId, (res: BridgeResponse) => {
        if (res.code === 0) {
          resolve(res.data as T);
        } else {
          reject(new Error(res.message || "Bridge invocation failed"));
        }
      });

      // Try invoking through Lynx native module if available
      try {
        if (typeof lynx !== "undefined" && lynx.getJSModule) {
          const bridgeModule = lynx.getJSModule("LynxBridge");
          if (bridgeModule && bridgeModule.call) {
            bridgeModule.call(module, method, params, callId, (res: BridgeResponse) => {
              const cb = LynxBridge.callbackMap.get(callId);
              if (cb) {
                LynxBridge.callbackMap.delete(callId);
                cb(res);
              }
            });
            return;
          }
        }
      } catch (_) {}

      // Fallback: mock response for local testing
      console.warn(`[LynxBridge] Native module not detected. Using local fallback for ${module}.${method}`);
      setTimeout(() => {
        const mockData = LynxBridge.getMockResponse(method, params);
        const cb = LynxBridge.callbackMap.get(callId);
        if (cb) {
          LynxBridge.callbackMap.delete(callId);
          cb({ callId, code: 0, message: "ok", data: mockData });
        }
      }, 100);
    });
  }

  // --- Convenience Mini-Program APIs ---

  static getSystemInfo(): Promise<SystemInfo> {
    return LynxBridge.invoke<SystemInfo>("getSystemInfo", {}, "system");
  }

  static getUserInfo(): Promise<UserInfo> {
    return LynxBridge.invoke<UserInfo>("getUserInfo", {}, "user");
  }

  static scanQRCode(): Promise<{ code: string }> {
    return LynxBridge.invoke<{ code: string }>("scanQRCode", {}, "scanner");
  }

  static request<T = any>(options: RequestOptions): Promise<T> {
    return LynxBridge.invoke<T>("request", options, "network");
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
    if (!LynxBridge.eventListeners.has(eventName)) {
      LynxBridge.eventListeners.set(eventName, new Set());
    }
    LynxBridge.eventListeners.get(eventName)!.add(callback);
  }

  static off(eventName: string, callback: (data: any) => void): void {
    LynxBridge.eventListeners.get(eventName)?.delete(callback);
  }

  private static getMockResponse(method: string, params: any): any {
    switch (method) {
      case "getSystemInfo":
        return {
          platform: "iOS",
          osVersion: "17.4",
          screenWidth: 390,
          screenHeight: 844,
          pixelRatio: 3,
          language: "zh_CN",
        };
      case "getUserInfo":
        return {
          userId: "10086",
          userName: "管理员 (Admin)",
          phone: "13800138000",
          token: "mock_jwt_token_kmanager_2026",
          roles: ["admin", "store_manager"],
        };
      case "scanQRCode":
        return { code: "https://kmanager.example.com/desk/001" };
      case "request":
        return { success: true, message: "Mock response for " + params.url };
      default:
        return {};
    }
  }
}
