import "package:flutter/services.dart";

/// Controller for interacting with a specific [LynxView] instance.
class LynxController {
  final int viewId;
  final MethodChannel _channel;
  bool _disposed = false;

  LynxController(this.viewId)
      : _channel = MethodChannel("com.kmanager.flutter_lynx/lynx_view_$viewId");

  /// Update the template data dynamically.
  Future<void> updateData(Map<String, dynamic> data) async {
    _ensureActive();
    await _channel.invokeMethod("updateData", data);
  }

  /// Dispatch a custom event to the Lynx template runtime.
  Future<void> sendCustomEvent(
      String eventName, Map<String, dynamic> data) async {
    _ensureActive();
    await _channel.invokeMethod("sendCustomEvent", {
      "eventName": eventName,
      "data": data,
    });
  }

  /// Reload the LynxView with optional new URL or initialData.
  Future<void> reload(
      {String? newUrl, Map<String, dynamic>? newInitialData}) async {
    _ensureActive();
    await _channel.invokeMethod("reload", {
      if (newUrl != null) "url": newUrl,
      if (newInitialData != null) "initialData": newInitialData,
    });
  }

  void _ensureActive() {
    if (_disposed) throw StateError("LynxController has been disposed");
  }

  /// 原生视图由Flutter的PlatformView生命周期销毁；旧控制器不能继续发消息。
  void dispose() => _disposed = true;
}
