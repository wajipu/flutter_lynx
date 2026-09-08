import "lynx_bridge_request.dart";
import "lynx_bridge_response.dart";

/// Modular handler for JSBridge calls from Lynx mini programs.
abstract class LynxBridgeHandler {
  /// Check whether this handler can process the given method.
  bool canHandle(String module, String method);

  /// Execute the method and return response.
  Future<LynxBridgeResponse> handle(LynxBridgeRequest request);
}
