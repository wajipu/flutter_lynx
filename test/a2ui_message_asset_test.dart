import "dart:convert";
import "dart:io";

import "package:flutter_test/flutter_test.dart";

/// A2UI 确认卡协议消息样例测试：直接读取 example 内置资产文件（flutter test
/// 默认工作目录是包根），验证小柯应产出的 A2UI v0.9 消息数组满足宿主渲染契约——
/// 该样例同时作为给云端小柯 Skill 的模板素材，这里每条断言即一条模板约束。
void main() {
  // A2UI v0.9 一条消息只承载一个动作，且只允许这 4 种。
  const messageActionKeys = {
    "createSurface",
    "updateComponents",
    "updateDataModel",
    "deleteSurface",
  };

  final messagesFile = File("example/assets/a2ui/confirm-card-messages.json");
  // 延迟到用例内首次访问时才读文件：expect 只能在测试上下文里调用，
  // 首个用例先断言文件存在，再触发解析。
  late final rawText = messagesFile.readAsStringSync();
  late final messages = jsonDecode(rawText) as List<dynamic>;

  /// 递归遍历任意已解码 JSON 值：Map 节点先收录自身再深入子值，
  /// List 逐项深入，保证任意深度的嵌套结构都不遗漏。
  List<Map<dynamic, dynamic>> collectMaps(
    dynamic node,
    bool Function(Map<dynamic, dynamic>) predicate,
  ) {
    final result = <Map<dynamic, dynamic>>[];
    void walk(dynamic current) {
      if (current is Map) {
        if (predicate(current)) result.add(current);
        current.values.forEach(walk);
      } else if (current is List) {
        for (final item in current) {
          walk(item);
        }
      }
    }

    walk(node);
    return result;
  }

  /// 递归收集一个组件以 id 引用形式声明的子组件引用：children 数组元素与
  /// child 单值。A2UI 不允许内联子组件，这两处只能是字符串 id。
  Set<String> collectChildRefs(Map<dynamic, dynamic> component) {
    final refs = <String>{};
    final children = component["children"];
    if (children is List) {
      for (final child in children) {
        if (child is String) refs.add(child);
      }
    }
    final child = component["child"];
    if (child is String) refs.add(child);
    return refs;
  }

  group("A2UI 确认卡消息资产", () {
    test("文件存在，解析为非空消息数组，每条都是 Map 且 version 为 v0.9", () {
      expect(
        messagesFile.existsSync(),
        isTrue,
        reason: "样例必须随仓库提供（example/assets/a2ui/）",
      );
      expect(messages, isNotEmpty);
      for (final message in messages) {
        expect(message, isA<Map<dynamic, dynamic>>());
        expect(
          (message as Map<dynamic, dynamic>)["version"],
          "v0.9",
          reason: "A2UI v0.9 协议要求每条消息都携带 version 字段",
        );
      }
    });

    test(
        "消息种类符合契约：恰好一条 createSurface(catalogId 含 basic)"
        " + 恰好一条 updateComponents + 零 updateDataModel，无 deleteSurface", () {
      // 逐条按「消息里出现的动作键」分类统计。
      final counts = <String, int>{};
      for (final message in messages) {
        final actionKeys = (message as Map<dynamic, dynamic>)
            .keys
            .where(messageActionKeys.contains)
            .toList();
        expect(actionKeys, hasLength(1), reason: "一条消息只承载一个动作");
        final actionKey = actionKeys.single as String;
        counts[actionKey] = (counts[actionKey] ?? 0) + 1;
      }
      expect(counts["createSurface"], 1, reason: "确认卡只创建一个 surface");
      expect(counts["updateComponents"], 1);
      expect(counts["updateDataModel"] ?? 0, 0,
          reason: "生产契约：数据由宿主经 initData 播种进数据模型，模板零数据携带");
      expect(counts["deleteSurface"] ?? 0, 0,
          reason: "确认卡是展示型 surface，不应携带删除动作");

      // createSurface 必须指向官方 basic catalog。
      final createSurfaces = collectMaps(
        messages,
        (node) => node.containsKey("createSurface"),
      );
      final surface =
          createSurfaces.single["createSurface"] as Map<dynamic, dynamic>;
      expect(
        surface["catalogId"] as String,
        contains("basic"),
        reason: "确认卡只使用官方基础组件目录",
      );
    });

    test("组件树根为 root(Column)，组件 id 无重复、引用闭合且 root 可达", () {
      final componentsMessage = messages
          .map((message) => message as Map<dynamic, dynamic>)
          .singleWhere((message) => message.containsKey("updateComponents"));
      final updateComponents =
          componentsMessage["updateComponents"] as Map<dynamic, dynamic>;
      final components = updateComponents["components"] as List<dynamic>;
      expect(components, isNotEmpty);

      // 定义表 id -> 组件；id 重复会让引用指向不确定，直接判失败。
      final byId = <String, Map<dynamic, dynamic>>{};
      for (final component in components) {
        final id = (component as Map<dynamic, dynamic>)["id"] as String;
        expect(byId.containsKey(id), isFalse, reason: "组件 id 重复: $id");
        byId[id] = component;
      }

      // 根组件必须存在且为 Column（渲染器以 root 为组件树入口）。
      expect(byId.containsKey("root"), isTrue);
      expect(byId["root"]!["component"], "Column");

      // 引用闭合性：children/child 里引用的每个 id 都必须有定义。
      final referencedIds = <String>{};
      for (final component in byId.values) {
        referencedIds.addAll(collectChildRefs(component));
      }
      expect(
        referencedIds.difference(byId.keys.toSet()),
        isEmpty,
        reason: "存在引用了未定义组件 id 的节点",
      );

      // 可达性：从 root 递归出发（带环保护），不允许游离于树外的组件定义。
      final visited = <String>{};
      void visit(String id) {
        if (visited.contains(id)) return;
        visited.add(id);
        collectChildRefs(byId[id]!).forEach(visit);
      }

      visit("root");
      expect(
        byId.keys.toSet().difference(visited),
        isEmpty,
        reason: "存在 root 不可达的游离组件定义",
      );
    });

    test("所有 Button 的动作是 confirm/cancel 事件，confirm 携带 quantity 绑定", () {
      final buttons = collectMaps(
        messages,
        (node) => node["component"] == "Button",
      );
      expect(buttons, hasLength(2), reason: "确认卡恰好一对确认/取消按钮");

      // 取按钮的动作事件名；只认 action.event 形态。
      String? eventName(Map<dynamic, dynamic> button) {
        final action = button["action"];
        if (action is! Map) return null;
        final event = action["event"];
        if (event is! Map) return null;
        return event["name"] as String?;
      }

      for (final button in buttons) {
        expect(
          eventName(button),
          isIn(const {"confirm", "cancel"}),
          reason: "按钮只能触发确认卡的确认/取消事件",
        );
      }

      // confirm 的 quantity 必须来自数据模型绑定而非字面量，保证宿主
      // 收到的回传值与小柯现场写入 data model 的补货数量一致。
      final confirm =
          buttons.singleWhere((button) => eventName(button) == "confirm");
      final event = (confirm["action"] as Map)["event"] as Map;
      final context = event["context"] as Map;
      final quantity = context["quantity"] as Map;
      expect(
        quantity.containsKey("path"),
        isTrue,
        reason: 'confirm 的 quantity 必须用 {"path": ...} 绑定数据模型',
      );
      expect(quantity["path"], "/payload/quantity");
    });

    test("无函数调用；绑定全部落在契约命名空间；文案零硬编码", () {
      // 渲染端 catalog 保持最小化：全文不允许出现 {"call": ...} 函数调用，
      // 只允许字面量与 {"path": ...} 数据绑定。
      expect(rawText.contains("{call"), isFalse);

      // 所有 {"path": ...} 绑定必须落在宿主播种的契约命名空间内
      // （koklam-docs f42edc0）：/label/*（三语文案）、/payload/*（候选
      // 字段）、/confirmationId、/statusText。
      final bindings = collectMaps(messages, (node) => node.containsKey("path"))
          .map((node) => node["path"] as String)
          .toList();
      expect(bindings, isNotEmpty);
      const namespacePattern = r"^/(label|payload)/.+";
      for (final path in bindings) {
        final allowed = RegExp(namespacePattern).hasMatch(path) ||
            path == "/confirmationId" ||
            path == "/statusText";
        expect(allowed, isTrue, reason: "越界绑定: $path");
      }

      // 文案零硬编码：所有 Text 的 text 一律是 {"path": ...} 绑定
      // （三语文案由宿主经 initData.label 注入）。
      final texts = collectMaps(messages, (node) => node["component"] == "Text");
      expect(texts, isNotEmpty);
      for (final text in texts) {
        final value = text["text"];
        expect(value, isA<Map<dynamic, dynamic>>(),
            reason: "Text 组件存在硬编码文案: ${text["id"]}");
        expect((value as Map<dynamic, dynamic>)["path"], isA<String>());
      }
    });
  });
}
