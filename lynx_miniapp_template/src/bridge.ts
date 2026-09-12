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
