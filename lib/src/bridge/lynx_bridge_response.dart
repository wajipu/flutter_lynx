class LynxBridgeResponse {
  final String callId;
  final int code;
  final String message;
  final Map<String, dynamic>? data;

  const LynxBridgeResponse({
    required this.callId,
    this.code = 0,
    this.message = "ok",
    this.data,
  });

  factory LynxBridgeResponse.success({
    required String callId,
    Map<String, dynamic>? data,
    String message = "ok",
  }) {
    return LynxBridgeResponse(
      callId: callId,
      code: 0,
      message: message,
      data: data,
    );
  }

  factory LynxBridgeResponse.error({
    required String callId,
    required int code,
    required String message,
  }) {
    return LynxBridgeResponse(
      callId: callId,
      code: code,
      message: message,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      "callId": callId,
      "code": code,
      "message": message,
      if (data != null) "data": data,
    };
  }
}
