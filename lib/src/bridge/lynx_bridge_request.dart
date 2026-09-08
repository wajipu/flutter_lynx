class LynxBridgeRequest {
  final String callId;
  final String module;
  final String method;
  final Map<String, dynamic> params;

  LynxBridgeRequest({
    required this.callId,
    required this.module,
    required this.method,
    this.params = const {},
  });

  factory LynxBridgeRequest.fromMap(Map<dynamic, dynamic> map) {
    return LynxBridgeRequest(
      callId: map["callId"]?.toString() ?? "",
      module: map["module"]?.toString() ?? "default",
      method: map["method"]?.toString() ?? "",
      params: Map<String, dynamic>.from(map["params"] as Map? ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "callId": callId,
      "module": module,
      "method": method,
      "params": params,
    };
  }
}
