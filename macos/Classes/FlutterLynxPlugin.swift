import Cocoa
import FlutterMacOS

public class FlutterLynxPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let pluginChannel = FlutterMethodChannel(
      name: "com.kmanager.flutter_lynx/plugin",
      binaryMessenger: registrar.messenger
    )
    let instance = FlutterLynxPlugin()
    registrar.addMethodCallDelegate(instance, channel: pluginChannel)

    let bridgeChannel = FlutterMethodChannel(
      name: "com.kmanager.flutter_lynx/bridge",
      binaryMessenger: registrar.messenger
    )
    registrar.addMethodCallDelegate(instance, channel: bridgeChannel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("macOS " + ProcessInfo.processInfo.operatingSystemVersionString)
    case "sendCustomEvent":
      result(FlutterError(
        code: "lynx_native_unavailable",
        message: "Official Lynx 3.2 has no macOS engine; desktop support starts at Lynx 3.7",
        details: nil
      ))
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
