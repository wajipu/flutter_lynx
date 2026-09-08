import "package:flutter/services.dart";
import "lynx_bridge_handler.dart";
import "lynx_bridge_request.dart";
import "lynx_bridge_response.dart";
import "built_in/system_bridge_handler.dart";
import "built_in/ui_bridge_handler.dart";
import "built_in/storage_bridge_handler.dart";
import "built_in/router_bridge_handler.dart";

typedef LynxBridgeFunction = Future<Map<String, dynamic>?> Function(Map<String, dynamic> params);

/// Central JSBridge dispatcher that connects Lynx JavaScript and Flutter Host.
class LynxBridge {
  static final LynxBridge _instance = LynxBridge._internal();
  factory LynxBridge() => _instance;
  static LynxBridge get instance => _instance;

  final MethodChannel _channel = const MethodChannel("com.kmanager.flutter_lynx/bridge");

  final List<LynxBridgeHandler> _handlers = [];
  final Map<String, LynxBridgeFunction> _functionHandlers = {};

  final SystemBridgeHandler systemHandler = SystemBridgeHandler();
  final UIBridgeHandler uiHandler = UIBridgeHandler();
  final StorageBridgeHandler storageHandler = StorageBridgeHandler();
  final RouterBridgeHandler routerHandler = RouterBridgeHandler();

  LynxBridge._internal() {
    // Register built-in handlers
    addHandler(systemHandler);
    addHandler(uiHandler);
    addHandler(storageHandler);
    addHandler(routerHandler);

    // Listen for calls from native Lynx engine
    _channel.setMethodCallHandler(_onMethodCall);
  }

  /// Add a modular bridge handler.
  void addHandler(LynxBridgeHandler handler) {
    if (!_handlers.contains(handler)) {
      _handlers.add(handler);
    }
  }

  /// Register a direct functional handler for a specific method.
  /// This is how host apps (like kmanager) register custom capabilities:
  /// scanQRCode, getUserInfo, request, etc.
  void register(String method, LynxBridgeFunction function, {String module = "default"}) {
    final key = "$module:$method";
    _functionHandlers[key] = function;
    // Also register under default key for convenience
    if (module != "default") {
      _functionHandlers["default:$method"] = function;
    }
  }

  /// Unregister a method.
  void unregister(String method, {String module = "default"}) {
    _functionHandlers.remove("$module:$method");
    if (module != "default") {
      _functionHandlers.remove("default:$method");
    }
  }

  /// Dispatch an incoming request from Lynx JS to registered handlers.
  Future<Map<String, dynamic>> dispatch(Map<dynamic, dynamic> rawRequest) async {
    final request = LynxBridgeRequest.fromMap(rawRequest);

    // 1. Check direct functional registrations
    final directKey = "${request.module}:${request.method}";
    final defaultKey = "default:${request.method}";
    final directFunction = _functionHandlers[directKey] ?? _functionHandlers[defaultKey];

    if (directFunction != null) {
      try {
        final result = await directFunction(request.params);
        final response = LynxBridgeResponse.success(
          callId: request.callId,
          data: result,
        );
        return response.toMap();
      } catch (e) {
        final response = LynxBridgeResponse.error(
          callId: request.callId,
          code: 500,
          message: e.toString(),
        );
        return response.toMap();
      }
    }

    // 2. Check modular handlers
    for (final handler in _handlers) {
      if (handler.canHandle(request.module, request.method)) {
        try {
          final response = await handler.handle(request);
          return response.toMap();
        } catch (e) {
          final response = LynxBridgeResponse.error(
            callId: request.callId,
            code: 500,
            message: e.toString(),
          );
          return response.toMap();
        }
      }
    }

    // 3. Fallback: Not found
    final notFound = LynxBridgeResponse.error(
      callId: request.callId,
      code: 404,
      message: "Bridge method ${request.module}.${request.method} not found",
    );
    return notFound.toMap();
  }

  /// Send an event from Flutter host to Lynx template.
  Future<void> sendEventToLynx(
    String eventName,
    Map<String, dynamic> data, {
    int? viewId,
  }) async {
    try {
      await _channel.invokeMethod("sendCustomEvent", {
        "eventName": eventName,
        "data": data,
        if (viewId != null) "viewId": viewId,
      });
    } catch (_) {}
  }

  Future<dynamic> _onMethodCall(MethodCall call) async {
    if (call.method == "callBridge") {
      final arguments = call.arguments;
      if (arguments is Map) {
        return await dispatch(arguments);
      }
    }
    return null;
  }
}
