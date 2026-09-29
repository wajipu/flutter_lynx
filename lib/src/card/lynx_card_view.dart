/// lynx-card/1 文本模板的 Flutter 渲染器。
///
/// 规范契约见 `docs/lynx-card-format.md`：本文件把解析完成的
/// [LynxCardDocument] 组件树渲染为 Flutter Widget，处理 `{{path}}`
/// 绑定求值、卡片 state 读写以及白名单内的 Bridge 动作出口。
/// 渲染过程无网络、无文件访问，未知组件按规范 §7 单点降级。
library;

import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../bridge/lynx_bridge.dart";
import "../utils/lynx_logger.dart";
import "lynx_card_document.dart";

/// 卡片动作允许调用的 Bridge 白名单（规范 §6.3，精确 `module.method` 匹配）。
const Set<String> kLynxCardActionBridgeWhitelist = {
  "ui.confirmResult",
  "ui.showToast",
  "system.getSystemInfo",
  "system.getNetworkType",
  "data.messageUnreadTotal",
  "data.inventoryAlertList",
  "data.paymentStatsOverview",
};

/// 解析 `#RRGGBB` / `#RRGGBBAA` 颜色字面量；非法输入回退 null。
Color? _parseCardColor(String input) {
  var hex = input.trim();
  if (hex.startsWith("#")) {
    hex = hex.substring(1);
  }
  if (hex.length != 6 && hex.length != 8) {
    return null;
  }
  final value = int.tryParse(hex, radix: 16);
  if (value == null) {
    return null;
  }
  if (hex.length == 6) {
    return Color(0xFF000000 | value);
  }
  return Color(value);
}

/// 规范 §4 的真值判定：`null`、`false`、`0`、`""` 为假，其余为真。
bool _isTruthy(dynamic value) {
  if (value == null) {
    return false;
  }
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    return value.isNotEmpty;
  }
  return true;
}

/// 卡片主题令牌（规范 §5），跟随宿主明暗模式；模板指定颜色优先。
class _CardPalette {
  /// 卡片背景。
  final Color background;

  /// 主文字。
  final Color text;

  /// 次级文字。
  final Color subtext;

  /// 分隔线。
  final Color divider;

  /// 主色（按钮/图表）。
  final Color primary;

  /// 危险色。
  final Color danger;

  /// 次级按钮底色。
  final Color secondaryBg;

  const _CardPalette({
    required this.background,
    required this.text,
    required this.subtext,
    required this.divider,
    required this.primary,
    required this.danger,
    required this.secondaryBg,
  });

  /// 按当前BuildContext的明暗模式取对应令牌组。
  factory _CardPalette.of(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    if (dark) {
      return const _CardPalette(
        background: Color(0xFF1E1F22),
        text: Color(0xFFE8EAED),
        subtext: Color(0xFFA8ADB4),
        divider: Color(0xFF3A3D42),
        primary: Color(0xFF4096FF),
        danger: Color(0xFFFF7875),
        secondaryBg: Color(0xFF2C2E33),
      );
    }
    return const _CardPalette(
      background: Color(0xFFFFFFFF),
      text: Color(0xFF1F2329),
      subtext: Color(0xFF646A73),
      divider: Color(0xFFE5E6EB),
      primary: Color(0xFF1677FF),
      danger: Color(0xFFFF4D4F),
      secondaryBg: Color(0xFFF2F3F5),
    );
  }
}

/// 深拷贝字符串键 Map（用于 state 初始化，隔离 document 原始对象）。
Map<String, dynamic> _deepCopyMap(Map<dynamic, dynamic> source) {
  final out = <String, dynamic>{};
  source.forEach((key, value) {
    out[key.toString()] = _deepCopyValue(value);
  });
  return out;
}

/// 深拷贝任意 JSON 值；Map/List 递归，标量原样返回。
dynamic _deepCopyValue(dynamic value) {
  if (value is Map) {
    return _deepCopyMap(value);
  }
  if (value is List) {
    return value.map(_deepCopyValue).toList();
  }
  return value;
}

/// lynx-card/1 卡片渲染组件。
///
/// 渲染 [document] 的组件树；宿主数据经 [data] 注入（`initialData` 与
/// 运行时 `updateData` 合并后的结果，由外部持有），卡片本地 state 由
/// 组件内部持有，`input` 写入、按钮 `withState` 携带（规范 §3.1）。
class LynxCardView extends StatefulWidget {
  /// 待渲染的卡片文档（解析器产物）。
  final LynxCardDocument document;

  /// 宿主数据层，外部持有并可整体替换以触发重渲染。
  final ValueNotifier<Map<String, dynamic>> data;

  /// 创建卡片渲染组件。
  const LynxCardView({
    super.key,
    required this.document,
    required this.data,
  });

  @override
  State<LynxCardView> createState() => _LynxCardViewState();
}

class _LynxCardViewState extends State<LynxCardView> {
  /// 卡片本地 state（envelope `state` 深拷贝初始化，`input` 写入）。
  Map<String, dynamic> _state = const {};

  /// `once` 按钮已触发过的动作标识集合（防连点重复回传）。
  final Set<int> _spentActions = {};

  /// 已告警过的非白名单 bridge，避免每次 build 重复打日志。
  final Set<String> _warnedBridges = {};

  /// `input` 的输入控制器缓存，按 `bind` 键复用，避免重建丢焦点。
  final Map<String, TextEditingController> _inputControllers = {};

  @override
  void initState() {
    super.initState();
    _state = _deepCopyMap(widget.document.state);
  }

  @override
  void didUpdateWidget(covariant LynxCardView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.document, oldWidget.document)) {
      for (final controller in _inputControllers.values) {
        controller.dispose();
      }
      _inputControllers.clear();
      setState(() {
        _state = _deepCopyMap(widget.document.state);
        _spentActions.clear();
        _warnedBridges.clear();
      });
    }
  }

  @override
  void dispose() {
    for (final controller in _inputControllers.values) {
      controller.dispose();
    }
    _inputControllers.clear();
    super.dispose();
  }

  /// 供分组扩展方法触发的重渲染入口（extension 内不能直接调 setState）。
  void _refresh(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    final palette = _CardPalette.of(context);
    return Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle(
        style: TextStyle(fontSize: 14, color: palette.text),
        child: ValueListenableBuilder<Map<String, dynamic>>(
          valueListenable: widget.data,
          builder: (context, data, _) {
            final scope = LynxCardScope(data: data, state: _state);
            return _buildNode(widget.document.root, context, scope);
          },
        ),
      ),
    );
  }

  /// 递归构建单个节点：先求 `when`，再按 `type` 分发；未知类型降级。
  Widget _buildNode(
      LynxCardNode node, BuildContext context, LynxCardScope scope) {
    if (!_evalWhen(node, scope)) {
      return const SizedBox.shrink();
    }
    switch (node.type) {
      case "container":
        return _buildContainer(node, context, scope);
      case "text":
        return _buildText(node, context, scope);
      case "field":
        return _buildField(node, context, scope);
      case "divider":
        return _buildDivider(node, context, scope);
      case "spacer":
        return _buildSpacer(node, context, scope);
      case "input":
        return _buildInput(node, context, scope);
      case "button":
        return _buildButton(node, context, scope);
      case "list":
        return _buildList(node, context, scope);
      case "chart":
        return _buildChart(node, context, scope);
      default:
        return _buildUnsupported(node, context);
    }
  }
}

extension _CardNodeCommon on _LynxCardViewState {
  /// 求节点 `when` 条件：仅当属性为字符串绑定时求值，否则默认可见。
  bool _evalWhen(LynxCardNode node, LynxCardScope scope) {
    final raw = node.props["when"];
    if (raw is! String) {
      return true;
    }
    return _isTruthy(scope.resolveValue(raw));
  }

  /// 构建容器子项：子节点声明 `flex`（num）时包 `Expanded`。
  Widget _buildChildWithFlex(
      LynxCardNode child, BuildContext context, LynxCardScope scope) {
    final widget = _buildNode(child, context, scope);
    final flex = child.props["flex"];
    if (flex is num) {
      return Expanded(flex: flex.toInt().clamp(0, 0x3FFFFFFF), child: widget);
    }
    return widget;
  }

  /// 在子项之间插入 [gap] 间距（`SizedBox`，不参与 flex 权重）。
  List<Widget> _withGaps(List<Widget> children, double gap) {
    if (gap <= 0 || children.length < 2) {
      return children;
    }
    final out = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        out.add(SizedBox(width: gap, height: gap));
      }
      out.add(children[i]);
    }
    return out;
  }

  /// `container`：布局容器（规范 §4.1）。
  Widget _buildContainer(
      LynxCardNode node, BuildContext context, LynxCardScope scope) {
    final props = node.props;
    final children = node.children;
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    final palette = _CardPalette.of(context);
    final isRow = props["direction"] == "row";
    final gap = _numProp(props, "gap", 0);
    final padding = _numProp(props, "padding", 0);
    final radius = _numProp(props, "radius", 0);
    final background = _colorProp(props, "background") ?? palette.background;
    final borderColor = _colorProp(props, "border");
    final content = isRow
        ? Row(
            crossAxisAlignment: _parseCrossAlign(props["align"]),
            children: _withGaps([
              for (final child in children)
                _buildChildWithFlex(child, context, scope),
            ], gap),
          )
        : Column(
            crossAxisAlignment: _parseCrossAlign(props["align"]),
            children: _withGaps([
              for (final child in children)
                _buildChildWithFlex(child, context, scope),
            ], gap),
          );
    return Container(
      width: _numOrNull(props, "width"),
      height: _numOrNull(props, "height"),
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: background,
        borderRadius: radius > 0 ? BorderRadius.circular(radius) : null,
        border: borderColor != null
            ? Border.all(color: borderColor, width: 1)
            : null,
      ),
      child: content,
    );
  }
}

extension _CardLeafNodes on _LynxCardViewState {
  /// `text`：文本（规范 §4.2）。
  Widget _buildText(
      LynxCardNode node, BuildContext context, LynxCardScope scope) {
    final props = node.props;
    final palette = _CardPalette.of(context);
    final maxLinesRaw = props["maxLines"];
    final maxLines =
        maxLinesRaw is num && maxLinesRaw > 0 ? maxLinesRaw.toInt() : null;
    return Text(
      _applyTextLimit(_boundString(props["text"], scope)),
      style: TextStyle(
        fontSize: _numProp(props, "size", 14),
        color: _colorProp(props, "color") ?? palette.text,
        fontWeight: _parseWeight(props["weight"]),
      ),
      textAlign: _parseTextAlign(props["align"]),
      maxLines: maxLines,
      overflow: maxLines != null ? TextOverflow.ellipsis : null,
    );
  }

  /// `field`：键值行，左列固定宽 96 次级色，右侧自动伸展（规范 §4.3）。
  Widget _buildField(
      LynxCardNode node, BuildContext context, LynxCardScope scope) {
    final props = node.props;
    final palette = _CardPalette.of(context);
    final label = props["label"];
    final value = _applyTextLimit(_boundString(props["value"], scope));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label is String && label.isNotEmpty)
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: palette.subtext),
            ),
          ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 14, color: palette.text),
          ),
        ),
      ],
    );
  }

  /// `divider`：分隔线（规范 §4.8）。
  Widget _buildDivider(
      LynxCardNode node, BuildContext context, LynxCardScope scope) {
    final color =
        _colorProp(node.props, "color") ?? _CardPalette.of(context).divider;
    return Divider(height: 1, thickness: 1, color: color);
  }

  /// `spacer`：空白占位（规范 §4.8）。
  Widget _buildSpacer(
      LynxCardNode node, BuildContext context, LynxCardScope scope) {
    final size = _numProp(node.props, "size", 8);
    return SizedBox(width: size, height: size);
  }
}

extension _CardInputNode on _LynxCardViewState {
  /// `input`：输入框，写入卡片 `state.<bind>`（规范 §4.4）。
  ///
  /// 初值优先级：`state.<bind>` 非 null 优先；否则取可选 `value`
  /// 属性（绑定表达式）在构建期求值的结果；都没有则空串。
  Widget _buildInput(
      LynxCardNode node, BuildContext context, LynxCardScope scope) {
    final props = node.props;
    final bind = props["bind"];
    if (bind is! String || bind.isEmpty) {
      return const SizedBox.shrink();
    }
    final palette = _CardPalette.of(context);
    final controller = _inputControllers.putIfAbsent(bind, () {
      final current = _state[bind];
      final initial = current != null
          ? LynxCardScope.stringify(current)
          : _inputInitialFromValue(props["value"], scope);
      return TextEditingController(text: initial);
    });
    final isNumber = props["keyboard"] == "number";
    final field = TextField(
      controller: controller,
      keyboardType: isNumber
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: isNumber
          ? <TextInputFormatter>[
              FilteringTextInputFormatter.allow(RegExp("[0-9.]")),
            ]
          : null,
      style: TextStyle(fontSize: 14, color: palette.text),
      decoration: InputDecoration(
        isDense: true,
        hintText: props["placeholder"] is String
            ? props["placeholder"] as String
            : null,
        hintStyle: TextStyle(fontSize: 14, color: palette.subtext),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: palette.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: palette.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: palette.primary),
        ),
      ),
      onChanged: (value) {
        _refresh(() {
          if (isNumber) {
            _state[bind] = value.isEmpty ? null : num.tryParse(value);
          } else {
            _state[bind] = value;
          }
        });
      },
    );
    final label = props["label"];
    if (label is String && label.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: palette.subtext)),
          const SizedBox(height: 4),
          field,
        ],
      );
    }
    return field;
  }

  /// 由可选 `value` 属性求输入框兜底初值：绑定求值后 stringify。
  String _inputInitialFromValue(dynamic raw, LynxCardScope scope) {
    final resolved = scope.resolveValue(raw);
    if (resolved == null) {
      return "";
    }
    return LynxCardScope.stringify(resolved);
  }
}

extension _CardActionNode on _LynxCardViewState {
  /// `button`：动作出口（规范 §4.5）。
  ///
  /// 禁用条件：`once` 且已点过 / `disabled` 绑定为真 / 缺 `action` /
  /// `action.bridge` 不在白名单（此时按禁用渲染并告警一次）。
  Widget _buildButton(
      LynxCardNode node, BuildContext context, LynxCardScope scope) {
    final props = node.props;
    final palette = _CardPalette.of(context);
    final action = props["action"];
    final once = props["once"] is bool ? props["once"] as bool : true;
    final disabledRaw = props["disabled"];
    final disabled = _isTruthy(
        disabledRaw is String ? scope.resolveValue(disabledRaw) : disabledRaw);
    final bridge = action is Map ? action["bridge"] : null;
    final bridgeAllowed =
        bridge is String && kLynxCardActionBridgeWhitelist.contains(bridge);
    if (action is Map && !bridgeAllowed) {
      final warnedKey = bridge is String ? bridge : "<invalid>";
      if (_warnedBridges.add(warnedKey)) {
        LynxLogger.warn("LynxCardView", "动作 bridge 不在白名单，按钮按禁用渲染: $warnedKey");
      }
    }
    final actionKey = identityHashCode(action);
    final spent = once && _spentActions.contains(actionKey);
    final enabled = action is Map && bridgeAllowed && !disabled && !spent;
    Color background;
    Color foreground;
    switch (props["style"]) {
      case "secondary":
        background = palette.secondaryBg;
        foreground = palette.text;
        break;
      case "danger":
        background = palette.danger;
        foreground = Colors.white;
        break;
      default:
        background = palette.primary;
        foreground = Colors.white;
    }
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton(
        onPressed: enabled
            ? () {
                if (once) {
                  _refresh(() => _spentActions.add(actionKey));
                }
                _runAction(action, scope);
              }
            : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          _boundString(props["text"], scope),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }

  /// 执行按钮动作：深绑定 params、按需携带 state、Bridge 派发、
  /// 响应 `data` 合并回 data 作用域（规范 §4.5 action 对象）。
  Future<void> _runAction(
      Map<dynamic, dynamic> action, LynxCardScope scope) async {
    try {
      final bridge = action["bridge"] as String? ?? "";
      final dot = bridge.indexOf(".");
      final module = dot <= 0 ? bridge : bridge.substring(0, dot);
      final method = dot <= 0 ? "" : bridge.substring(dot + 1);
      final rawParams = scope.resolveValue(action["params"] ?? {});
      final params = rawParams is Map
          ? Map<String, dynamic>.from(rawParams)
          : <String, dynamic>{};
      final withState = action["withState"];
      if (withState is String && withState.isNotEmpty && _state.isNotEmpty) {
        params[withState] = Map<String, dynamic>.of(_state);
      }
      final result = await LynxBridge.instance.dispatch(<dynamic, dynamic>{
        "callId": "card_${DateTime.now().millisecondsSinceEpoch}",
        "module": module,
        "method": method,
        "params": params,
      });
      final applyTo = action["applyResultTo"];
      if (applyTo is String && applyTo.isNotEmpty) {
        final data = result["data"];
        if (data is Map) {
          widget.data.value = <String, dynamic>{
            ...widget.data.value,
            applyTo: data
          };
        }
      }
    } catch (e) {
      LynxLogger.warn("LynxCardView", "卡片动作执行失败", e);
    }
  }
}

extension _CardCollectionNodes on _LynxCardViewState {
  /// `list`：列表循环（规范 §4.6），超过 100 条截断。
  Widget _buildList(
      LynxCardNode node, BuildContext context, LynxCardScope scope) {
    final props = node.props;
    final body = props["body"];
    if (body is! LynxCardNode) {
      return const SizedBox.shrink();
    }
    final itemsRaw = scope.resolveValue(props["items"]);
    final items = itemsRaw is List ? itemsRaw : const <dynamic>[];
    final limit = LynxCardLimits.maxListItems;
    final count = items.length > limit ? limit : items.length;
    if (count == 0) {
      final empty = props["empty"];
      if (empty is LynxCardNode) {
        return _buildNode(empty, context, scope);
      }
      return const SizedBox.shrink();
    }
    final asRaw = props["as"];
    final as = asRaw is String && asRaw.isNotEmpty ? asRaw : "item";
    final gap = _numProp(props, "gap", 8);
    final children = <Widget>[
      for (var i = 0; i < count; i++)
        _buildNode(
          body,
          context,
          scope.child(as: as, item: items[i], index: i),
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _withGaps(children, gap),
    );
  }

  /// `chart`：水平条形图，`variant` 仅支持 "bar"（规范 §4.7）。
  Widget _buildChart(
      LynxCardNode node, BuildContext context, LynxCardScope scope) {
    final props = node.props;
    if (props["variant"] != "bar") {
      return const SizedBox.shrink();
    }
    final palette = _CardPalette.of(context);
    final itemsRaw = scope.resolveValue(props["items"]);
    final items = itemsRaw is List ? itemsRaw : const <dynamic>[];
    final rows = <MapEntry<String, num>>[];
    for (final item in items) {
      if (item is Map && item["value"] is num) {
        rows.add(MapEntry(
            LynxCardScope.stringify(item["label"]), item["value"] as num));
      }
    }
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    var maxPositive = 0.0;
    for (final row in rows) {
      if (row.value.toDouble() > maxPositive) {
        maxPositive = row.value.toDouble();
      }
    }
    final barColor = _colorProp(props, "color") ?? palette.primary;
    final children = <Widget>[
      for (final row in rows)
        Row(
          children: [
            SizedBox(
              width: 72,
              child: Text(
                row.key,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: palette.subtext),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 10,
                decoration: BoxDecoration(
                  color: palette.divider,
                  borderRadius: BorderRadius.circular(5),
                ),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: _barFraction(row.value, maxPositive),
                  child: Container(
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 64,
              child: Text(
                LynxCardScope.stringify(row.value),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12, color: palette.text),
              ),
            ),
          ],
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _withGaps(children, 6),
    );
  }

  /// 计算条形占比：最大值 ≤ 0 或值非正时归 0。
  double _barFraction(num value, double maxPositive) {
    if (maxPositive <= 0 || value <= 0) {
      return 0;
    }
    return (value / maxPositive).clamp(0.0, 1.0);
  }

  /// 未知 `type`：灰色次级小字占位，不展开 children（规范 §7）。
  Widget _buildUnsupported(LynxCardNode node, BuildContext context) {
    return Text(
      "不支持组件 ${node.type}",
      style: TextStyle(
        fontSize: 12,
        color: _CardPalette.of(context).subtext,
      ),
    );
  }
}

/// 读取 num 类型属性并转 double；类型不符回退 [fallback]。
double _numProp(Map<String, dynamic> props, String key, double fallback) {
  final value = props[key];
  return value is num ? value.toDouble() : fallback;
}

/// 读取 num 类型属性；缺失或类型不符返回 null。
double? _numOrNull(Map<String, dynamic> props, String key) {
  final value = props[key];
  return value is num ? value.toDouble() : null;
}

/// 读取颜色属性（`#RRGGBB`/`#RRGGBBAA`）；类型不符或非法返回 null。
Color? _colorProp(Map<String, dynamic> props, String key) {
  final value = props[key];
  if (value is String) {
    return _parseCardColor(value);
  }
  return null;
}

/// 绑定求值后取字符串：整串绑定保留原类型，非字符串 stringify。
String _boundString(dynamic raw, LynxCardScope scope) {
  final value = scope.resolveValue(raw);
  if (value is String) {
    return value;
  }
  return LynxCardScope.stringify(value);
}

/// 文本长度超限截断并追加省略号（`LynxCardLimits.maxTextLength`）。
String _applyTextLimit(String text) {
  final limit = LynxCardLimits.maxTextLength;
  if (text.length > limit) {
    return "${text.substring(0, limit)}…";
  }
  return text;
}

/// 解析字重：`"normal"`/`"medium"`/`"bold"` 或 100–900 数字，非法回退常规。
FontWeight _parseWeight(dynamic raw) {
  switch (raw) {
    case "medium":
      return FontWeight.w500;
    case "bold":
      return FontWeight.w700;
    default:
      break;
  }
  if (raw is num) {
    const weights = [
      FontWeight.w100,
      FontWeight.w200,
      FontWeight.w300,
      FontWeight.w400,
      FontWeight.w500,
      FontWeight.w600,
      FontWeight.w700,
      FontWeight.w800,
      FontWeight.w900,
    ];
    final index = (raw / 100).round().clamp(1, 9) - 1;
    return weights[index];
  }
  return FontWeight.w400;
}

/// 解析容器交叉轴对齐，默认 `stretch`（规范 §4.1）。
CrossAxisAlignment _parseCrossAlign(dynamic raw) {
  switch (raw) {
    case "start":
      return CrossAxisAlignment.start;
    case "center":
      return CrossAxisAlignment.center;
    case "end":
      return CrossAxisAlignment.end;
    default:
      return CrossAxisAlignment.stretch;
  }
}

/// 解析文本对齐：`start`/`center`/`end`，默认 `start`（规范 §4.2）。
TextAlign _parseTextAlign(dynamic raw) {
  switch (raw) {
    case "center":
      return TextAlign.center;
    case "end":
      return TextAlign.end;
    default:
      return TextAlign.start;
  }
}
