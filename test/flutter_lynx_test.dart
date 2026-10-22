import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:flutter_lynx/flutter_lynx.dart";

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group("LynxTemplateData", () {
    test("serializes and deserializes properly", () {
      final data = LynxTemplateData({"title": "Test", "count": 10});
      expect(data.toMap()["title"], "Test");
      expect(data.toMap()["count"], 10);

      final jsonStr = data.toJson();
      final reconstructed = LynxTemplateData.fromJson(jsonStr);
      expect(reconstructed.toMap()["title"], "Test");
      expect(reconstructed.toMap()["count"], 10);
    });
  });

  group("MiniProgramManifest", () {
    test("converts to and from map correctly", () {
      final manifest = MiniProgramManifest(
        appId: "test_miniapp",
        name: "测试小程序",
        version: "1.2.0",
        bundleUrl: "https://example.com/main.lynx.bundle",
        md5: "abc123",
        initialData: {"user": "admin"},
      );

      final map = manifest.toMap();
      expect(map["appId"], "test_miniapp");
      expect(map["name"], "测试小程序");
      expect(map["version"], "1.2.0");

      final reconstructed = MiniProgramManifest.fromMap(map);
      expect(reconstructed.appId, "test_miniapp");
      expect(reconstructed.md5, "abc123");
      expect(reconstructed.initialData?["user"], "admin");
      expect(reconstructed.applySafeArea, isTrue);
      expect(map["applySafeArea"], isTrue);
    });

    test("fromMap 缺省 applySafeArea 时默认打开", () {
      final manifest = MiniProgramManifest.fromMap({
        "appId": "safe_default",
        "name": "默认安全区",
        "version": "1.0.0",
        "bundleUrl": "https://example.com/main.lynx.bundle",
      });
      expect(manifest.applySafeArea, isTrue);
    });

    test("applySafeArea 为 false 时保持关闭", () {
      final manifest = MiniProgramManifest(
        appId: "safe_off",
        name: "关闭安全区",
        version: "1.0.0",
        bundleUrl: "https://example.com/main.lynx.bundle",
        applySafeArea: false,
      );
      expect(manifest.toMap()["applySafeArea"], isFalse);
      expect(
        MiniProgramManifest.fromMap(manifest.toMap()).applySafeArea,
        isFalse,
      );
    });
  });

  group("LynxBridge", () {
    test("handles direct registration and dispatch", () async {
      final bridge = LynxBridge.instance;

      bridge.register("testMethod", (params) async {
        return {"result": params["input"] * 2};
      });

      final response = await bridge.dispatch({
        "callId": "call_1",
        "module": "default",
        "method": "testMethod",
        "params": {"input": 21},
      });

      expect(response["code"], 0);
      expect(response["data"]["result"], 42);
    });

    test("handles storage bridge handler", () async {
      final bridge = LynxBridge.instance;

      // Set storage
      final setRes = await bridge.dispatch({
        "callId": "set_1",
        "module": "storage",
        "method": "setStorage",
        "params": {"key": "name", "data": "HostApp"},
      });
      expect(setRes["code"], 0);

      // Get storage
      final getRes = await bridge.dispatch({
        "callId": "get_1",
        "module": "storage",
        "method": "getStorage",
        "params": {"key": "name"},
      });
      expect(getRes["code"], 0);
      expect(getRes["data"]["data"], "HostApp");
    });
  });

  group("LynxDynamicCanvas", () {
    testWidgets("renders dynamic canvas commands without error",
        (tester) async {
      final commands = [
        {"op": "beginPath"},
        {"op": "moveTo", "x": 10, "y": 10},
        {"op": "lineTo", "x": 100, "y": 100},
        {"op": "setStrokeColor", "color": "#1677FF"},
        {"op": "setLineWidth", "width": 2.5},
        {"op": "stroke"},
        {"op": "rect", "x": 20, "y": 20, "w": 50, "h": 50, "isFill": true},
        {"op": "setFillColor", "color": "#52C41A"},
        {"op": "drawCircle", "x": 80, "y": 80, "r": 15},
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LynxDynamicCanvas(
              commands: commands,
              width: 200,
              height: 200,
            ),
          ),
        ),
      );

      expect(find.byType(LynxDynamicCanvas), findsOneWidget);
    });
  });
}
