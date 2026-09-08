import "../lynx_bridge_handler.dart";
import "../lynx_bridge_request.dart";
import "../lynx_bridge_response.dart";

typedef NavigationHandler = Future<bool> Function(String action, String url, Map<String, dynamic> params);

/// Built-in bridge handler for mini-program navigation.
class RouterBridgeHandler implements LynxBridgeHandler {
  static const String _module = "router";
  NavigationHandler? onNavigate;

  RouterBridgeHandler({this.onNavigate});

  @override
  bool canHandle(String module, String method) {
    if (module == _module || module == "default") {
      return [
        "navigateTo",
        "navigateBack",
        "redirectTo",
        "reLaunch",
      ].contains(method);
    }
    return false;
  }

  @override
  Future<LynxBridgeResponse> handle(LynxBridgeRequest request) async {
    final url = request.params["url"]?.toString() ?? "";
    bool ok = true;
    if (onNavigate != null) {
      ok = await onNavigate!(request.method, url, request.params);
    }
    if (ok) {
      return LynxBridgeResponse.success(callId: request.callId);
    } else {
      return LynxBridgeResponse.error(
        callId: request.callId,
        code: 500,
        message: "Navigation failed for ${request.method}",
      );
    }
  }
}
