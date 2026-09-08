import "dart:io";
import "dart:ui" as ui;
import "package:flutter/services.dart";
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
        final physicalSize = view.physicalSize;
        final pixelRatio = view.devicePixelRatio;
        final screenWidth = physicalSize.width / pixelRatio;
        final screenHeight = physicalSize.height / pixelRatio;

        return LynxBridgeResponse.success(
          callId: request.callId,
          data: {
            "platform": Platform.operatingSystem,
            "osVersion": Platform.operatingSystemVersion,
            "screenWidth": screenWidth,
            "screenHeight": screenHeight,
            "pixelRatio": pixelRatio,
            "language": Platform.localeName,
          },
        );

      case "getNetworkType":
        // Fallback indicator
        return LynxBridgeResponse.success(
          callId: request.callId,
          data: {"networkType": "wifi"},
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
          message: "Method ${request.method} not supported in SystemBridgeHandler",
        );
    }
  }
}
