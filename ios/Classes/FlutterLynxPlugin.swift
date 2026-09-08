import Flutter
import UIKit

public class FlutterLynxPlugin: NSObject, FlutterPlugin {
  public static var bridgeChannel: FlutterMethodChannel?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let pluginChannel = FlutterMethodChannel(
      name: "com.kmanager.flutter_lynx/plugin",
      binaryMessenger: registrar.messenger()
    )
    let instance = FlutterLynxPlugin()
    registrar.addMethodCallDelegate(instance, channel: pluginChannel)

    bridgeChannel = FlutterMethodChannel(
      name: "com.kmanager.flutter_lynx/bridge",
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: bridgeChannel!)

    // Register Lynx Platform View Factory
    let factory = LynxPlatformViewFactory(messenger: registrar.messenger())
    registrar.register(factory, withId: "com.kmanager.flutter_lynx/lynx_view")
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)
    case "sendCustomEvent":
      guard let args = call.arguments as? [String: Any],
            let eventName = args["eventName"] as? String,
            let data = args["data"] as? [String: Any] else {
        result(false)
        return
      }
      LynxPlatformViewManager.shared.broadcastEvent(eventName: eventName, data: data)
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public static func callBridge(
    module: String,
    method: String,
    params: [String: Any],
    callId: String,
    completion: @escaping ([String: Any]) -> Void
  ) {
    guard let channel = bridgeChannel else {
      completion([
        "callId": callId,
        "code": 500,
        "message": "Bridge channel not initialized on iOS"
      ])
      return
    }

    let request: [String: Any] = [
      "callId": callId,
      "module": module,
      "method": method,
      "params": params
    ]

    channel.invokeMethod("callBridge", arguments: request) { reply in
      if let dict = reply as? [String: Any] {
        completion(dict)
      } else {
        completion([
          "callId": callId,
          "code": 0,
          "message": "ok"
        ])
      }
    }
  }
}
