/// lynx-card/1 文本模板的解析器与作用域绑定求值。
///
/// 规范全文见 `docs/lynx-card-format.md`，该文档即本文件实现契约：
/// - [LynxCardDocument.parse] 把模板文本解析为组件树，超长 / 超深 /
///   坏 JSON / 坏信封 / 节点超限整体拒绝并抛 [LynxCardParseError]；
/// - [LynxCardScope] 负责渲染期 `{{path}}` 绑定与插值求值；
/// - 未知组件类型不拒绝，由渲染器降级为占位。
library;

import "dart:convert";

/// lynx-card/1 的资源上限（规范 §7）。
class LynxCardLimits {
  /// 源文本最大字节数（256 KiB），超长整体拒绝。
  static const int maxSourceBytes = 256 * 1024;

  /// 括号嵌套最大深度：预扫描与节点递归共用，超限整体拒绝。
  static const int maxDepth = 32;

  /// 解析后节点总数上限，超限整体拒绝。
  static const int maxNodes = 512;

  /// `list` 组件渲染条数上限，超出截断（防抖）。
  static const int maxListItems = 100;

  /// 单段渲染文本的最大长度。
  static const int maxTextLength = 10000;

  const LynxCardLimits._();
}

/// 模板解析失败异常。
///
/// [code] 为固定错误码，供宿主区分失败原因：
/// "length-exceeded"（源超长）、"depth-exceeded"（嵌套超深）、
/// "bad-json"（非法 JSON）、"bad-envelope"（信封结构非法）、
/// "too-many-nodes"（节点超限）。
class LynxCardParseError implements Exception {
  /// 固定错误码，取值见类文档。
  final String code;

  /// 人类可读的错误说明。
  final String message;

  const LynxCardParseError(this.message, {this.code = "invalid"});

  @override
  String toString() => "LynxCardParseError($code): $message";
}

/// 解析后的单个组件节点。
class LynxCardNode {
  /// 组件类型名（如 "container"/"text"）；
  /// 未知类型照常保留，由渲染器降级为占位。
  final String type;

  /// 原始未绑定属性（不含已归一的 `children`）。
  final Map<String, dynamic> props;

  /// 子节点；仅 `container` 的 `children` 归一至此，其余类型为空列表。
  final List<LynxCardNode> children;

  const LynxCardNode(this.type, this.props, this.children);
}

/// 信封 body 的递归树解析：控制嵌套深度、统计节点数、归一 children。
class _LynxCardTreeParser {
  int _count = 0;

  LynxCardNode parseRoot(Map<dynamic, dynamic> raw) {
    return _parseNode(raw, 1);
  }

  LynxCardNode _parseNode(Map<dynamic, dynamic> raw, int depth) {
    if (depth > LynxCardLimits.maxDepth) {
      throw LynxCardParseError(
        "节点嵌套超过 ${LynxCardLimits.maxDepth} 层上限",
        code: "depth-exceeded",
      );
    }
    _count += 1;
    if (_count > LynxCardLimits.maxNodes) {
      throw LynxCardParseError(
        "节点总数超过 ${LynxCardLimits.maxNodes} 上限",
        code: "too-many-nodes",
      );
    }
    final type = raw["type"];
    if (type is! String) {
      throw const LynxCardParseError(
        "节点缺少字符串 type 字段",
        code: "bad-envelope",
      );
    }
    // children 单独归一，不进 props，避免渲染器深绑属性时重复展开。
    final props = <String, dynamic>{};
    raw.forEach((key, value) {
      if (key != "children") {
        props[key.toString()] = value;
      }
    });
    // 仅 container 归一 children；其余类型（含未知类型）一律空 children，
    // 未知类型的子树不展开（规范 §7 降级表）。
    final children = <LynxCardNode>[];
    if (type == "container") {
      final rawChildren = raw["children"];
      if (rawChildren is List) {
        for (final rawChild in rawChildren) {
          // 子项非 Map 的条目跳过（单点降级，不整体失败）。
          if (rawChild is Map) {
            children.add(_parseNode(rawChild, depth + 1));
          }
        }
      }
    }
    // list 的 body/empty 是节点型属性：与 children 同样在解析期归一，
    // 保证嵌套深度与节点总数单点核算，渲染器直接拿 LynxCardNode 不做二次解析。
    if (type == "list") {
      for (final nodeProp in const ["body", "empty"]) {
        final rawNode = raw[nodeProp];
        if (rawNode is Map) {
          props[nodeProp] = _parseNode(rawNode, depth + 1);
        }
      }
    }
    return LynxCardNode(type, props, children);
  }
}

/// 一份解析完成的 lynx-card/1 文档。
class LynxCardDocument {
  /// 信封格式标识，`format` 字段必须精确等于该值（规范 §9）。
  static const String _formatId = "lynx-card/1";

  /// UTF-8 BOM 字符。
  static const String _bom = "\uFEFF";

  /// 代码栅栏语言标识（可选出现，如 json/json5/c++）。
  static final RegExp _fenceLangPattern = RegExp(r"^[A-Za-z0-9_\-+#.]+$");

  /// 信封 `state`：卡片本地初始 state，缺失或非对象时为空对象兜底。
  final Map<String, dynamic> state;

  /// 根节点（信封 `body`）。
  final LynxCardNode root;

  const LynxCardDocument({required this.state, required this.root});

  /// 判断源文本是否疑似 lynx-card/1 信封（规范 §8：移动端据此拦截）。
  ///
  /// 廉价启发式，不做完整 JSON 解码：剥去 BOM / 代码栅栏后须以 `{` 开头、
  /// 且含字面量 `"lynx-card/1"`。即使 JSON 残缺也返回 true，让上层抛出
  /// 带指引的错误，而不是把文本静默喂给真引擎。
  static bool looksLikeLynxCard(String source) {
    final text = _stripEnvelope(source);
    return text.startsWith("{") && text.contains("\"$_formatId\"");
  }

  /// 剥离源文本的 BOM、首尾空白与一层 Markdown 代码栅栏。
  static String _stripEnvelope(String source) {
    var text = source;
    if (text.startsWith(_bom)) {
      text = text.substring(_bom.length);
    }
    text = text.trim();
    return _stripCodeFence(text);
  }

  /// 剥一层代码栅栏：首行 ```[lang]，末行 ```（其后仅允许空白）。
  static String _stripCodeFence(String text) {
    if (!text.startsWith("```")) {
      return text;
    }
    final firstNewline = text.indexOf("\n");
    if (firstNewline < 0) {
      return text;
    }
    final header = text.substring(0, firstNewline).trim();
    final lang = header.substring(3).trim();
    // 语言标识可选；存在时须形如常见语言单词，否则不视为栅栏。
    if (lang.isNotEmpty && !_fenceLangPattern.hasMatch(lang)) {
      return text;
    }
    var body = text.substring(firstNewline + 1);
    final close = body.lastIndexOf("```");
    if (close < 0) {
      return text;
    }
    if (body.substring(close + 3).trim().isNotEmpty) {
      // 闭合栅栏之后还有实质内容，不视为栅栏包裹。
      return text;
    }
    body = body.substring(0, close);
    if (body.endsWith("\r\n")) {
      body = body.substring(0, body.length - 2);
    } else if (body.endsWith("\n") || body.endsWith("\r")) {
      body = body.substring(0, body.length - 1);
    }
    return body;
  }

  /// 线性扫描统计括号嵌套峰值；
  /// 字符串字面量内的括号也计入（规范 §7：保守）。
  static int _maxBracketDepth(String text) {
    var depth = 0;
    var peak = 0;
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit == 0x7B || unit == 0x5B) {
        depth += 1;
        if (depth > peak) {
          peak = depth;
        }
      } else if (unit == 0x7D || unit == 0x5D) {
        depth -= 1;
        if (depth < 0) {
          // 括号不配对时截为 0，避免负深度掩盖后续真实嵌套。
          depth = 0;
        }
      }
    }
    return peak;
  }

  /// 深拷贝 JSON 值（对象键统一为字符串）。
  static dynamic _deepCopy(dynamic value) {
    if (value is Map) {
      final copy = <String, dynamic>{};
      value.forEach((key, v) {
        copy[key.toString()] = _deepCopy(v);
      });
      return copy;
    }
    if (value is List) {
      return value.map(_deepCopy).toList();
    }
    return value;
  }

  /// 解析模板文本；命中任一整体拒绝条件即抛 [LynxCardParseError]。
  static LynxCardDocument parse(String source) {
    // 长度两道闸：先按字符数廉价拒绝（字符数 ≤ UTF-8 字节数，超了必超），
    // 再精确统计 UTF-8 字节数。
    if (source.length > LynxCardLimits.maxSourceBytes) {
      throw const LynxCardParseError(
        "源文本超过 256 KiB 上限",
        code: "length-exceeded",
      );
    }
    if (utf8.encode(source).length > LynxCardLimits.maxSourceBytes) {
      throw const LynxCardParseError(
        "源文本 UTF-8 字节数超过 256 KiB 上限",
        code: "length-exceeded",
      );
    }

    final text = _stripEnvelope(source);

    // 括号深度预扫描必须先于 jsonDecode：
    // 防止深嵌套文本把 dart:convert 的递归解码打出栈溢出。
    if (_maxBracketDepth(text) > LynxCardLimits.maxDepth) {
      throw LynxCardParseError(
        "JSON 括号嵌套深度超过 ${LynxCardLimits.maxDepth} 上限",
        code: "depth-exceeded",
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const LynxCardParseError("源文本不是合法 JSON", code: "bad-json");
    }
    if (decoded is! Map) {
      throw const LynxCardParseError(
        "顶层必须是 JSON 对象",
        code: "bad-envelope",
      );
    }
    if (decoded["format"] != _formatId) {
      final actual = decoded["format"];
      throw LynxCardParseError(
        "format 必须精确为 \"$_formatId\"（模型提示语须要求输出该版本），"
        "实际为 $actual",
        code: "bad-envelope",
      );
    }

    // state 深拷贝留用，与解析树隔离，避免渲染期间被外部改动。
    final state = <String, dynamic>{};
    final rawState = decoded["state"];
    if (rawState is Map) {
      rawState.forEach((key, value) {
        state[key.toString()] = _deepCopy(value);
      });
    }

    final rawBody = decoded["body"];
    if (rawBody is! Map) {
      throw const LynxCardParseError(
        "信封缺少 body 字段或 body 不是节点对象",
        code: "bad-envelope",
      );
    }

    final root = _LynxCardTreeParser().parseRoot(rawBody);
    return LynxCardDocument(state: state, root: root);
  }
}

/// 渲染期作用域：data（宿主数据）+ state（卡片本地）+ locals（循环局部）。
///
/// 三层命名空间隔离（规范 §3.1）：state 只能经 `state.` 前缀访问，
/// 宿主注入名为 `state` 的顶层 key 无法渗透进卡片 state，反之亦然。
class LynxCardScope {
  /// 宿主数据层（initialData 与运行时合并结果），路径直接引用。
  final Map<String, dynamic> data;

  /// 卡片本地 state 层，必须经 `state.` 前缀访问。
  final Map<String, dynamic> state;

  /// list 循环的 item / index 局部层，默认为空。
  final Map<String, dynamic> locals;

  const LynxCardScope({
    required this.data,
    required this.state,
    this.locals = const {},
  });

  /// 整串精确绑定 `{{path}}`（容忍内部空白，路径字符集 [A-Za-z0-9_.-]）。
  static final RegExp _exactBinding = RegExp(
    r"^\{\{\s*([A-Za-z0-9_.\-]+)\s*\}\}$",
  );

  /// 字符串内单个 `{{path}}` 绑定片段。
  static final RegExp _binding = RegExp(r"\{\{\s*([A-Za-z0-9_.\-]+)\s*\}\}");

  /// 按路径求值：`state.` 前缀走 state 层（裸 `state` 返回整个 state 表）；
  /// 否则首段命中 locals 时从 locals 开始（如 `{{item}}`/`{{item.x}}`）；
  /// 再否则落到 data 层。当前值为 List 时段须是数字下标（越界 / 非数字→null），
  /// 当前值为 Map 时按键取（缺失→null），当前值为标量 / null 时直接 null。
  dynamic resolve(String path) {
    final segments = path.split(".");
    final first = segments.first;
    dynamic current;
    Iterable<String> rest;
    if (first == "state") {
      current = state;
      rest = segments.skip(1);
    } else if (locals.containsKey(first)) {
      current = locals[first];
      rest = segments.skip(1);
    } else {
      current = data;
      rest = segments;
    }
    for (final segment in rest) {
      if (current is List) {
        final index = int.tryParse(segment);
        if (index == null || index < 0 || index >= current.length) {
          return null;
        }
        current = current[index];
      } else if (current is Map) {
        current = current[segment];
      } else {
        // 标量或 null 之后仍有路径段：视为缺失。
        return null;
      }
    }
    return current;
  }

  /// 对属性值做绑定求值：
  /// - 字符串整串恰为 `{{path}}` 时返回路径的**原类型值**；
  /// - 字符串内嵌若干 `{{path}}` 时做插值，缺失路径插为空串；
  /// - Map / List 递归深绑并构造新容器（不改写原对象）；
  /// - 其他标量原样返回。
  dynamic resolveValue(dynamic value) {
    if (value is String) {
      final exact = _exactBinding.firstMatch(value);
      if (exact != null) {
        return resolve(exact.group(1)!);
      }
      return value.replaceAllMapped(_binding, (match) {
        return stringify(resolve(match.group(1)!));
      });
    }
    if (value is Map) {
      final bound = <String, dynamic>{};
      value.forEach((key, v) {
        bound[key.toString()] = resolveValue(v);
      });
      return bound;
    }
    if (value is List) {
      return value.map(resolveValue).toList();
    }
    return value;
  }

  /// 生成叠加循环局部变量（`as` 命名的 item 与内置 `index`）的子作用域。
  LynxCardScope child({String? as, dynamic item, int? index}) {
    final merged = Map<String, dynamic>.from(locals);
    if (as != null) {
      merged[as] = item;
    }
    if (index != null) {
      merged["index"] = index;
    }
    return LynxCardScope(data: data, state: state, locals: merged);
  }

  /// 标量转字符串（规范 §3.2）：null→空串；整数保持整型书写；
  /// 整值浮点省略小数尾零（25.0→"25"）；bool→"true"/"false"；
  /// 其余 toString()。
  static String stringify(dynamic value) {
    if (value == null) {
      return "";
    }
    if (value is num) {
      return _numToString(value);
    }
    return value.toString();
  }

  static String _numToString(num value) {
    if (value is int) {
      return value.toString();
    }
    final d = value.toDouble();
    if (d.isFinite && d == d.truncateToDouble()) {
      if (d.abs() < 9.2e18) {
        // 常规范围整值浮点：直接取整书写。
        return d.truncate().toString();
      }
      // 超出 int 表示范围的整值大数：兜底去掉 toString 的 ".0" 尾缀。
      final text = d.toString();
      return text.endsWith(".0") ? text.substring(0, text.length - 2) : text;
    }
    return d.toString();
  }
}
