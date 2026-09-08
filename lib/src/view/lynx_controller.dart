import "package:flutter/services.dart";

/// Controller for interacting with a specific [LynxView] instance.
class LynxController {
  final int viewId;
  final MethodChannel _channel;

  LynxController(this.viewId)
      : _channel = MethodChannel("com.kmanager.flutter_lynx/lynx_view_$viewId");

  /// Update the template data dynamically.
  Future<void> updateData(Map<String, dynamic> data) async {
    try {
      await _channel.invokeMethod("updateData", data);
    } catch (_) {}
  }

  /// Dispatch a custom event to the Lynx template runtime.
  Future<void> sendCustomEvent(String eventName, Map<String, dynamic> data) async {
    try {
      await _channel.invokeMethod("sendCustomEvent", {
        "eventName": eventName,
        "data": data,
      });
    } catch (_) {}
  }

  /// Reload the LynxView with optional new URL or initialData.
  Future<void> reload({String? newUrl, Map<String, dynamic>? newInitialData}) async {
    try {
      await _channel.invokeMethod("reload", {
        if (newUrl != null) "url": newUrl,
        if (newInitialData != null) "initialData": newInitialData,
      });
    } catch (_) {}
  }

  void dispose() {}
}
