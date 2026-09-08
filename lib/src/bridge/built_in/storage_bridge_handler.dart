import "../lynx_bridge_handler.dart";
import "../lynx_bridge_request.dart";
import "../lynx_bridge_response.dart";

/// Built-in bridge handler for mini-program key-value storage.
class StorageBridgeHandler implements LynxBridgeHandler {
  static const String _module = "storage";
  final Map<String, dynamic> _memoryCache = {};

  @override
  bool canHandle(String module, String method) {
    if (module == _module || module == "default") {
      return [
        "setStorage",
        "getStorage",
        "removeStorage",
        "clearStorage",
        "getStorageInfo",
      ].contains(method);
    }
    return false;
  }

  @override
  Future<LynxBridgeResponse> handle(LynxBridgeRequest request) async {
    final params = request.params;
    switch (request.method) {
      case "setStorage":
        final key = params["key"]?.toString();
        if (key == null || key.isEmpty) {
          return LynxBridgeResponse.error(
            callId: request.callId,
            code: 400,
            message: "Missing key parameter",
          );
        }
        _memoryCache[key] = params["data"];
        return LynxBridgeResponse.success(callId: request.callId);

      case "getStorage":
        final key = params["key"]?.toString();
        if (key == null || !_memoryCache.containsKey(key)) {
          return LynxBridgeResponse.error(
            callId: request.callId,
            code: 404,
            message: "Key not found",
          );
        }
        return LynxBridgeResponse.success(
          callId: request.callId,
          data: {"data": _memoryCache[key]},
        );

      case "removeStorage":
        final key = params["key"]?.toString();
        if (key != null) {
          _memoryCache.remove(key);
        }
        return LynxBridgeResponse.success(callId: request.callId);

      case "clearStorage":
        _memoryCache.clear();
        return LynxBridgeResponse.success(callId: request.callId);

      case "getStorageInfo":
        return LynxBridgeResponse.success(
          callId: request.callId,
          data: {
            "keys": _memoryCache.keys.toList(),
            "currentSize": _memoryCache.length,
          },
        );

      default:
        return LynxBridgeResponse.error(
          callId: request.callId,
          code: 404,
          message: "Method ${request.method} not supported in StorageBridgeHandler",
        );
    }
  }
}
