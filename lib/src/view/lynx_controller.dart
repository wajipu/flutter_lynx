import "package:flutter/services.dart";

/// Controller for interacting with a specific [LynxView] instance.
class LynxController {
  final int viewId;
  final MethodChannel _channel;
  bool _disposed = false;

  LynxController(this.viewId)
      : _channel = MethodChannel("io.github.wajipu.flutter_lynx/lynx_view_$viewId");

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

  /// 直喂模板内容加载，不经本地 bundle 文件与缓存链路。
  ///
  /// 对齐官方 `LynxView.loadTemplate`（bytes 直喂引擎）：
  /// 原生把 [source] 按 UTF-8 编成 bytes 后走与文件链路相同的渲染入口
  /// （Android `renderTemplateWithBaseUrl` / iOS `loadTemplate:withURL:initData:`），
  /// 因此内容要求一致——必须是引擎可执行的模板产物，[source] 大小上限同为 10 MiB。
  Future<void> loadFromSource(String source,
      {Map<String, dynamic>? initialData}) async {
    _ensureActive();
    await _channel.invokeMethod("loadFromSource", {
      "source": source,
      if (initialData != null) "initialData": initialData,
    });
  }

  /// 直喂模板 bytes，语义同 [loadFromSource]。
  ///
  /// rspeedy/tasm 编译出的 `main.lynx.bundle` 是二进制模板，不经 UTF-8 无损转换，
  /// 这类内容必须走本入口；`loadFromSource` 只用于文本型模板内容。
  Future<void> loadFromTemplateBytes(Uint8List bytes,
      {Map<String, dynamic>? initialData}) async {
    _ensureActive();
    await _channel.invokeMethod("loadFromSource", {
      "templateBytes": bytes,
      if (initialData != null) "initialData": initialData,
    });
  }

  void _ensureActive() {
    if (_disposed) throw StateError("LynxController has been disposed");
  }

  /// 原生视图由Flutter的PlatformView生命周期销毁；旧控制器不能继续发消息。
  void dispose() => _disposed = true;
}
