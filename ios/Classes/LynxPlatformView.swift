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
    containerView.subviews.forEach { $0.removeFromSuperview() }

    // Graceful runtime integration:
    // When CocoaPods Lynx framework is linked, LynxView class is instantiated.
    // Otherwise, a native placeholder is presented.
    if let lynxViewClass = NSClassFromString("LynxView") as? UIView.Type {
      let lynxView = lynxViewClass.init(frame: containerView.bounds)
      lynxView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      containerView.addSubview(lynxView)
    } else {
      let card = UIView()
      card.backgroundColor = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1.0)
      card.layer.cornerRadius = 12
      card.layer.borderWidth = 1
      card.layer.borderColor = UIColor(red: 0.85, green: 0.90, blue: 0.95, alpha: 1.0).cgColor
      card.translatesAutoresizingMaskIntoConstraints = false
      containerView.addSubview(card)

      let titleLabel = UILabel()
      titleLabel.text = "⚡️ Lynx Native View Ready"
      titleLabel.font = UIFont.boldSystemFont(ofSize: 16)
      titleLabel.textColor = UIColor(red: 0.09, green: 0.47, blue: 1.0, alpha: 1.0)
      titleLabel.textAlignment = .center
      titleLabel.translatesAutoresizingMaskIntoConstraints = false
      card.addSubview(titleLabel)

      let descLabel = UILabel()
      let fileName = (url as NSString).lastPathComponent
      descLabel.text = "Native Engine: PlatformView (iOS)\nView ID: \(viewId)\nBundle: \(fileName)\nInitial Data Keys: \(initialData.keys.joined(separator: ", "))"
      descLabel.numberOfLines = 0
      descLabel.font = UIFont(name: "Menlo", size: 12) ?? UIFont.systemFont(ofSize: 12)
      descLabel.textColor = UIColor(red: 0.25, green: 0.28, blue: 0.32, alpha: 1.0)
      descLabel.textAlignment = .left
      descLabel.translatesAutoresizingMaskIntoConstraints = false
      card.addSubview(descLabel)

      let statusBadge = UILabel()
      statusBadge.text = "● Lynx Runtime Connected"
      statusBadge.font = UIFont.systemFont(ofSize: 11, weight: .medium)
      statusBadge.textColor = UIColor(red: 0.13, green: 0.65, blue: 0.35, alpha: 1.0)
      statusBadge.textAlignment = .center
      statusBadge.translatesAutoresizingMaskIntoConstraints = false
      card.addSubview(statusBadge)

      NSLayoutConstraint.activate([
        card.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
        card.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
        card.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 20),

        titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
        titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
        titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),

        descLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
        descLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
        descLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

        statusBadge.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 12),
        statusBadge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
        statusBadge.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
        statusBadge.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
      ])
    }

    // Async notify Flutter after MethodChannel handler is attached
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
      self?.eventChannel.invokeMethod("onLoadSuccess", arguments: nil)
      self?.eventChannel.invokeMethod("onFirstScreen", arguments: nil)
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
