class LynxBridgeRequest {
  final String callId;
  final String module;
  final String method;
  final Map<String, dynamic> params;
  /// Injected by the native view binding, never taken from JS params.
  final String? sourceContextId;

  LynxBridgeRequest({
    required this.callId,
    required this.module,
    required this.method,
    this.params = const {},
    this.sourceContextId,
  });

  factory LynxBridgeRequest.fromMap(Map<dynamic, dynamic> map) {
    return LynxBridgeRequest(
      callId: map["callId"]?.toString() ?? "",
      module: map["module"]?.toString() ?? "default",
      method: map["method"]?.toString() ?? "",
      params: Map<String, dynamic>.from(map["params"] as Map? ?? {}),
      sourceContextId: map["sourceContextId"] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "callId": callId,
      "module": module,
      "method": method,
      "params": params,
      "sourceContextId": sourceContextId,
    };
  }
}
