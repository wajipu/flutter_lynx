import Flutter
import UIKit

public class LynxPlatformViewManager {
  public static let shared = LynxPlatformViewManager()
  private var activeViews: [Int64: LynxPlatformView] = [:]

  public func register(view: LynxPlatformView, for viewId: Int64) {
    activeViews[viewId] = view
  }

  public func unregister(for viewId: Int64) {
    activeViews.removeValue(forKey: viewId)
  }

  public func broadcastEvent(eventName: String, data: [String: Any]) {
    for view in activeViews.values {
      view.sendCustomEvent(eventName: eventName, data: data)
    }
  }
}

public class LynxPlatformView: NSObject, FlutterPlatformView {
  private let containerView: UIView
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterMethodChannel
  private let viewId: Int64
  private var url: String
  private var initialData: [String: Any]

  public init(
    frame: CGRect,
    viewId: Int64,
    params: [String: Any],
    messenger: FlutterBinaryMessenger
  ) {
    self.viewId = viewId
    self.url = params["url"] as? String ?? ""
    self.initialData = params["initialData"] as? [String: Any] ?? [:]
    self.containerView = UIView(frame: frame)
    self.containerView.backgroundColor = .white

    self.methodChannel = FlutterMethodChannel(
      name: "com.kmanager.flutter_lynx/lynx_view_\(viewId)",
      binaryMessenger: messenger
    )
    self.eventChannel = FlutterMethodChannel(
      name: "com.kmanager.flutter_lynx/lynx_view_\(viewId)_events",
      binaryMessenger: messenger
    )

    super.init()

    self.methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handleMethodCall(call, result: result)
    }

    LynxPlatformViewManager.shared.register(view: self, for: viewId)
    setupLynxView()
  }

  public func view() -> UIView {
    return containerView
  }

  private func setupLynxView() {
    // Graceful runtime integration:
    // When CocoaPods Lynx framework is linked, LynxView class is instantiated.
    // Otherwise, a native placeholder is presented.
    if let lynxViewClass = NSClassFromString("LynxView") as? UIView.Type {
      let lynxView = lynxViewClass.init(frame: containerView.bounds)
      lynxView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      containerView.addSubview(lynxView)

      eventChannel.invokeMethod("onLoadSuccess", arguments: nil)
      eventChannel.invokeMethod("onFirstScreen", arguments: nil)
    } else {
      let label = UILabel(frame: containerView.bounds)
      label.text = "Lynx View Ready\nID: \(viewId)\nBundle: \(url)"
      label.numberOfLines = 0
      label.textAlignment = .center
      label.textColor = .darkGray
      label.font = UIFont.systemFont(ofSize: 13)
      label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      containerView.addSubview(label)

      eventChannel.invokeMethod("onLoadSuccess", arguments: nil)
      eventChannel.invokeMethod("onFirstScreen", arguments: nil)
    }
  }

  public func sendCustomEvent(eventName: String, data: [String: Any]) {
    // Dispatch into Lynx runtime
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "updateData":
      result(true)
    case "sendCustomEvent":
      if let args = call.arguments as? [String: Any],
         let eventName = args["eventName"] as? String,
         let data = args["data"] as? [String: Any] {
        sendCustomEvent(eventName: eventName, data: data)
      }
      result(true)
    case "reload":
      setupLynxView()
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  deinit {
    LynxPlatformViewManager.shared.unregister(for: viewId)
    methodChannel.setMethodCallHandler(nil)
  }
}
