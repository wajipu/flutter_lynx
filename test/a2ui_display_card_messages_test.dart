import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";

/// A2UI 展示卡（Tabs/图表演示）消息样例测试：同一 bundle 的第二张菜单，
/// 验证展示卡消息满足渲染契约。与确认卡契约的差异点：
/// - Tabs 页签标题为字面量（官方 Tabs 直读 props.tabs，页签标题不做 path 绑定）；
/// - 图表数据为 path 绑定（labels/series/data 顶层 prop 绑定由渲染器解析），
///   数值为字面量数字（数字不属「文案」约束范围）。
void main() {
  final messagesFile = File("example/assets/a2ui/display-card-messages.json");
  late final messages =
      jsonDecode(messagesFile.readAsStringSync()) as List<dynamic>;

  test("展示卡消息资产 文件存在，解析为非空消息数组，每条都是 Map 且 version 为 v0.9", () {
    expect(messagesFile.existsSync(), isTrue);
    expect(messages, isNotEmpty);
    for (final message in messages) {
      expect(message, isA<Map<dynamic, dynamic>>());
      expect(message["version"], "v0.9");
    }
  });

  test("展示卡消息 恰好一条 createSurface + 一条 updateComponents，零 updateDataModel", () {
    final actionKeys = messages
        .map((m) => m.keys.where((k) => k != "version"))
        .expand((keys) => keys)
        .toSet();
    expect(actionKeys, containsAll(["createSurface", "updateComponents"]));
    expect(actionKeys, isNot(contains("updateDataModel")));
    expect(actionKeys, isNot(contains("deleteSurface")));
  });

  test("展示卡组件 全部落在白名单内、id 无重复，且实际用到 Tabs/图表/Icon", () {
    const whitelist = {
      "Text",
      "Row",
      "Column",
      "Card",
      "Divider",
      "Button",
      "Icon",
      "Image",
      "List",
      "Loading",
      "Tabs",
      "LineChart",
      "PieChart",
      "BarChart",
      "ScatterChart",
      "RadarChart",
      "FunnelChart",
    };
    final components = (messages[1]["updateComponents"]
        as Map<dynamic, dynamic>)["components"] as List<dynamic>;
    final ids = <String>{};
    for (final component in components) {
      final map = component as Map<dynamic, dynamic>;
      final name = map["component"] as String;
      expect(whitelist, contains(name), reason: "组件 $name 不在白名单");
      final id = map["id"] as String;
      expect(ids, isNot(contains(id)), reason: "组件 id 重复: $id");
      ids.add(id);
    }
    final names = components.map((c) => c["component"]).toSet();
    expect(
        names,
        containsAll([
          "Tabs", "LineChart", "PieChart", "BarChart", "ScatterChart",
          "RadarChart", "FunnelChart", "Icon",
        ]));
  });

  test("展示卡绑定 只允许 path 绑定，无函数调用，path 须以 / 开头", () {
    void walk(dynamic node) {
      if (node is Map) {
        for (final entry in node.entries) {
          if (entry.key == "path") {
            final value = entry.value as String;
            expect(value.startsWith("/"), isTrue, reason: "path 须以 / 开头");
          }
          if (entry.key == "call") {
            fail("展示卡禁止函数调用");
          }
          walk(entry.value);
        }
      } else if (node is List) {
        for (final item in node) {
          walk(item);
        }
      }
    }

    walk(messages);
  });
}
