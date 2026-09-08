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
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
