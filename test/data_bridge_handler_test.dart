// 覆盖 data Bridge 模块的白名单、身份参数拒绝与信封透传。
import "package:flutter_lynx/src/bridge/built_in/data_bridge_handler.dart";
import "package:flutter_lynx/src/bridge/lynx_bridge_request.dart";
import "package:flutter_test/flutter_test.dart";

DataBridgeReply _ok(Map<String, dynamic> data) =>
    DataBridgeReply(code: 200, message: "ok", data: data);

void main() {
  group("DataBridgeHandler whitelist", () {
    test("accepts only the documented data methods", () {
      final handler = DataBridgeHandler();
      expect(
        handler.canHandle(
          "data",
          DataBridgeMethod.messageUnreadTotal.wire,
        ),
        isTrue,
      );
      expect(handler.canHandle("data", "inventoryAlertList"), isTrue);
      expect(handler.canHandle("data", "paymentStatsOverview"), isTrue);
      // 未列名方法不得进入 handler，由工层返回固定 not found。
      expect(handler.canHandle("data", "request"), isFalse);
      expect(handler.canHandle("system", "messageUnreadTotal"), isFalse);
      // 业务模块不允许借 default 通道。
      expect(handler.canHandle("default", "messageUnreadTotal"), isFalse);
    });
  });

  group("DataBridgeHandler handle", () {
    test("rejects identity context params before delegating", () async {
      var delegated = false;
      final handler = DataBridgeHandler()
        ..delegate = (method, params) async {
          delegated = true;
          return _ok({});
        };
      final response = await handler.handle(
        LynxBridgeRequest(
          callId: "c1",
          module: "data",
          method: "inventoryAlertList",
          params: {"storeId": 1},
        ),
      );
      expect(delegated, isFalse);
      expect(response.code, 403);
    });

    test("returns fixed failure when host delegate is missing", () async {
      final handler = DataBridgeHandler();
      final response = await handler.handle(
        LynxBridgeRequest(
          callId: "c2",
          module: "data",
          method: "messageUnreadTotal",
        ),
      );
      expect(response.code, 501);
    });

    test("maps delegate reply into the Cloud R envelope", () async {
      final handler = DataBridgeHandler()
        ..delegate = (method, params) async {
          expect(method, DataBridgeMethod.messageUnreadTotal);
          expect(params, isEmpty);
          return _ok({"total": 7});
        };
      final response = await handler.handle(
        LynxBridgeRequest(
          callId: "c3",
          module: "data",
          method: "messageUnreadTotal",
        ),
      );
      // bridge 层成功；业务信封整体放在 data，bundle 按三态渲染。
      expect(response.code, 0);
      expect(response.data, {
        "code": 200,
        "msg": "ok",
        "data": {"total": 7},
      });
    });

    test("keeps business failure codes inside the envelope", () async {
      final handler = DataBridgeHandler()
        ..delegate = (method, params) async =>
            const DataBridgeReply(code: 403, message: "无此权限");
      final response = await handler.handle(
        LynxBridgeRequest(
          callId: "c4",
          module: "data",
          method: "paymentStatsOverview",
        ),
      );
      expect(response.code, 0);
      expect(response.data?["code"], 403);
      expect(response.data?["msg"], "无此权限");
      expect(response.data?["data"], isNull);
    });

    test("wraps delegate exceptions as bridge errors", () async {
      final handler = DataBridgeHandler()
        ..delegate = (method, params) async => throw StateError("boom");
      final response = await handler.handle(
        LynxBridgeRequest(
          callId: "c5",
          module: "data",
          method: "inventoryAlertList",
        ),
      );
      expect(response.code, 500);
      expect(response.message, contains("boom"));
    });

    test("rejects undocumented methods handed directly", () async {
      final handler = DataBridgeHandler()
        ..delegate = (method, params) async => _ok({});
      final response = await handler.handle(
        LynxBridgeRequest(
          callId: "c6",
          module: "data",
          method: "anyThingElse",
        ),
      );
      expect(response.code, 404);
    });
  });
}
