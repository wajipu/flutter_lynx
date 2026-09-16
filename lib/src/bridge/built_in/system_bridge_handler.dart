import "dart:io";
import "dart:ui" as ui;
import "package:flutter/services.dart";
import "../../host/lynx_host_metrics.dart";
import "../lynx_bridge_handler.dart";
import "../lynx_bridge_request.dart";
import "../lynx_bridge_response.dart";

/// Built-in bridge handler for system info, device metrics and vibration.
class SystemBridgeHandler implements LynxBridgeHandler {
  static const String _module = "system";

  @override
  bool canHandle(String module, String method) {
    if (module == _module || module == "default") {
      return [
        "getSystemInfo",
        "getNetworkType",
        "vibrateShort",
        "vibrateLong",
      ].contains(method);
    }
    return false;
  }

  @override
  Future<LynxBridgeResponse> handle(LynxBridgeRequest request) async {
    switch (request.method) {
      case "getSystemInfo":
        final view = ui.PlatformDispatcher.instance.views.first;
        final metrics = LynxHostMetrics.fromView(
          view,
          capsuleHasMore: true,
        );
        return LynxBridgeResponse.success(
          callId: request.callId,
          data: metrics.toSystemInfo(
            platform: Platform.operatingSystem,
            osVersion: Platform.operatingSystemVersion,
            language: Platform.localeName,
          ),
        );

      case "getNetworkType":
        // 没有网络状态依赖时只能返回未知，禁止把未探测的网络伪装成Wi-Fi。
        return LynxBridgeResponse.success(
          callId: request.callId,
          data: {"networkType": "unknown"},
        );

      case "vibrateShort":
        await HapticFeedback.selectionClick();
        return LynxBridgeResponse.success(callId: request.callId);

      case "vibrateLong":
        await HapticFeedback.heavyImpact();
        return LynxBridgeResponse.success(callId: request.callId);

      default:
        return LynxBridgeResponse.error(
          callId: request.callId,
          code: 404,
          message:
              "Method ${request.method} not supported in SystemBridgeHandler",
        );
    }
  }
}
