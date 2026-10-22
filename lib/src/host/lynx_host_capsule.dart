import "package:flutter/foundation.dart";
import "package:flutter/services.dart";

/// 全屏小程序胶囊的 Dart 开关。
///
/// 可见胶囊由原生画在窗口层，不进 Flutter 树，也不挂在 Lynx PlatformView 上。
/// 这里只负责显示/隐藏、主题和 more/close 回调。
class LynxHostCapsule {
  LynxHostCapsule._();

  static const MethodChannel _channel =
      MethodChannel("io.github.wajipu.flutter_lynx/host_capsule");

  static VoidCallback? _onMore;
  static VoidCallback? _onClose;
  static bool _listening = false;

  static bool get _supported =>
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;

  /// 进入全屏小程序页时挂上窗口层胶囊。
  static Future<void> show({
    required bool dark,
    required VoidCallback onMore,
    required VoidCallback onClose,
  }) async {
    if (!_supported) {
      return;
    }
    _onMore = onMore;
    _onClose = onClose;
    _ensureListener();
    try {
      await _channel.invokeMethod<void>("show", <String, int>{
        "dark": dark ? 1 : 0,
      });
    } on MissingPluginException {
      return;
    }
  }

  /// 主题变化时只改毛玻璃，不重建窗口层。
  static Future<void> setDark(bool dark) async {
    if (!_supported) {
      return;
    }
    try {
      await _channel.invokeMethod<void>("setDark", <String, int>{
        "dark": dark ? 1 : 0,
      });
    } on MissingPluginException {
      return;
    }
  }

  /// 离开全屏小程序页时摘掉。
  static Future<void> hide() async {
    _onMore = null;
    _onClose = null;
    if (!_supported) {
      return;
    }
    try {
      await _channel.invokeMethod<void>("hide");
    } on MissingPluginException {
      return;
    }
  }

  static void _ensureListener() {
    if (_listening) {
      return;
    }
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == "onMore") {
        _onMore?.call();
        return;
      }
      if (call.method == "onClose") {
        _onClose?.call();
      }
    });
  }
}
