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
        "params": {"key": "name", "data": "KManager"},
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
      expect(getRes["data"]["data"], "KManager");
    });
  });
}
