import "../lynx_bridge_handler.dart";
import "../lynx_bridge_request.dart";
import "../lynx_bridge_response.dart";

/// `data` 模块第一批白名单方法（契约文档 merchant-mobile-app/13 §4）。
///
/// 新增方法必须先补 13 号文清单，再在此扩枚举，禁止绕过文档直接加方法。
enum DataBridgeMethod {
  /// 未读消息总数：`{}` → `{total: number}`。
  messageUnreadTotal("messageUnreadTotal"),

  /// 库存预警列表（当前门店 top 20）：`{}` → `{list: [...]}`。
  inventoryAlertList("inventoryAlertList"),

  /// 收款概览：`{}` → Cloud `/system/payment/stats/overview` VO 透传。
  paymentStatsOverview("paymentStatsOverview");

  const DataBridgeMethod(this.wire);

  /// wire 值即 JS 调用的方法名，保持小写驼峰原样。
  final String wire;

  static DataBridgeMethod? fromWire(String value) {
    for (final method in DataBridgeMethod.values) {
      if (method.wire == value) return method;
    }
    return null;
  }
}

/// 宿主代调结果：Cloud `R` 信封（`{code, msg, data}`）由宿主组装后整体交给 JS。
///
/// 码表沿用 Cloud `R`：`200` 成功，`401` 会话失效，其余非 200 一律失败态；
/// `msg` 已由宿主/Cloud 按 `content-language` 解析，bundle 不自行翻译。
class DataBridgeReply {
  final int code;
  final String message;
  final Map<String, dynamic>? data;

  const DataBridgeReply({
    required this.code,
    required this.message,
    this.data,
  });
}

/// 宿主注册的代调函数。Token 与租户/门店/用户上下文只留在宿主闭包内，
/// 绝不通过 initialData 或响应透传给 JS。
typedef DataBridgeDelegate = Future<DataBridgeReply> Function(
  DataBridgeMethod method,
  Map<String, dynamic> params,
);

/// 业务数据 Bridge：独立于 `system` 的设备/环境语义，只读白名单 + 宿主代调。
///
/// 宿主未提供 [delegate] 时不伪造数据，直接返回固定失败；
/// 未列名方法根本不会进入本 handler（canHandle 精确匹配），沿用工层
/// `module.method not found` 固定拒绝路径。
class DataBridgeHandler implements LynxBridgeHandler {
  static const String _module = "data";

  /// 入参禁止出现的身份上下文字段：数据范围由宿主会话决定，不信任 JS 传参。
  static const Set<String> _forbiddenParamKeys = {
    "tenantId",
    "storeId",
    "userId",
  };

  /// 宿主在创建 LynxView 前注入；为 null 表示当前宿主未开通 data 模块。
  DataBridgeDelegate? delegate;

  @override
  bool canHandle(String module, String method) =>
      module == _module && DataBridgeMethod.fromWire(method) != null;

  @override
  Future<LynxBridgeResponse> handle(LynxBridgeRequest request) async {
    final method = DataBridgeMethod.fromWire(request.method);
    // canHandle 已拦截未列名方法；此处兜住直接调用 handle 的路径。
    if (method == null) {
      return LynxBridgeResponse.error(
        callId: request.callId,
        code: 404,
        message:
            "Method ${request.method} not supported in DataBridgeHandler",
      );
    }
    final hostDelegate = delegate;
    if (hostDelegate == null) {
      // 不做任何假数据兜底：宿主没开通就明确失败，让 bundle 呈现失败态。
      return LynxBridgeResponse.error(
        callId: request.callId,
        code: 501,
        message: "Data bridge module is not provided by this host",
      );
    }
    for (final key in request.params.keys) {
      if (_forbiddenParamKeys.contains(key)) {
        return LynxBridgeResponse.error(
          callId: request.callId,
          code: 403,
          message:
              "Data bridge params must not carry identity context: $key",
        );
      }
    }
    try {
      final reply = await hostDelegate(method, request.params);
      // bridge 层 code 恒为 0 表示“调用已执行”；业务成败由信封 code 表达，
      // bundle 按三态约定渲染 loading/empty/error。
      return LynxBridgeResponse.success(
        callId: request.callId,
        data: {
          "code": reply.code,
          "msg": reply.message,
          "data": reply.data,
        },
      );
    } catch (error) {
      return LynxBridgeResponse.error(
        callId: request.callId,
        code: 500,
        message: error.toString(),
      );
    }
  }
}
