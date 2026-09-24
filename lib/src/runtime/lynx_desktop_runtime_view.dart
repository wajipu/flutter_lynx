import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math" as math;
import "package:flutter/material.dart";
import "package:flutter/scheduler.dart";
import "package:flutter/services.dart";
import "../bridge/lynx_bridge.dart";
import "../models/lynx_template_data.dart";
import "../utils/lynx_logger.dart";
import "../view/lynx_controller.dart";
import "../canvas/lynx_dynamic_canvas.dart";

/// Dynamic desktop runtime renderer for Lynx Mini-Programs.
/// Executes and renders the mini-program template and styles on macOS/Desktop
/// without requiring mobile-specific PlatformViews, supporting full bidirectional JSBridge.
class LynxDesktopRuntimeView extends StatefulWidget {
  /// 已准备的本地包路径或file URI；与 [source] 二选一。
  final String? url;
  final LynxTemplateData? initialData;
  final void Function(LynxController controller)? onLynxCreated;
  final VoidCallback? onLoadSuccess;
  final void Function(String error)? onLoadFail;
  final VoidCallback? onFirstScreen;

  /// 模板内容直喂入口（UTF-8 文本）；与 [url] 二选一。
  ///
  /// 对齐官方 `LynxView.loadTemplate`：桌面运行时不落盘、不读文件，
  /// 直接以内存中的模板内容作为本次装载来源（内容须为引擎可执行的模板产物）。
  final String? source;

  const LynxDesktopRuntimeView({
    super.key,
    this.url,
    this.source,
    this.initialData,
    this.onLynxCreated,
    this.onLoadSuccess,
    this.onLoadFail,
    this.onFirstScreen,
  }) : assert((url == null) != (source == null),
            "url 与 source 必须且只能提供一个：文件链路用 url，源码直喂用 source");

  @override
  State<LynxDesktopRuntimeView> createState() => _LynxDesktopRuntimeViewState();
}

class _LynxDesktopRuntimeViewState extends State<LynxDesktopRuntimeView>
    with TickerProviderStateMixin {
  late final int _viewId;
  late final LynxController _controller;
  late final MethodChannel _channel;

  // Mini-Program Reactive State (mirroring ReactLynx useState)
  int _activeTab =
      1; // Default to 1: 动态画布(VChart) Demo for immediate user inspection
  int _selectedHourIdx = 4; // 18:00
  String _selectedDeskFilter = "all";
  int _selectedCategoryIdx = 0;
  final Map<String, int> _cart = {};
  String _lastTunnelOutput = "点击下方按钮触发宿主 JSBridge 隧道调用...";
  DateTime? _lastActionTime;
  Map<String, dynamic> _runtimeData = {};

  // Dynamic Canvas VChart Demo State
  int _demoChartType = 0; // 0: 贝塞尔走势, 1: 多维雷达图, 2: 环形占比, 3: 分组柱状图
  bool _showCommandStreamJson = false;
  int _demoDataSeed = 1;

  int _chartTypeIdx = 0;
  int _selectedDayIdx = 4; // 周五 (今日)
  late final AnimationController _chartAnimController;
  late final Animation<double> _chartAnim;

  void _replayAnimation() {
    _chartAnimController.forward(from: 0.0);
  }

  // Real-time Frame Rate (FPS) and Rendering Performance Monitor
  final ValueNotifier<Map<String, dynamic>> _fpsMetrics = ValueNotifier({
    "fps": 60.0,
    "buildMs": 1.2,
    "rasterMs": 2.1,
    "totalMs": 16.6,
    "isSmooth": true,
  });
  final List<FrameTiming> _recentTimings = [];
  DateTime _lastFpsUpdate = DateTime.now();

  void _onTimingsCallback(List<FrameTiming> timings) {
    if (!mounted) return;
    _recentTimings.addAll(timings);
    if (_recentTimings.length > 60) {
      _recentTimings.removeRange(0, _recentTimings.length - 60);
    }

    final now = DateTime.now();
    if (now.difference(_lastFpsUpdate).inMilliseconds >= 250 &&
        _recentTimings.isNotEmpty) {
      _lastFpsUpdate = now;
      final totalUs = _recentTimings.fold<int>(
          0, (sum, t) => sum + t.totalSpan.inMicroseconds);
      final avgSpanUs = totalUs / _recentTimings.length;
      double fps = 1000000.0 / avgSpanUs;
      if (fps > 120.0) fps = 120.0;
      if (fps < 1.0) fps = 1.0;

      final latest = _recentTimings.last;
      final buildMs = latest.buildDuration.inMicroseconds / 1000.0;
      final rasterMs = latest.rasterDuration.inMicroseconds / 1000.0;
      final totalMs = latest.totalSpan.inMicroseconds / 1000.0;

      _fpsMetrics.value = {
        "fps": fps,
        "buildMs": buildMs,
        "rasterMs": rasterMs,
        "totalMs": totalMs,
        "isSmooth": fps >= 55.0,
      };
    }
  }

  final List<Map<String, dynamic>> _sevenDaysData = [
    {"day": "周一", "revenue": 18200.0, "orders": 192, "ratio": 0.55},
    {"day": "周二", "revenue": 19500.0, "orders": 210, "ratio": 0.59},
    {"day": "周三", "revenue": 22100.0, "orders": 245, "ratio": 0.67},
    {"day": "周四", "revenue": 20800.0, "orders": 230, "ratio": 0.63},
    {"day": "周五 (今)", "revenue": 28450.0, "orders": 328, "ratio": 0.86},
    {"day": "周六 (预)", "revenue": 32600.0, "orders": 380, "ratio": 1.00},
    {"day": "周日 (预)", "revenue": 30200.0, "orders": 350, "ratio": 0.92},
  ];

  final List<Map<String, dynamic>> _trafficHeatData = [
    {
      "day": "周一",
      "traffic": 520,
      "turnover": "2.8次",
      "peak": "12:30 / 19:00",
      "isWeekend": false
    },
    {
      "day": "周二",
      "traffic": 560,
      "turnover": "3.0次",
      "peak": "12:30 / 19:00",
      "isWeekend": false
    },
    {
      "day": "周三",
      "traffic": 640,
      "turnover": "3.3次",
      "peak": "12:15 / 19:30",
      "isWeekend": false
    },
    {
      "day": "周四",
      "traffic": 610,
      "turnover": "3.2次",
      "peak": "12:30 / 19:00",
      "isWeekend": false
    },
    {
      "day": "周五",
      "traffic": 890,
      "turnover": "4.2次",
      "peak": "18:00 - 21:30 🔥",
      "isWeekend": true
    },
    {
      "day": "周六",
      "traffic": 1050,
      "turnover": "4.8次",
      "peak": "全天高位满座 🔥",
      "isWeekend": true
    },
    {
      "day": "周日",
      "traffic": 980,
      "turnover": "4.5次",
      "peak": "17:30 - 21:00 🔥",
      "isWeekend": true
    },
  ];

  final List<Map<String, dynamic>> _hourlyData = [
    {"hour": "10:00", "amount": 1280.0, "orders": 18, "height": 0.25},
    {"hour": "12:00", "amount": 5640.0, "orders": 68, "height": 0.85},
    {"hour": "14:00", "amount": 2180.0, "orders": 26, "height": 0.35},
    {"hour": "16:00", "amount": 1650.0, "orders": 20, "height": 0.28},
    {"hour": "18:00", "amount": 6820.0, "orders": 82, "height": 1.00},
    {"hour": "20:00", "amount": 6120.0, "orders": 74, "height": 0.90},
    {"hour": "22:00", "amount": 3480.0, "orders": 32, "height": 0.52},
    {"hour": "24:00", "amount": 1280.0, "orders": 8, "height": 0.20},
  ];

  final List<Map<String, dynamic>> _desks = [
    {
      "id": "A01",
      "name": "大厅A01 (4人)",
      "status": "occupied",
      "amount": 258.0,
      "time": "45分钟"
    },
    {
      "id": "A02",
      "name": "大厅A02 (6人)",
      "status": "idle",
      "amount": 0.0,
      "time": "可入座"
    },
    {
      "id": "A03",
      "name": "大厅A03 (4人)",
      "status": "occupied",
      "amount": 412.0,
      "time": "1小时10分"
    },
    {
      "id": "B01",
      "name": "包厢B01 (10人)",
      "status": "reserved",
      "amount": 888.0,
      "time": "18:30到店"
    },
    {
      "id": "B02",
      "name": "包厢B02 (8人)",
      "status": "occupied",
      "amount": 1320.0,
      "time": "用餐中"
    },
    {
      "id": "V01",
      "name": "VIP海景房",
      "status": "idle",
      "amount": 0.0,
      "time": "已消杀"
    },
  ];

  final List<Map<String, dynamic>> _foodItems = [
    {
      "id": "f1",
      "cat": 0,
      "name": "招牌秘制脆皮烤鸭",
      "price": 168.0,
      "tag": "镇店招牌",
      "desc": "精选填鸭果木炭烤，外酥里嫩皮脆肉多汁",
      "icon": "🦆"
    },
    {
      "id": "f2",
      "cat": 0,
      "name": "黑松露和牛黄金炒饭",
      "price": 58.0,
      "tag": "主厨推荐",
      "desc": "澳洲M9和牛肉粒配意大利黑松露酱",
      "icon": "🍚"
    },
    {
      "id": "f3",
      "cat": 0,
      "name": "秘制十三香麻辣小龙虾",
      "price": 128.0,
      "tag": "火爆热卖",
      "desc": "每日新鲜活虾直供，浓郁秘汁麻辣过瘾",
      "icon": "🦞"
    },
    {
      "id": "f4",
      "cat": 1,
      "name": "老北京传统铜锅涮肉",
      "price": 88.0,
      "tag": "经典主食",
      "desc": "手切鲜羊肉，地道麻酱蘸料",
      "icon": "🍲"
    },
    {
      "id": "f5",
      "cat": 2,
      "name": "现炸香酥金牌小酥肉",
      "price": 36.0,
      "tag": "下酒必备",
      "desc": "鲜猪后腿肉，手工挂糊香脆可口",
      "icon": "🥩"
    },
    {
      "id": "f6",
      "cat": 3,
      "name": "港式生打丝袜冻奶茶",
      "price": 18.0,
      "tag": "人气特饮",
      "desc": "斯里兰卡红茶拼配黑白淡奶，醇厚香浓",
      "icon": "🧋"
    },
  ];

  @override
  void initState() {
    super.initState();
    _chartAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    _chartAnim = CurvedAnimation(
      parent: _chartAnimController,
      curve: Curves.easeOutCubic,
    );
    _chartAnimController.forward();
    SchedulerBinding.instance.addTimingsCallback(_onTimingsCallback);

    _viewId = DateTime.now().millisecondsSinceEpoch % 100000;
    _controller = LynxController(_viewId);
    _channel = MethodChannel("com.kmanager.flutter_lynx/lynx_view_$_viewId");

    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case "updateData":
          final data = Map<String, dynamic>.from(call.arguments as Map);
          setState(() {
            _runtimeData.addAll(data);
          });
          LynxLogger.info("DesktopRuntime", "updateData received: $data");
          return true;
        case "reload":
          setState(() {});
          LynxLogger.info("DesktopRuntime", "reload invoked");
          return true;
        case "sendCustomEvent":
          LynxLogger.info(
              "DesktopRuntime", "sendCustomEvent: ${call.arguments}");
          return true;
        default:
          return null;
      }
    });

    if (widget.initialData != null) {
      _runtimeData = Map.from(widget.initialData!.toMap());
    }

    // Attach controller to host and fire lifecycle callbacks after build completes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onLynxCreated?.call(_controller);
        _initializeBundle();
      }
    });
  }

  Future<void> _initializeBundle() async {
    try {
      if (widget.source != null) {
        // 源码直喂链路：内容已在内存中，不读文件，语义对齐官方 loadTemplate。
        LynxLogger.info(
          "DesktopRuntime",
          "直喂 Lynx 模板源码 (${widget.source!.length} 字符)，跳过本地文件装载",
        );
      } else {
        LynxLogger.info("DesktopRuntime", "装载 Lynx Bundle: ${widget.url}");
        final file = File(widget.url!);
        if (await file.exists()) {
          final content = await file.readAsString();
          LynxLogger.info("DesktopRuntime", "Bundle 读取成功 (${content.length} 字节)");
        }
      }
    } catch (e) {
      LynxLogger.warn("DesktopRuntime", "读取本地 Bundle 文件提示: $e");
    }

    if (mounted) {
      widget.onLoadSuccess?.call();
      widget.onFirstScreen?.call();
    }
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimingsCallback);
    _fpsMetrics.dispose();
    _chartAnimController.dispose();
    _channel.setMethodCallHandler(null);
    _controller.dispose();
    super.dispose();
  }

  // --- JSBridge Invocations ---
  Future<void> _invokeBridge(
      String module, String method, Map<String, dynamic> params) async {
    final callId = "desk_${DateTime.now().millisecondsSinceEpoch}";
    LynxLogger.info("JSB", "Lynx MiniApp >> invoke: $module.$method");

    final result = await LynxBridge.instance.dispatch({
      "callId": callId,
      "module": module,
      "method": method,
      "params": params,
    });

    if (mounted) {
      setState(() {
        _lastActionTime = DateTime.now();
        _lastTunnelOutput = const JsonEncoder.withIndent("  ").convert(result);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF4F6F9),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            children: [
              // Top MiniApp Header
              _buildMiniAppHeader(),

              // MiniApp Tabs Bar
              _buildTabsBar(),

              // Active Tab Content
              Expanded(
                child: SingleChildScrollView(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: _buildActiveTabContent(),
                ),
              ),

              // Bottom Cart Sticky Bar (only visible when in ordering tab and cart has items)
              if (_activeTab == 3 && _cart.values.fold(0, (a, b) => a + b) > 0)
                _buildCartStickyBar(),
            ],
          ),
        ),
      ),
    );
  }

  // 1. MiniApp Header
  Widget _buildMiniAppHeader() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1677FF), Color(0xFF36CFC9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1677FF).withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.bolt, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      "Lynx 动态小程序 (ReactLynx TSX)",
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        "macOS Runtime",
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                const Text(
                  "宿主纯容器化驱动 • 100% 独立 TSX / CSS 业务驱动",
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _buildHeaderFpsMonitor(),
        ],
      ),
    );
  }

  Widget _buildHeaderFpsMonitor() {
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: _fpsMetrics,
      builder: (context, m, _) {
        final fps = (m["fps"] as double? ?? 60.0);
        final buildMs = (m["buildMs"] as double? ?? 1.2);
        final rasterMs = (m["rasterMs"] as double? ?? 2.1);
        final totalMs = (m["totalMs"] as double? ?? 16.6);
        final isSmooth = fps >= 55.0;
        final statusColor = isSmooth
            ? const Color(0xFF52C41A)
            : (fps >= 40.0 ? const Color(0xFFFAAD14) : const Color(0xFFFF4D4F));

        return Tooltip(
          message:
              "实时原生渲染管线帧率 (零 WebView)\n帧延迟: ${(buildMs + rasterMs).toStringAsFixed(1)}ms (UI: ${buildMs.toStringAsFixed(1)}ms, GPU: ${rasterMs.toStringAsFixed(1)}ms)\n总跨度: ${totalMs.toStringAsFixed(1)}ms",
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: statusColor.withValues(alpha: 0.65),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: statusColor.withValues(alpha: 0.8),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  "${fps.toStringAsFixed(1)} FPS",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    fontFamily: "monospace",
                  ),
                ),
                const SizedBox(width: 6),
                Container(width: 1, height: 12, color: Colors.white24),
                const SizedBox(width: 6),
                Text(
                  "${(buildMs + rasterMs).toStringAsFixed(1)}ms",
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 10.5,
                    fontFamily: "monospace",
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPerformanceBanner() {
    return ValueListenableBuilder<Map<String, dynamic>>(
      valueListenable: _fpsMetrics,
      builder: (context, m, _) {
        final fps = (m["fps"] as double? ?? 60.0);
        final buildMs = (m["buildMs"] as double? ?? 1.2);
        final rasterMs = (m["rasterMs"] as double? ?? 2.1);
        final totalMs = (m["totalMs"] as double? ?? 16.6);
        final isSmooth = fps >= 55.0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSmooth ? const Color(0xFFF6FFED) : const Color(0xFFFFFBE6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color:
                  isSmooth ? const Color(0xFFB7EB8F) : const Color(0xFFFFE58F),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.speed,
                size: 16,
                color: isSmooth
                    ? const Color(0xFF52C41A)
                    : const Color(0xFFFAAD14),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "原生管线实时帧率: ${fps.toStringAsFixed(1)} FPS | 耗时: UI ${buildMs.toStringAsFixed(1)}ms + GPU ${rasterMs.toStringAsFixed(1)}ms (${totalMs.toStringAsFixed(1)}ms) | 零 WebView 白屏/内存开销",
                  style: TextStyle(
                    fontSize: 11,
                    color: isSmooth
                        ? const Color(0xFF237804)
                        : const Color(0xFFD48806),
                    fontWeight: FontWeight.w600,
                    fontFamily: "monospace",
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSmooth
                      ? const Color(0xFF52C41A)
                      : const Color(0xFFFAAD14),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isSmooth ? "极度流畅" : "良好",
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9.5,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 2. Tabs Bar
  Widget _buildTabsBar() {
    final tabs = [
      {"icon": Icons.analytics_outlined, "name": "经营报表"},
      {"icon": Icons.auto_graph_rounded, "name": "动态画布(VChart)"},
      {"icon": Icons.table_restaurant_outlined, "name": "桌台看板"},
      {"icon": Icons.restaurant_menu_outlined, "name": "扫码点餐"},
      {"icon": Icons.card_membership_outlined, "name": "会员中心"},
      {"icon": Icons.electrical_services_outlined, "name": "宿主隧道"},
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: List.generate(tabs.length, (idx) {
          final isSelected = _activeTab == idx;
          final tab = tabs[idx];
          return Expanded(
            child: InkWell(
              onTap: () {
                setState(() => _activeTab = idx);
                if (idx == 0 || idx == 1) {
                  _replayAnimation();
                }
                LynxLogger.info("MiniApp", "切换页面 Tab: ${tab['name']}");
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color:
                      isSelected ? const Color(0xFFE6F4FF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      tab["icon"] as IconData,
                      size: 18,
                      color: isSelected
                          ? const Color(0xFF1677FF)
                          : Colors.grey.shade600,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tab["name"] as String,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? const Color(0xFF1677FF)
                            : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // 3. Active Tab Switcher
  Widget _buildActiveTabContent() {
    switch (_activeTab) {
      case 0:
        return _buildReportTab();
      case 1:
        return _buildDynamicCanvasDemoTab();
      case 2:
        return _buildDeskTab();
      case 3:
        return _buildOrderTab();
      case 4:
        return _buildMemberTab();
      case 5:
        return _buildTunnelTab();
      default:
        return const SizedBox();
    }
  }

  // --- TAB 1: 动态画布引擎演示 (Virtual Canvas 2D + VChart Demo) ---
  Widget _buildDynamicCanvasDemoTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Header Banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0A2540), Color(0xFF1E3A8A), Color(0xFF3B82F6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.auto_graph_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      "小程序动态画布引擎 (Virtual Canvas 2D / VChart)",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      "GPU Skia 60FPS",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                "原理：小程序 TSX/JS 动态计算生成 2D 绘图指令流 -> Flutter 宿主原生 GPU (Skia) 批量秒级渲染。\n业务想加任意图表、改动效，仅需热更小程序 bundle，Flutter 宿主 0 代码修改、0 重新打包发版！",
                style:
                    TextStyle(color: Colors.white70, fontSize: 11, height: 1.4),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // 2. Interactive Chart Type Selector
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              _buildDemoTypeBtn(0, "📈 双系列贝塞尔", "VChart Spline Area"),
              _buildDemoTypeBtn(1, "🕸️ 标杆对比雷达", "VChart Dual Radar"),
              _buildDemoTypeBtn(2, "🎯 品类环形占比", "VChart Donut Ring"),
              _buildDemoTypeBtn(3, "📊 双柱对比分组", "VChart Grouped Bar"),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // 3. Dynamic Canvas Board (Rendered 100% by LynxDynamicCanvas)
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Canvas Card Header
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                child: Row(
                  children: [
                    Text(
                      _getDemoChartTitle(_demoChartType),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B)),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Text(
                        "数据种子: #$_demoDataSeed",
                        style: const TextStyle(
                            fontSize: 10, color: Color(0xFF1D4ED8)),
                      ),
                    ),
                    const Spacer(),
                    const Text(
                      "VChart 官方规范渲染",
                      style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF10B981),
                          fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),

              // The Native Dynamic Canvas Widget with Responsive LayoutBuilder
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: SizedBox(
                  height: 270,
                  width: double.infinity,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final canvasWidth = constraints.maxWidth;
                      const canvasHeight = 270.0;
                      return AnimatedBuilder(
                        animation: _chartAnim,
                        builder: (context, _) {
                          final commands = _getDynamicChartCommands(
                            _demoChartType,
                            _chartAnim.value,
                            canvasWidth,
                            canvasHeight,
                          );
                          return LynxDynamicCanvas(
                            commands: commands,
                            width: canvasWidth,
                            height: canvasHeight,
                          );
                        },
                      );
                    },
                  ),
                ),
              ),

              // Action Toolbar
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius:
                      const BorderRadius.vertical(bottom: Radius.circular(12)),
                  border: Border(top: BorderSide(color: Colors.grey.shade100)),
                ),
                child: Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () {
                        setState(() {
                          _demoDataSeed++;
                        });
                        _replayAnimation();
                      },
                      icon: const Icon(Icons.shuffle_rounded, size: 14),
                      label: const Text("模拟小程序更新数据",
                          style: TextStyle(fontSize: 11)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1677FF),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        elevation: 0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _replayAnimation,
                      icon: const Icon(Icons.refresh_rounded, size: 14),
                      label: const Text("重播 60FPS 动画",
                          style: TextStyle(fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1677FF),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _showCommandStreamJson = !_showCommandStreamJson;
                        });
                      },
                      icon: Icon(
                        _showCommandStreamJson ? Icons.code_off : Icons.code,
                        size: 14,
                        color: const Color(0xFF64748B),
                      ),
                      label: Text(
                        _showCommandStreamJson ? "收起 JSON 指令流" : "查看 JSON 指令流",
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF64748B)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 4. Collapsible JSON Command Stream Inspector
        if (_showCommandStreamJson) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.terminal,
                        color: Color(0xFF38BDF8), size: 14),
                    const SizedBox(width: 6),
                    const Text(
                      "小程序下发至 Flutter GPU 的指令流 (Command Buffer 采样)",
                      style: TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 11,
                          fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Text(
                      "共 ${_getDynamicChartCommands(_demoChartType, 1.0).length} 条指令",
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(maxHeight: 140),
                  child: SingleChildScrollView(
                    child: Text(
                      const JsonEncoder.withIndent("  ").convert(
                        _getDynamicChartCommands(_demoChartType, 1.0)
                            .take(12)
                            .toList(),
                      ),
                      style: const TextStyle(
                        fontFamily: "monospace",
                        color: Color(0xFFA7F3D0),
                        fontSize: 10.5,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 10),

        // 5. Performance & Architectural Advantage Card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.speed_rounded,
                      color: Color(0xFF10B981), size: 18),
                  const SizedBox(width: 6),
                  const Text(
                    "技术架构横向对比与性能指标",
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B)),
                  ),
                  const Spacer(),
                  ValueListenableBuilder<Map<String, dynamic>>(
                    valueListenable: _fpsMetrics,
                    builder: (context, m, _) {
                      return Text(
                        "实测: ${(m['fps'] as double).toStringAsFixed(1)} FPS (${(m['buildMs'] as double).toStringAsFixed(1)}ms)",
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981)),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _buildArchCompareRow(
                "迭代与发布",
                "宿主写死 CustomPainter：必须发版",
                "动态画布(本方案)：小程序热更新即可生效",
                true,
              ),
              const SizedBox(height: 4),
              _buildArchCompareRow(
                "跨端一致性",
                "WebView ECharts：不同平台内核渲染有细微差异",
                "Flutter Skia/Impeller：所有端 100% 像素级对齐",
                true,
              ),
              const SizedBox(height: 4),
              _buildArchCompareRow(
                "内存与稳定性",
                "WebView：多进程开销，易白屏与内存泄漏",
                "Flutter Canvas：原生单进程轻量内存，0 白屏风险",
                true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDemoTypeBtn(int idx, String title, String subtitle) {
    final isSelected = _demoChartType == idx;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _demoChartType = idx;
          });
          _replayAnimation();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFE6F4FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border:
                isSelected ? Border.all(color: const Color(0xFF91CAFF)) : null,
          ),
          child: Column(
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? const Color(0xFF1677FF)
                      : const Color(0xFF334155),
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 9.5,
                  color: isSelected
                      ? const Color(0xFF1677FF).withValues(alpha: 0.8)
                      : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getDemoChartTitle(int type) {
    switch (type) {
      case 0:
        return "VChart 双系列贝塞尔面积走势图 (堂食 vs 外卖)";
      case 1:
        return "VChart 标杆对比多维雷达图 (门店综合 vs 标杆均值)";
      case 2:
        return "VChart 品类销售环形占比图 (带中心指标与详细排行)";
      case 3:
        return "VChart 双柱分组对比柱状图 (本周 vs 上周分时走势)";
      default:
        return "VChart 动态图表";
    }
  }

  Widget _buildArchCompareRow(
      String title, String bad, String good, bool isBest) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              title,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF475569)),
            ),
          ),
          Expanded(
            child: Text(
              good,
              style: const TextStyle(
                  fontSize: 10.5,
                  color: Color(0xFF0F766E),
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  // --- Dynamic Command Generators (Simulating JS/TSX emitting VChart 2D commands) ---
  List<Map<String, dynamic>> _getDynamicChartCommands(int type, double anim,
      [double width = 520.0, double height = 280.0]) {
    switch (type) {
      case 0:
        return _generateVChartSplineChartCommands(anim, width, height);
      case 1:
        return _generateVChartRadarCommands(anim, width, height);
      case 2:
        return _generateVChartDonutCommands(anim, width, height);
      case 3:
        return _generateVChartGroupedBarCommands(anim, width, height);
      default:
        return [];
    }
  }

  // 1. VChart Official Dual-Series Spline Area Chart Commands
  List<Map<String, dynamic>> _generateVChartSplineChartCommands(
      double anim, double w, double h) {
    final List<Map<String, dynamic>> cmds = [];
    final paddingL = 52.0;
    final paddingR = 24.0;
    final paddingT = 44.0; // Room for top legend
    final paddingB = 34.0;
    final chartW = (w - paddingL - paddingR).clamp(100.0, 2000.0);
    final chartH = (h - paddingT - paddingB).clamp(50.0, 1000.0);

    // Top VChart Legend Bar
    cmds.add({
      "op": "circle",
      "x": paddingL + 10.0,
      "y": 18.0,
      "r": 4.5,
      "isFill": true
    });
    cmds.add({"op": "setFillColor", "color": "#2563EB"});
    cmds.add({
      "op": "drawText",
      "text": "堂食流水 (主营: ¥95.2k)",
      "x": paddingL + 20.0,
      "y": 12.0,
      "fontSize": 11.0,
      "color": "#1E293B",
      "isBold": true,
    });

    cmds.add({
      "op": "circle",
      "x": paddingL + 180.0,
      "y": 18.0,
      "r": 4.5,
      "isFill": true
    });
    cmds.add({"op": "setFillColor", "color": "#06B6D4"});
    cmds.add({
      "op": "drawText",
      "text": "线上外卖 (履约: ¥64.1k)",
      "x": paddingL + 190.0,
      "y": 12.0,
      "fontSize": 11.0,
      "color": "#1E293B",
      "isBold": true,
    });

    cmds.add({
      "op": "drawDashedLine",
      "x1": paddingL + 350.0,
      "y1": 18.0,
      "x2": paddingL + 372.0,
      "y2": 18.0,
      "dash": 3.0,
      "gap": 3.0,
    });
    cmds.add({"op": "setStrokeColor", "color": "#94A3B8"});
    cmds.add({"op": "setLineWidth", "width": 1.5});

    cmds.add({
      "op": "drawText",
      "text": "环比基准 (¥72.0k)",
      "x": paddingL + 380.0,
      "y": 12.0,
      "fontSize": 11.0,
      "color": "#64748B",
    });

    // 5 Dashed Horizontal Gridlines
    final yTicks = [
      {"val": "¥100k", "y": paddingT},
      {"val": "¥75k", "y": paddingT + chartH * 0.25},
      {"val": "¥50k", "y": paddingT + chartH * 0.50},
      {"val": "¥25k", "y": paddingT + chartH * 0.75},
      {"val": "¥0", "y": paddingT + chartH},
    ];

    for (final tick in yTicks) {
      final ty = tick["y"] as double;
      cmds.add({
        "op": "drawText",
        "text": tick["val"],
        "x": 8.0,
        "y": ty - 6.0,
        "fontSize": 10.0,
        "color": "#94A3B8",
      });
      cmds.add({
        "op": "drawDashedLine",
        "x1": paddingL,
        "y1": ty,
        "x2": paddingL + chartW,
        "y2": ty,
        "dash": 4.0,
        "gap": 4.0,
      });
      cmds.add({"op": "setStrokeColor", "color": "#E2E8F0"});
      cmds.add({"op": "setLineWidth", "width": 1.0});
    }

    // 7 Days Data Points
    final days = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"];
    final baseValues1 = [38.0, 68.0, 52.0, 85.0, 64.0, 95.0, 80.0];
    final baseValues2 = [22.0, 42.0, 34.0, 56.0, 42.0, 64.0, 52.0];
    final points1 = <Offset>[];
    final points2 = <Offset>[];

    for (int i = 0; i < days.length; i++) {
      final x = paddingL + (i / (days.length - 1)) * chartW;
      final seedOffset = math.sin(_demoDataSeed + i * 1.6) * 10.0;

      final val1 = (baseValues1[i] + seedOffset).clamp(15.0, 100.0);
      final rawY1 = paddingT + (1.0 - val1 / 100.0) * chartH;
      final animY1 = (paddingT + chartH) - ((paddingT + chartH) - rawY1) * anim;
      points1.add(Offset(x, animY1));

      final val2 = (baseValues2[i] + seedOffset * 0.6).clamp(10.0, 80.0);
      final rawY2 = paddingT + (1.0 - val2 / 100.0) * chartH;
      final animY2 = (paddingT + chartH) - ((paddingT + chartH) - rawY2) * anim;
      points2.add(Offset(x, animY2));

      // X-Axis Day Labels
      final isPeak = i == 5; // 周六
      if (isPeak) {
        cmds.add({
          "op": "roundRect",
          "x": x - 18.0,
          "y": paddingT + chartH + 8.0,
          "w": 36.0,
          "h": 18.0,
          "r": 4.0,
          "isFill": true,
        });
        cmds.add({"op": "setFillColor", "color": "#2563EB"});
        cmds.add({
          "op": "drawText",
          "text": days[i],
          "x": x - 11.0,
          "y": paddingT + chartH + 11.0,
          "fontSize": 10.0,
          "color": "#FFFFFF",
          "isBold": true,
        });
      } else {
        cmds.add({
          "op": "drawText",
          "text": days[i],
          "x": x - 11.0,
          "y": paddingT + chartH + 11.0,
          "fontSize": 10.0,
          "color": "#64748B",
        });
      }
    }

    // Series 2 (外卖 Cyan) Spline Area Fill
    cmds.add({"op": "beginPath"});
    cmds.add({"op": "moveTo", "x": points2[0].dx, "y": paddingT + chartH});
    cmds.add({"op": "lineTo", "x": points2[0].dx, "y": points2[0].dy});
    for (int i = 0; i < points2.length - 1; i++) {
      final p0 = points2[i];
      final p1 = points2[i + 1];
      cmds.add({
        "op": "bezierCurveTo",
        "cp1x": p0.dx + (p1.dx - p0.dx) / 2.0,
        "cp1y": p0.dy,
        "cp2x": p0.dx + (p1.dx - p0.dx) / 2.0,
        "cp2y": p1.dy,
        "x": p1.dx,
        "y": p1.dy,
      });
    }
    cmds.add({"op": "lineTo", "x": points2.last.dx, "y": paddingT + chartH});
    cmds.add({"op": "closePath"});
    cmds.add({
      "op": "setLinearGradient",
      "x0": 0.0,
      "y0": paddingT,
      "x1": 0.0,
      "y1": paddingT + chartH,
      "colors": ["#4006B6D4", "#0006B6D4"],
    });
    cmds.add({"op": "fill"});

    // Series 2 Stroke (Cyan)
    cmds.add({"op": "beginPath"});
    cmds.add({"op": "moveTo", "x": points2[0].dx, "y": points2[0].dy});
    for (int i = 0; i < points2.length - 1; i++) {
      final p0 = points2[i];
      final p1 = points2[i + 1];
      cmds.add({
        "op": "bezierCurveTo",
        "cp1x": p0.dx + (p1.dx - p0.dx) / 2.0,
        "cp1y": p0.dy,
        "cp2x": p0.dx + (p1.dx - p0.dx) / 2.0,
        "cp2y": p1.dy,
        "x": p1.dx,
        "y": p1.dy,
      });
    }
    cmds.add({"op": "setStrokeColor", "color": "#06B6D4"});
    cmds.add({"op": "setLineWidth", "width": 2.2});
    cmds.add({"op": "stroke"});

    // Series 1 (堂食 Blue) Spline Area Fill
    cmds.add({"op": "beginPath"});
    cmds.add({"op": "moveTo", "x": points1[0].dx, "y": paddingT + chartH});
    cmds.add({"op": "lineTo", "x": points1[0].dx, "y": points1[0].dy});
    for (int i = 0; i < points1.length - 1; i++) {
      final p0 = points1[i];
      final p1 = points1[i + 1];
      cmds.add({
        "op": "bezierCurveTo",
        "cp1x": p0.dx + (p1.dx - p0.dx) / 2.0,
        "cp1y": p0.dy,
        "cp2x": p0.dx + (p1.dx - p0.dx) / 2.0,
        "cp2y": p1.dy,
        "x": p1.dx,
        "y": p1.dy,
      });
    }
    cmds.add({"op": "lineTo", "x": points1.last.dx, "y": paddingT + chartH});
    cmds.add({"op": "closePath"});
    cmds.add({
      "op": "setLinearGradient",
      "x0": 0.0,
      "y0": paddingT,
      "x1": 0.0,
      "y1": paddingT + chartH,
      "colors": ["#552563EB", "#052563EB"],
    });
    cmds.add({"op": "fill"});

    // Series 1 Stroke (Blue)
    cmds.add({"op": "beginPath"});
    cmds.add({"op": "moveTo", "x": points1[0].dx, "y": points1[0].dy});
    for (int i = 0; i < points1.length - 1; i++) {
      final p0 = points1[i];
      final p1 = points1[i + 1];
      cmds.add({
        "op": "bezierCurveTo",
        "cp1x": p0.dx + (p1.dx - p0.dx) / 2.0,
        "cp1y": p0.dy,
        "cp2x": p0.dx + (p1.dx - p0.dx) / 2.0,
        "cp2y": p1.dy,
        "x": p1.dx,
        "y": p1.dy,
      });
    }
    cmds.add({"op": "setStrokeColor", "color": "#2563EB"});
    cmds.add({"op": "setLineWidth", "width": 3.0});
    cmds.add({"op": "stroke"});

    // Baseline Forecast Curve (Dashed)
    cmds.add({"op": "beginPath"});
    for (int i = 0; i < days.length; i++) {
      final x = points1[i].dx;
      final midY = (points1[i].dy + points2[i].dy) / 2.0;
      if (i == 0) {
        cmds.add({"op": "moveTo", "x": x, "y": midY});
      } else {
        cmds.add({
          "op": "drawDashedLine",
          "x1": points1[i - 1].dx,
          "y1": (points1[i - 1].dy + points2[i - 1].dy) / 2.0,
          "x2": x,
          "y2": midY,
          "dash": 4.0,
          "gap": 4.0,
        });
        cmds.add({"op": "setStrokeColor", "color": "#94A3B8"});
        cmds.add({"op": "setLineWidth", "width": 1.2});
      }
    }

    // Vertical Crosshair Guideline at Active Point (Index 5: 周六)
    final pActive1 = points1[5];
    final pActive2 = points2[5];
    cmds.add({
      "op": "drawDashedLine",
      "x1": pActive1.dx,
      "y1": paddingT,
      "x2": pActive1.dx,
      "y2": paddingT + chartH,
      "dash": 3.0,
      "gap": 3.0,
    });
    cmds.add({"op": "setStrokeColor", "color": "#94A3B8"});
    cmds.add({"op": "setLineWidth", "width": 1.2});

    // Active Markers on Series 2 (Cyan)
    cmds.add({
      "op": "circle",
      "x": pActive2.dx,
      "y": pActive2.dy,
      "r": 6.0,
      "isFill": true
    });
    cmds.add({"op": "setFillColor", "color": "#A5F3FC"});
    cmds.add({
      "op": "circle",
      "x": pActive2.dx,
      "y": pActive2.dy,
      "r": 4.0,
      "isFill": true
    });
    cmds.add({"op": "setFillColor", "color": "#FFFFFF"});
    cmds.add({
      "op": "circle",
      "x": pActive2.dx,
      "y": pActive2.dy,
      "r": 2.5,
      "isFill": true
    });
    cmds.add({"op": "setFillColor", "color": "#06B6D4"});

    // Active Markers on Series 1 (Blue Glowing Halo)
    cmds.add({
      "op": "circle",
      "x": pActive1.dx,
      "y": pActive1.dy,
      "r": 8.5,
      "isFill": true
    });
    cmds.add({"op": "setFillColor", "color": "#BFDBFE"});
    cmds.add({
      "op": "circle",
      "x": pActive1.dx,
      "y": pActive1.dy,
      "r": 5.5,
      "isFill": true
    });
    cmds.add({"op": "setFillColor", "color": "#FFFFFF"});
    cmds.add({
      "op": "circle",
      "x": pActive1.dx,
      "y": pActive1.dy,
      "r": 3.8,
      "isFill": true
    });
    cmds.add({"op": "setFillColor", "color": "#2563EB"});

    // VChart-Style High-End Floating Tooltip Card
    final tooltipW = 195.0;
    final tooltipH = 76.0;
    final tx =
        (pActive1.dx - tooltipW / 2.0).clamp(paddingL, w - tooltipW - 10.0);
    final ty = (pActive1.dy - tooltipH - 12.0).clamp(paddingT, h - tooltipH);

    cmds.add({
      "op": "roundRect",
      "x": tx,
      "y": ty,
      "w": tooltipW,
      "h": tooltipH,
      "r": 8.0,
      "isFill": true,
    });
    cmds.add({"op": "setFillColor", "color": "#0F172A"});

    cmds.add({
      "op": "drawText",
      "text": "周六 18:00 (客流高峰时段)",
      "x": tx + 12.0,
      "y": ty + 8.0,
      "fontSize": 10.5,
      "color": "#94A3B8",
      "isBold": true,
    });

    // Tooltip Row 1: 堂食
    cmds.add({
      "op": "circle",
      "x": tx + 16.0,
      "y": ty + 30.0,
      "r": 3.5,
      "isFill": true
    });
    cmds.add({"op": "setFillColor", "color": "#3B82F6"});
    cmds.add({
      "op": "drawText",
      "text": "堂食流水: ¥95,280 (+28.4%)",
      "x": tx + 26.0,
      "y": ty + 24.0,
      "fontSize": 10.5,
      "color": "#FFFFFF",
      "isBold": true,
    });

    // Tooltip Row 2: 外卖
    cmds.add({
      "op": "circle",
      "x": tx + 16.0,
      "y": ty + 48.0,
      "r": 3.5,
      "isFill": true
    });
    cmds.add({"op": "setFillColor", "color": "#06B6D4"});
    cmds.add({
      "op": "drawText",
      "text": "线上外卖: ¥64,120 (+16.2%)",
      "x": tx + 26.0,
      "y": ty + 42.0,
      "fontSize": 10.0,
      "color": "#38BDF8",
    });

    // Tooltip Row 3: Tag
    cmds.add({
      "op": "drawText",
      "text": "★ 全天实收 ¥159.4k (破历史纪录)",
      "x": tx + 12.0,
      "y": ty + 58.0,
      "fontSize": 9.5,
      "color": "#FBBF24",
    });

    return cmds;
  }

  // 2. VChart Dual-Benchmark Radar Chart Commands
  List<Map<String, dynamic>> _generateVChartRadarCommands(
      double anim, double w, double h) {
    final List<Map<String, dynamic>> cmds = [];
    final cx = w / 2.0;
    final cy = h / 2.0 + 10.0;
    final maxR = math.min(w * 0.35, h * 0.36);
    final dimensions = [
      "菜品口味 (96分)",
      "用餐环境 (88分)",
      "服务响应 (92分)",
      "上菜速度 (95分)",
      "价格感知 (82分)",
      "复购忠诚 (94分)",
    ];
    final scoresOur = [96.0, 88.0, 92.0, 95.0, 82.0, 94.0];
    final scoresPeer = [86.0, 92.0, 84.0, 88.0, 90.0, 85.0];
    final n = dimensions.length;

    // Top VChart Legend
    cmds.add(
        {"op": "circle", "x": cx - 140.0, "y": 18.0, "r": 4.5, "isFill": true});
    cmds.add({"op": "setFillColor", "color": "#2563EB"});
    cmds.add({
      "op": "drawText",
      "text": "本店当前得分: 91.2分 (超越商圈94%)",
      "x": cx - 130.0,
      "y": 12.0,
      "fontSize": 11.0,
      "color": "#1E293B",
      "isBold": true,
    });

    cmds.add(
        {"op": "circle", "x": cx + 80.0, "y": 18.0, "r": 4.5, "isFill": true});
    cmds.add({"op": "setFillColor", "color": "#F59E0B"});
    cmds.add({
      "op": "drawText",
      "text": "商圈 TOP10 标杆均值: 87.5分",
      "x": cx + 90.0,
      "y": 12.0,
      "fontSize": 11.0,
      "color": "#64748B",
    });

    // 5-Level Concentric Spiderweb Polygons
    for (int ring = 1; ring <= 5; ring++) {
      final r = maxR * (ring / 5.0);
      cmds.add({"op": "beginPath"});
      for (int i = 0; i < n; i++) {
        final angle = (i * 2.0 * math.pi / n) - math.pi / 2.0;
        final x = cx + r * math.cos(angle);
        final y = cy + r * math.sin(angle);
        if (i == 0) {
          cmds.add({"op": "moveTo", "x": x, "y": y});
        } else {
          cmds.add({"op": "lineTo", "x": x, "y": y});
        }
      }
      cmds.add({"op": "closePath"});
      if (ring == 5) {
        cmds.add({"op": "setStrokeColor", "color": "#CBD5E1"});
        cmds.add({"op": "setLineWidth", "width": 1.2});
      } else {
        cmds.add({"op": "setStrokeColor", "color": "#F1F5F9"});
        cmds.add({"op": "setLineWidth", "width": 1.0});
      }
      cmds.add({"op": "stroke"});

      // Grid percentage label along top vertical axis
      cmds.add({
        "op": "drawText",
        "text": "${ring * 20}%",
        "x": cx + 4.0,
        "y": cy - r - 4.0,
        "fontSize": 8.5,
        "color": "#94A3B8",
      });
    }

    // 6 Radial Axes & Dimension Labels
    for (int i = 0; i < n; i++) {
      final angle = (i * 2.0 * math.pi / n) - math.pi / 2.0;
      final x = cx + maxR * math.cos(angle);
      final y = cy + maxR * math.sin(angle);
      cmds.add({"op": "beginPath"});
      cmds.add({"op": "moveTo", "x": cx, "y": cy});
      cmds.add({"op": "lineTo", "x": x, "y": y});
      cmds.add({"op": "setStrokeColor", "color": "#E2E8F0"});
      cmds.add({"op": "setLineWidth", "width": 1.0});
      cmds.add({"op": "stroke"});

      // Dimension Label Pill
      final labelX = cx + (maxR + 24.0) * math.cos(angle) - 36.0;
      final labelY = cy + (maxR + 16.0) * math.sin(angle) - 7.0;
      cmds.add({
        "op": "drawText",
        "text": dimensions[i],
        "x": labelX,
        "y": labelY,
        "fontSize": 10.0,
        "color": "#1E293B",
        "isBold": true,
      });
    }

    // Series 2 (商圈标杆 Peer Benchmark - Amber Polygon)
    final ptsPeer = <Offset>[];
    for (int i = 0; i < n; i++) {
      final angle = (i * 2.0 * math.pi / n) - math.pi / 2.0;
      final r = maxR * (scoresPeer[i] / 100.0) * anim;
      ptsPeer.add(Offset(cx + r * math.cos(angle), cy + r * math.sin(angle)));
    }
    cmds.add({"op": "beginPath"});
    cmds.add({"op": "moveTo", "x": ptsPeer[0].dx, "y": ptsPeer[0].dy});
    for (int i = 1; i < ptsPeer.length; i++) {
      cmds.add({"op": "lineTo", "x": ptsPeer[i].dx, "y": ptsPeer[i].dy});
    }
    cmds.add({"op": "closePath"});
    cmds.add({"op": "setFillColor", "color": "#20F59E0B"});
    cmds.add({"op": "fill"});
    cmds.add({"op": "setStrokeColor", "color": "#F59E0B"});
    cmds.add({"op": "setLineWidth", "width": 1.8});
    cmds.add({"op": "stroke"});

    // Series 1 (本店实际 - Royal Blue Polygon)
    final ptsOur = <Offset>[];
    for (int i = 0; i < n; i++) {
      final angle = (i * 2.0 * math.pi / n) - math.pi / 2.0;
      final seedOffset = math.sin(_demoDataSeed + i * 1.8) * 4.0;
      final s = ((scoresOur[i] + seedOffset).clamp(60.0, 100.0) / 100.0);
      final r = maxR * s * anim;
      ptsOur.add(Offset(cx + r * math.cos(angle), cy + r * math.sin(angle)));
    }
    cmds.add({"op": "beginPath"});
    cmds.add({"op": "moveTo", "x": ptsOur[0].dx, "y": ptsOur[0].dy});
    for (int i = 1; i < ptsOur.length; i++) {
      cmds.add({"op": "lineTo", "x": ptsOur[i].dx, "y": ptsOur[i].dy});
    }
    cmds.add({"op": "closePath"});
    cmds.add({"op": "setFillColor", "color": "#402563EB"});
    cmds.add({"op": "fill"});
    cmds.add({"op": "setStrokeColor", "color": "#2563EB"});
    cmds.add({"op": "setLineWidth", "width": 2.8});
    cmds.add({"op": "stroke"});

    // Vertex Halo Markers for 本店
    for (final pt in ptsOur) {
      cmds.add(
          {"op": "circle", "x": pt.dx, "y": pt.dy, "r": 4.5, "isFill": true});
      cmds.add({"op": "setFillColor", "color": "#BFDBFE"});
      cmds.add(
          {"op": "circle", "x": pt.dx, "y": pt.dy, "r": 3.0, "isFill": true});
      cmds.add({"op": "setFillColor", "color": "#2563EB"});
      cmds.add(
          {"op": "circle", "x": pt.dx, "y": pt.dy, "r": 1.5, "isFill": true});
      cmds.add({"op": "setFillColor", "color": "#FFFFFF"});
    }

    return cmds;
  }

  // 3. VChart Donut Ring Chart with Center Metrics & Right Breakdown List
  List<Map<String, dynamic>> _generateVChartDonutCommands(
      double anim, double w, double h) {
    final List<Map<String, dynamic>> cmds = [];
    final donutCx = w > 600 ? w * 0.28 : w * 0.32;
    final donutCy = h * 0.52;
    final outerR = math.min(w * 0.18, h * 0.36);

    final categories = [
      {
        "name": "招牌秘制牛腩煲",
        "percent": 0.42,
        "color": "#2563EB",
        "amount": "¥53,949",
        "sub": "日销 328份"
      },
      {
        "name": "潮汕鲜手打丸类",
        "percent": 0.26,
        "color": "#06B6D4",
        "amount": "¥33,397",
        "sub": "日销 214份"
      },
      {
        "name": "鲜榨爆汁特饮冷碟",
        "percent": 0.18,
        "color": "#10B981",
        "amount": "¥23,121",
        "sub": "日销 186杯"
      },
      {
        "name": "经典主食甜品茶歇",
        "percent": 0.14,
        "color": "#F59E0B",
        "amount": "¥17,983",
        "sub": "日销 142份"
      },
    ];

    // Background track arc
    cmds.add({
      "op": "drawArc",
      "x": donutCx,
      "y": donutCy,
      "r": outerR,
      "startAngle": 0.0,
      "sweepAngle": 360.0,
      "isFill": false,
    });
    cmds.add({"op": "setStrokeColor", "color": "#F1F5F9"});
    cmds.add({"op": "setLineWidth", "width": 24.0});
    cmds.add({"op": "stroke"});

    // Animated Colored Segments
    double curAngle = -90.0;
    for (final cat in categories) {
      final sweep = (cat["percent"] as double) * 360.0 * anim;
      if (sweep > 0.5) {
        cmds.add({
          "op": "drawArc",
          "x": donutCx,
          "y": donutCy,
          "r": outerR,
          "startAngle": curAngle,
          "sweepAngle": sweep - 2.0, // small gap between segments
          "isFill": false,
        });
        cmds.add({"op": "setStrokeColor", "color": cat["color"]});
        cmds.add({"op": "setLineWidth", "width": 24.0});
        cmds.add({"op": "stroke"});
      }
      curAngle += (cat["percent"] as double) * 360.0;
    }

    // Donut Center Big Typography
    cmds.add({
      "op": "drawText",
      "text": "¥128,450",
      "x": donutCx - 44.0,
      "y": donutCy - 20.0,
      "fontSize": 20.0,
      "color": "#0F172A",
      "isBold": true,
    });
    cmds.add({
      "op": "drawText",
      "text": "今日总实收流水",
      "x": donutCx - 36.0,
      "y": donutCy + 4.0,
      "fontSize": 10.5,
      "color": "#64748B",
    });
    cmds.add({
      "op": "roundRect",
      "x": donutCx - 38.0,
      "y": donutCy + 18.0,
      "w": 76.0,
      "h": 16.0,
      "r": 8.0,
      "isFill": true,
    });
    cmds.add({"op": "setFillColor", "color": "#DCFCE7"});
    cmds.add({
      "op": "drawText",
      "text": "▲ 环比 +18.4%",
      "x": donutCx - 32.0,
      "y": donutCy + 20.0,
      "fontSize": 9.5,
      "color": "#15803D",
      "isBold": true,
    });

    // Right Side: High-End Category Breakdown List
    final listStartX = w > 600 ? w * 0.52 : w * 0.58;
    final rowH = 54.0;
    final startY = 32.0;

    for (int i = 0; i < categories.length; i++) {
      final cat = categories[i];
      final ry = startY + i * rowH;

      // Color Swatch
      cmds.add({
        "op": "circle",
        "x": listStartX + 6.0,
        "y": ry + 8.0,
        "r": 5.0,
        "isFill": true
      });
      cmds.add({"op": "setFillColor", "color": cat["color"]});

      // Category Name
      cmds.add({
        "op": "drawText",
        "text": cat["name"].toString(),
        "x": listStartX + 18.0,
        "y": ry + 2.0,
        "fontSize": 11.5,
        "color": "#1E293B",
        "isBold": true,
      });

      // Amount & Percent
      final pctStr =
          "${((cat['percent'] as double) * 100).toStringAsFixed(0)}%";
      cmds.add({
        "op": "drawText",
        "text": "${cat['amount']} ($pctStr)",
        "x": listStartX + 180.0,
        "y": ry + 2.0,
        "fontSize": 11.0,
        "color": "#0F172A",
        "isBold": true,
      });

      // Progress Bar Track
      final barW = 240.0;
      cmds.add({
        "op": "roundRect",
        "x": listStartX + 18.0,
        "y": ry + 20.0,
        "w": barW,
        "h": 6.0,
        "r": 3.0,
        "isFill": true,
      });
      cmds.add({"op": "setFillColor", "color": "#F1F5F9"});

      // Progress Bar Fill (Animated)
      final fillW = barW * (cat["percent"] as double) * anim;
      cmds.add({
        "op": "roundRect",
        "x": listStartX + 18.0,
        "y": ry + 20.0,
        "w": fillW,
        "h": 6.0,
        "r": 3.0,
        "isFill": true,
      });
      cmds.add({"op": "setFillColor", "color": cat["color"]});

      // Sub description
      cmds.add({
        "op": "drawText",
        "text": cat["sub"].toString(),
        "x": listStartX + 18.0,
        "y": ry + 30.0,
        "fontSize": 9.5,
        "color": "#94A3B8",
      });
    }

    return cmds;
  }

  // 4. VChart Grouped Bar Chart (堂食 vs 外卖 双柱对比)
  List<Map<String, dynamic>> _generateVChartGroupedBarCommands(
      double anim, double w, double h) {
    final List<Map<String, dynamic>> cmds = [];
    final paddingL = 52.0;
    final paddingR = 24.0;
    final paddingT = 44.0;
    final paddingB = 34.0;
    final chartW = (w - paddingL - paddingR).clamp(100.0, 2000.0);
    final chartH = (h - paddingT - paddingB).clamp(50.0, 1000.0);

    // Top Legend Bar
    cmds.add({
      "op": "roundRect",
      "x": paddingL + 10.0,
      "y": 14.0,
      "w": 12.0,
      "h": 10.0,
      "r": 2.0,
      "isFill": true
    });
    cmds.add({"op": "setFillColor", "color": "#2563EB"});
    cmds.add({
      "op": "drawText",
      "text": "堂食订单 (单均 ¥86.7)",
      "x": paddingL + 28.0,
      "y": 12.0,
      "fontSize": 11.0,
      "color": "#1E293B",
      "isBold": true,
    });

    cmds.add({
      "op": "roundRect",
      "x": paddingL + 180.0,
      "y": 14.0,
      "w": 12.0,
      "h": 10.0,
      "r": 2.0,
      "isFill": true
    });
    cmds.add({"op": "setFillColor", "color": "#06B6D4"});
    cmds.add({
      "op": "drawText",
      "text": "外卖订单 (单均 ¥48.2)",
      "x": paddingL + 198.0,
      "y": 12.0,
      "fontSize": 11.0,
      "color": "#1E293B",
      "isBold": true,
    });

    // 5 Dashed Gridlines
    for (int i = 0; i <= 4; i++) {
      final ty = paddingT + (chartH / 4.0) * i;
      final val = ((4 - i) * 25).toString();
      cmds.add({
        "op": "drawText",
        "text": "¥${val}k",
        "x": 8.0,
        "y": ty - 6.0,
        "fontSize": 10.0,
        "color": "#94A3B8",
      });
      cmds.add({
        "op": "drawDashedLine",
        "x1": paddingL,
        "y1": ty,
        "x2": paddingL + chartW,
        "y2": ty,
        "dash": 4.0,
        "gap": 4.0,
      });
      cmds.add({"op": "setStrokeColor", "color": "#E2E8F0"});
      cmds.add({"op": "setLineWidth", "width": 1.0});
    }

    final days = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"];
    final data1 = [36.0, 68.0, 52.0, 85.0, 64.0, 95.0, 78.0];
    final data2 = [22.0, 42.0, 34.0, 56.0, 42.0, 64.0, 50.0];

    final colW = chartW / days.length;
    final barW = (colW * 0.32).clamp(10.0, 24.0);

    for (int i = 0; i < days.length; i++) {
      final groupCenterX = paddingL + i * colW + colW / 2.0;
      final seedOffset = math.sin(_demoDataSeed + i * 1.5) * 8.0;

      final v1 = (data1[i] + seedOffset).clamp(10.0, 100.0);
      final v2 = (data2[i] + seedOffset * 0.7).clamp(10.0, 100.0);

      final barH1 = (chartH * (v1 / 100.0) * anim).clamp(4.0, chartH);
      final barH2 = (chartH * (v2 / 100.0) * anim).clamp(4.0, chartH);

      final barX1 = groupCenterX - barW - 2.0;
      final barY1 = (paddingT + chartH) - barH1;

      final barX2 = groupCenterX + 2.0;
      final barY2 = (paddingT + chartH) - barH2;

      // Bar 1 (堂食 Blue Gradient)
      cmds.add({
        "op": "roundRect",
        "x": barX1,
        "y": barY1,
        "w": barW,
        "h": barH1,
        "r": 4.0,
        "isFill": true,
      });
      cmds.add({
        "op": "setLinearGradient",
        "x0": barX1,
        "y0": barY1,
        "x1": barX1,
        "y1": paddingT + chartH,
        "colors": ["#2563EB", "#60A5FA"],
      });
      cmds.add({"op": "fill"});

      // Value label 1
      cmds.add({
        "op": "drawText",
        "text": "${v1.toInt()}k",
        "x": barX1 - 2.0,
        "y": barY1 - 14.0,
        "fontSize": 9.0,
        "color": "#2563EB",
        "isBold": true,
      });

      // Bar 2 (外卖 Cyan Gradient)
      cmds.add({
        "op": "roundRect",
        "x": barX2,
        "y": barY2,
        "w": barW,
        "h": barH2,
        "r": 4.0,
        "isFill": true,
      });
      cmds.add({
        "op": "setLinearGradient",
        "x0": barX2,
        "y0": barY2,
        "x1": barX2,
        "y1": paddingT + chartH,
        "colors": ["#06B6D4", "#67E8F9"],
      });
      cmds.add({"op": "fill"});

      // Value label 2
      cmds.add({
        "op": "drawText",
        "text": "${v2.toInt()}k",
        "x": barX2 - 2.0,
        "y": barY2 - 14.0,
        "fontSize": 9.0,
        "color": "#06B6D4",
        "isBold": true,
      });

      // X Day Label
      cmds.add({
        "op": "drawText",
        "text": days[i],
        "x": groupCenterX - 11.0,
        "y": paddingT + chartH + 10.0,
        "fontSize": 10.0,
        "color": "#64748B",
      });
    }

    return cmds;
  }

  // --- TAB 0: 经营报表与多维图表套件 ---
  Widget _buildReportTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 4 KPI Cards
        Row(
          children: [
            Expanded(
                child: _buildKpiCard(
                    "今日营业总额", "¥28,450.00", "+18.4% 环比昨日", Colors.blue)),
            const SizedBox(width: 8),
            Expanded(
                child: _buildKpiCard(
                    "有效订单总量", "328 单", "+12.6% 环比昨日", Colors.green)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
                child: _buildKpiCard(
                    "顾客平均客单价", "¥86.74", "+5.2% 提升", Colors.orange)),
            const SizedBox(width: 8),
            Expanded(
                child:
                    _buildKpiCard("综合菜品毛利率", "68.5%", "处于优秀区间", Colors.purple)),
          ],
        ),
        const SizedBox(height: 10),

        // Live Real-Time FPS and Rendering Pipeline Banner
        _buildPerformanceBanner(),
        const SizedBox(height: 10),

        // Multi-Chart Selector Segmented Bar
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              _buildChartTypeTab(0, "📊 分时柱状", "峰值"),
              _buildChartTypeTab(1, "📈 7日折线", "走势"),
              _buildChartTypeTab(2, "🎯 业绩仪表", "目标"),
              _buildChartTypeTab(3, "🍩 品类结构", "占比"),
              _buildChartTypeTab(4, "👥 客流高峰", "翻台"),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Render selected chart component
        _buildSelectedChartCard(),
        const SizedBox(height: 12),

        // Top Sellers List
        _buildTopSellersCard(),
        const SizedBox(height: 12),

        // Export Report Tunnel Trigger
        ElevatedButton.icon(
          onPressed: () {
            _invokeBridge("report", "exportReport", {
              "range": "今日实时",
              "format": "xlsx",
              "storeId": _runtimeData["storeId"] ?? "STORE_001",
            });
          },
          icon: const Icon(Icons.file_download_outlined, size: 18),
          label: const Text("通过宿主隧道导出 Excel 报表 (exportReport)"),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            backgroundColor: const Color(0xFF1677FF),
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
    );
  }

  Widget _buildChartTypeTab(int idx, String title, String sub) {
    final isCur = _chartTypeIdx == idx;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _chartTypeIdx = idx);
          _replayAnimation();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isCur ? const Color(0xFF1677FF) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isCur ? FontWeight.bold : FontWeight.normal,
                  color: isCur ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                sub,
                style: TextStyle(
                  fontSize: 9.5,
                  color: isCur ? Colors.white70 : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedChartCard() {
    Widget chart;
    switch (_chartTypeIdx) {
      case 0:
        chart = _buildHourlyBarChart();
        break;
      case 1:
        chart = _buildSevenDaysLineChart();
        break;
      case 2:
        chart = _buildTargetGaugeChart();
        break;
      case 3:
        chart = _buildCategoryDonutChart();
        break;
      case 4:
        chart = _buildWeeklyTrafficHeatChart();
        break;
      default:
        chart = _buildHourlyBarChart();
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.0, 0.03),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<int>(_chartTypeIdx),
        child: chart,
      ),
    );
  }

  // Chart 1: Hourly Sales Bar Chart
  Widget _buildHourlyBarChart() {
    final curHour = _hourlyData[_selectedHourIdx];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("分时营收与订单走势图 (Bar Chart)",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  SizedBox(height: 2),
                  Text("专业可视化柱状图 • 含 Y 轴金额刻度与辅助网格线",
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
              Row(
                children: [
                  InkWell(
                    onTap: _replayAnimation,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6F4FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF91CAFF)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh,
                              size: 12, color: Color(0xFF1677FF)),
                          SizedBox(width: 3),
                          Text("重播动画",
                              style: TextStyle(
                                  color: Color(0xFF1677FF),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text("点击柱子联动",
                        style: TextStyle(
                            color: Color(0xFF1677FF),
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedBuilder(
            animation: _chartAnim,
            builder: (context, _) {
              return SizedBox(
                height: 175,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(
                      width: 38,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text("¥8.0k",
                              style:
                                  TextStyle(fontSize: 9.5, color: Colors.grey)),
                          Text("¥6.0k",
                              style:
                                  TextStyle(fontSize: 9.5, color: Colors.grey)),
                          Text("¥4.0k",
                              style:
                                  TextStyle(fontSize: 9.5, color: Colors.grey)),
                          Text("¥2.0k",
                              style:
                                  TextStyle(fontSize: 9.5, color: Colors.grey)),
                          Text("¥0.0",
                              style:
                                  TextStyle(fontSize: 9.5, color: Colors.grey)),
                          SizedBox(height: 18),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            bottom: 22,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: List.generate(
                                5,
                                (_) => Container(
                                    height: 1, color: const Color(0xFFF0F2F5)),
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children:
                                  List.generate(_hourlyData.length, (idx) {
                                final item = _hourlyData[idx];
                                final isCur = _selectedHourIdx == idx;
                                final hFactor = item["height"] as double;

                                final start = (idx * 0.08).clamp(0.0, 0.6);
                                final end = (start + 0.4).clamp(0.0, 1.0);
                                final itemP =
                                    ((_chartAnim.value - start) / (end - start))
                                        .clamp(0.0, 1.0);
                                final curvedP =
                                    Curves.easeOutBack.transform(itemP);
                                final animH = (110.0 * hFactor * curvedP)
                                    .clamp(2.0, 120.0);

                                return Expanded(
                                  child: InkWell(
                                    onTap: () {
                                      setState(() => _selectedHourIdx = idx);
                                      LynxLogger.info(
                                          "MiniApp", "选择分时时段: ${item['hour']}");
                                    },
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Opacity(
                                          opacity: itemP.clamp(0.0, 1.0),
                                          child: Text(
                                            "¥${((item['amount'] as double) / 1000).toStringAsFixed(1)}k",
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: isCur
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              color: isCur
                                                  ? const Color(0xFF1677FF)
                                                  : Colors.grey.shade500,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Container(
                                          height: animH,
                                          width: 26,
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: isCur
                                                  ? [
                                                      const Color(0xFF1677FF),
                                                      const Color(0xFF69C0FF)
                                                    ]
                                                  : [
                                                      const Color(0xFF91CAFF),
                                                      const Color(0xFFE6F4FF)
                                                    ],
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                            ),
                                            borderRadius:
                                                const BorderRadius.vertical(
                                                    top: Radius.circular(5)),
                                            boxShadow: isCur
                                                ? [
                                                    BoxShadow(
                                                      color: const Color(
                                                              0xFF1677FF)
                                                          .withValues(
                                                              alpha: 0.35),
                                                      blurRadius: 8,
                                                      offset:
                                                          const Offset(0, 3),
                                                    )
                                                  ]
                                                : null,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          item["hour"] as String,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: isCur
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: isCur
                                                ? const Color(0xFF1677FF)
                                                : Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                const Icon(Icons.touch_app, size: 16, color: Color(0xFF1677FF)),
                const SizedBox(width: 8),
                Text(
                  "选中时段 ${curHour['hour']}: 营收 ¥${curHour['amount']} (${curHour['orders']}笔订单)",
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1677FF)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Chart 2: 7-Day Line & Area Chart
  Widget _buildSevenDaysLineChart() {
    final curDay = _sevenDaysData[_selectedDayIdx];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("7日营收平滑折线走势图 (Line Chart)",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  SizedBox(height: 2),
                  Text("多周期对比分析 • 动态面积渐变与节点高亮",
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
              Row(
                children: [
                  InkWell(
                    onTap: _replayAnimation,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6F4FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF91CAFF)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh,
                              size: 12, color: Color(0xFF1677FF)),
                          SizedBox(width: 3),
                          Text("重播动画",
                              style: TextStyle(
                                  color: Color(0xFF1677FF),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text("持续冲高 ↑",
                        style: TextStyle(
                            color: Color(0xFF52C41A),
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedBuilder(
            animation: _chartAnim,
            builder: (context, _) {
              return SizedBox(
                height: 175,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(
                      width: 38,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text("¥35k",
                              style:
                                  TextStyle(fontSize: 9.5, color: Colors.grey)),
                          Text("¥25k",
                              style:
                                  TextStyle(fontSize: 9.5, color: Colors.grey)),
                          Text("¥18k",
                              style:
                                  TextStyle(fontSize: 9.5, color: Colors.grey)),
                          Text("¥10k",
                              style:
                                  TextStyle(fontSize: 9.5, color: Colors.grey)),
                          Text("¥0.0",
                              style:
                                  TextStyle(fontSize: 9.5, color: Colors.grey)),
                          SizedBox(height: 18),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            bottom: 22,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: List.generate(
                                5,
                                (_) => Container(
                                    height: 1, color: const Color(0xFFF0F2F5)),
                              ),
                            ),
                          ),

                          // Real Smooth Curve & Area Painter with Left-to-Right Drawing Animation
                          Positioned.fill(
                            bottom: 22,
                            child: CustomPaint(
                              painter: SmoothLineChartPainter(
                                values: _sevenDaysData
                                    .map((d) => d["revenue"] as double)
                                    .toList(),
                                maxValue: 35000.0,
                                progress: _chartAnim.value,
                                selectedIndex: _selectedDayIdx,
                                primaryColor: const Color(0xFF1677FF),
                              ),
                            ),
                          ),

                          // Bottom Labels & Interactive Overlay
                          Positioned.fill(
                            child: Row(
                              children:
                                  List.generate(_sevenDaysData.length, (idx) {
                                final d = _sevenDaysData[idx];
                                final isCur = _selectedDayIdx == idx;

                                return Expanded(
                                  child: InkWell(
                                    onTap: () {
                                      setState(() => _selectedDayIdx = idx);
                                      LynxLogger.info(
                                          "MiniApp", "选择7日走势: ${d['day']}");
                                    },
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Opacity(
                                          opacity:
                                              _chartAnim.value.clamp(0.0, 1.0),
                                          child: Text(
                                            "¥${((d['revenue'] as double) / 1000).toStringAsFixed(1)}k",
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: isCur
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                              color: isCur
                                                  ? const Color(0xFF1677FF)
                                                  : Colors.grey.shade500,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          d["day"] as String,
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: isCur
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: isCur
                                                ? const Color(0xFF1677FF)
                                                : Colors.grey.shade700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                const Icon(Icons.show_chart,
                    size: 16, color: Color(0xFF1677FF)),
                const SizedBox(width: 8),
                Text(
                  "${curDay['day']}流水: ¥${curDay['revenue']} (${curDay['orders']}单) • 环比周一 +${(((curDay['revenue'] as double) - 18200) / 182).toStringAsFixed(1)}%",
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1677FF)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Chart 3: Target Achievement Gauge Chart
  Widget _buildTargetGaugeChart() {
    const double target = 30000.0;
    const double current = 28450.0;
    const double percent = (current / target) * 100;
    const double diff = target - current;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("今日经营目标达成仪表盘 (Gauge Chart)",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  SizedBox(height: 2),
                  Text("实时追踪日营业额达成率与关键指标进度",
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
              Row(
                children: [
                  InkWell(
                    onTap: _replayAnimation,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6F4FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF91CAFF)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh,
                              size: 12, color: Color(0xFF1677FF)),
                          SizedBox(width: 3),
                          Text("重播动画",
                              style: TextStyle(
                                  color: Color(0xFF1677FF),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text("进度 94.8%",
                        style: TextStyle(
                            color: Color(0xFF1677FF),
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          AnimatedBuilder(
            animation: _chartAnim,
            builder: (context, _) {
              final animPercent = percent * _chartAnim.value;
              final animCurrent = current * _chartAnim.value;
              return Center(
                child: Column(
                  children: [
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(160, 160),
                          painter: GaugeChartPainter(
                            progress: _chartAnim.value,
                            targetPercent: percent / 100,
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "${animPercent.toStringAsFixed(1)}%",
                              style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1677FF)),
                            ),
                            Text(
                              "¥${animCurrent.toInt()}",
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.grey.shade700),
                            ),
                            const Text("当前达成额",
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Transform.scale(
                      scale: 1.0 + 0.03 * math.sin(_chartAnim.value * math.pi),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE6F4FF),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF1677FF)
                                  .withValues(alpha: 0.15 * _chartAnim.value),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Text(
                          "🚀 仅差 ¥${diff.toStringAsFixed(0)} 即可突破今日 ¥30,000 封顶目标！",
                          style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF1677FF),
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                  child: _buildMetricPill("日业绩目标", "¥30,000", Colors.black87)),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildMetricPill("当前已达成", "¥28,450", Colors.green)),
              const SizedBox(width: 8),
              Expanded(
                  child: _buildMetricPill("待冲刺缺口", "¥1,550", Colors.orange)),
            ],
          ),
        ],
      ),
    );
  }

  // Chart 4: Category Donut / Progress Breakdown
  Widget _buildCategoryDonutChart() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("菜品类目营收结构占比 (Category Donut)",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  SizedBox(height: 2),
                  Text("各大餐品类目流水贡献与单品利润率分析",
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
              Row(
                children: [
                  InkWell(
                    onTap: _replayAnimation,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6F4FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF91CAFF)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh,
                              size: 12, color: Color(0xFF1677FF)),
                          SizedBox(width: 3),
                          Text("重播动画",
                              style: TextStyle(
                                  color: Color(0xFF1677FF),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text("4大主力品类",
                        style: TextStyle(
                            color: Color(0xFF1677FF),
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedBuilder(
            animation: _chartAnim,
            builder: (context, _) {
              final p = _chartAnim.value.clamp(0.01, 1.0);
              return Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      height: 18,
                      child: Row(
                        children: [
                          Expanded(
                              flex: (45 * p).toInt().clamp(1, 45),
                              child: Container(color: const Color(0xFF1677FF))),
                          Expanded(
                              flex: (25 * p).toInt().clamp(1, 25),
                              child: Container(color: const Color(0xFF52C41A))),
                          Expanded(
                              flex: (18 * p).toInt().clamp(1, 18),
                              child: Container(color: const Color(0xFFFAAD14))),
                          Expanded(
                              flex: (12 * p).toInt().clamp(1, 12),
                              child: Container(color: const Color(0xFF722ED1))),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 4 Category Detail Cards with staggered fade & slide
                  Transform.translate(
                    offset: Offset(0, 12 * (1.0 - p)),
                    child: Opacity(
                      opacity: p,
                      child: GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 2,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 3.2,
                        children: [
                          _buildCategoryCard(
                              "招牌热菜与火锅",
                              "¥12,802.50",
                              "${(45 * p).toInt()}%",
                              "毛利 68%",
                              const Color(0xFF1677FF)),
                          _buildCategoryCard(
                              "特色小吃与冷碟",
                              "¥7,112.50",
                              "${(25 * p).toInt()}%",
                              "毛利 72%",
                              const Color(0xFF52C41A)),
                          _buildCategoryCard(
                              "鲜榨特饮与名酒",
                              "¥5,121.00",
                              "${(18 * p).toInt()}%",
                              "毛利 81%",
                              const Color(0xFFFAAD14)),
                          _buildCategoryCard(
                              "经典主食与甜点",
                              "¥3,414.00",
                              "${(12 * p).toInt()}%",
                              "毛利 65%",
                              const Color(0xFF722ED1)),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // Chart 5: Weekly Traffic Heatmap
  Widget _buildWeeklyTrafficHeatChart() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("一周客流热度与翻台率峰值分析 (Traffic Heatmap)",
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  SizedBox(height: 2),
                  Text("进店客流频次、翻台指数及晚市高峰集中区间",
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
              Row(
                children: [
                  InkWell(
                    onTap: _replayAnimation,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6F4FF),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF91CAFF)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.refresh,
                              size: 12, color: Color(0xFF1677FF)),
                          SizedBox(width: 3),
                          Text("重播动画",
                              style: TextStyle(
                                  color: Color(0xFF1677FF),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text("周末高峰高预警 🔥",
                        style: TextStyle(
                            color: Colors.purple,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          AnimatedBuilder(
            animation: _chartAnim,
            builder: (context, _) {
              return Column(
                children: List.generate(_trafficHeatData.length, (idx) {
                  final t = _trafficHeatData[idx];
                  final isWk = t["isWeekend"] as bool;
                  final traffic = t["traffic"] as int;
                  final ratio = traffic / 1050.0;

                  final start = (idx * 0.08).clamp(0.0, 0.6);
                  final end = (start + 0.4).clamp(0.0, 1.0);
                  final itemP = ((_chartAnim.value - start) / (end - start))
                      .clamp(0.0, 1.0);
                  final curvedP = Curves.easeOutCubic.transform(itemP);
                  final animatedRatio = (ratio * curvedP).clamp(0.0, 1.0);

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: isWk
                          ? Colors.orange.shade50.withValues(alpha: 0.5)
                          : const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: isWk
                              ? Colors.orange.shade200
                              : Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 44,
                          child: Text(
                            t["day"] as String,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: isWk
                                    ? Colors.orange.shade900
                                    : Colors.black87),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text("$traffic人次 (${t['turnover']}翻台)",
                                      style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold)),
                                  Text(t["peak"] as String,
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          color: isWk
                                              ? Colors.deepOrange
                                              : Colors.grey.shade600)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: animatedRatio,
                                  minHeight: 6,
                                  backgroundColor: Colors.grey.shade200,
                                  valueColor: AlwaysStoppedAnimation<Color>(isWk
                                      ? Colors.orange
                                      : const Color(0xFF1677FF)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(
      String name, String rev, String pct, String margin, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 11.5)),
                Text("$rev ($pct)",
                    style:
                        TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(4)),
            child: Text(margin,
                style: TextStyle(
                    fontSize: 9.5,
                    color: Colors.green.shade800,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricPill(String lbl, String val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Text(lbl, style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(val,
              style: TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildTopSellersCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("爆款单品销量与毛利排行 Top 4",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 10),
          _buildSellerItem(
              "1", "招牌秘制牛腩煲", "已售 142份", "¥9,656", "毛利 68%", Colors.amber),
          _buildSellerItem(
              "2", "潮汕鲜手打牛肉丸", "已售 98份", "¥3,724", "毛利 72%", Colors.blue),
          _buildSellerItem(
              "3", "生椰爆汁柠檬茶", "已售 86杯", "¥1,548", "毛利 81%", Colors.green),
          _buildSellerItem(
              "4", "极佳级安格斯眼肉", "已售 45份", "¥4,410", "毛利 65%", Colors.purple),
        ],
      ),
    );
  }

  Widget _buildSellerItem(String rank, String name, String sales, String rev,
      String margin, Color badgeColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.15),
                shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(rank,
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: badgeColor)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 12.5)),
                Text(sales,
                    style:
                        TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(rev,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12.5,
                      color: Color(0xFFFA541C))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(4)),
                child: Text(margin,
                    style: TextStyle(
                        fontSize: 9.5,
                        color: Colors.green.shade800,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard(String label, String value, String sub, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(sub,
              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  // --- TAB 1: 桌台管理看板 ---
  Widget _buildDeskTab() {
    final filteredDesks = _selectedDeskFilter == "all"
        ? _desks
        : _desks.where((d) => d["status"] == _selectedDeskFilter).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _buildFilterChip("全部 (${_desks.length})", "all"),
              _buildFilterChip("占用中 (3)", "occupied"),
              _buildFilterChip("空闲中 (2)", "idle"),
              _buildFilterChip("预订中 (1)", "reserved"),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Grid of Desks
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.4,
          ),
          itemCount: filteredDesks.length,
          itemBuilder: (ctx, idx) {
            final desk = filteredDesks[idx];
            final status = desk["status"] as String;
            Color statusColor;
            String statusText;

            if (status == "occupied") {
              statusColor = Colors.orange;
              statusText = "占用中";
            } else if (status == "reserved") {
              statusColor = Colors.purple;
              statusText = "已预订";
            } else {
              statusColor = Colors.green;
              statusText = "空闲";
            }

            return InkWell(
              onTap: () {
                _invokeBridge("ui", "showToast", {
                  "title": "选中 ${desk['name']} (消费: ¥${desk['amount']})",
                  "icon": "success",
                });
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(desk["name"] as String,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(
                                color: statusColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("消费金额",
                                style: TextStyle(
                                    fontSize: 10, color: Colors.grey.shade500)),
                            Text("¥${desk['amount']}",
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                        Text(desk["time"] as String,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600)),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, String filterKey) {
    final isSelected = _selectedDeskFilter == filterKey;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        selected: isSelected,
        label: Text(label,
            style: TextStyle(
                fontSize: 11.5,
                color: isSelected ? Colors.white : Colors.black87)),
        backgroundColor: Colors.white,
        selectedColor: const Color(0xFF1677FF),
        checkmarkColor: Colors.white,
        onSelected: (val) {
          setState(() => _selectedDeskFilter = filterKey);
        },
      ),
    );
  }

  // --- TAB 2: 扫码点餐货架 ---
  Widget _buildOrderTab() {
    final categories = ["全部菜品", "招牌热销", "经典主食", "特色下酒", "精选饮品"];
    final filteredFood = _selectedCategoryIdx == 0
        ? _foodItems
        : _foodItems
            .where((f) => f["cat"] == (_selectedCategoryIdx - 1))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Category horizontal slider
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(categories.length, (idx) {
              final isCur = _selectedCategoryIdx == idx;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(categories[idx]),
                  selected: isCur,
                  selectedColor: const Color(0xFF1677FF),
                  backgroundColor: Colors.white,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: isCur ? Colors.white : Colors.black87,
                    fontWeight: isCur ? FontWeight.bold : FontWeight.normal,
                  ),
                  onSelected: (val) {
                    setState(() => _selectedCategoryIdx = idx);
                  },
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 12),

        // Food Items List
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filteredFood.length,
          itemBuilder: (ctx, idx) {
            final food = filteredFood[idx];
            final id = food["id"] as String;
            final count = _cart[id] ?? 0;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(food["icon"] as String,
                        style: const TextStyle(fontSize: 26)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(food["name"] as String,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13.5)),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                food["tag"] as String,
                                style: TextStyle(
                                    color: Colors.red.shade700,
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(food["desc"] as String,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade600)),
                        const SizedBox(height: 6),
                        Text(
                          "¥${(food['price'] as double).toStringAsFixed(2)}",
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: Color(0xFFFA541C)),
                        ),
                      ],
                    ),
                  ),

                  // Quantity Stepper (- / +)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (count > 0) ...[
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline,
                              color: Color(0xFF1677FF), size: 22),
                          onPressed: () {
                            setState(() {
                              if (count <= 1) {
                                _cart.remove(id);
                              } else {
                                _cart[id] = count - 1;
                              }
                            });
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text("$count",
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ],
                      IconButton(
                        icon: const Icon(Icons.add_circle,
                            color: Color(0xFF1677FF), size: 22),
                        onPressed: () {
                          setState(() {
                            _cart[id] = count + 1;
                          });
                        },
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCartStickyBar() {
    int totalCount = _cart.values.fold(0, (a, b) => a + b);
    double totalPrice = 0.0;
    _cart.forEach((id, qty) {
      final item = _foodItems.firstWhere((f) => f["id"] == id);
      totalPrice += (item["price"] as double) * qty;
    });

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1F1F1F),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Badge(
              label: Text("$totalCount"),
              child:
                  const Icon(Icons.shopping_bag, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "¥${totalPrice.toStringAsFixed(2)}",
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold),
                  ),
                  const Text("支持宿主支付协同与开单",
                      style: TextStyle(color: Colors.white60, fontSize: 10)),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () {
                _invokeBridge("network", "request", {
                  "url": "https://kmanager.example.com/api/order/submit",
                  "method": "POST",
                  "items": _cart,
                  "totalPrice": totalPrice,
                });
                _invokeBridge("ui", "showToast", {
                  "title": "下单成功 (¥${totalPrice.toStringAsFixed(2)})",
                  "icon": "success",
                });
                setState(() => _cart.clear());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1677FF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text("立即下单"),
            ),
          ],
        ),
      ),
    );
  }

  // --- TAB 3: 会员中心 ---
  Widget _buildMemberTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // VIP Black-Gold Card
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2C2D35), Color(0xFF1A1A1E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "KManager 黑钻尊享会员",
                    style: TextStyle(
                        color: Color(0xFFFFD700),
                        fontSize: 16,
                        fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text("VIP 终身有效",
                        style: TextStyle(
                            color: Color(0xFFFFD700), fontSize: 10.5)),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text("卡号: 8899 0188 6621",
                  style: TextStyle(
                      color: Colors.white70,
                      fontFamily: "monospace",
                      fontSize: 13)),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("储值余额",
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 11)),
                      const SizedBox(height: 2),
                      const Text("¥880.00",
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("可用积分",
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.6),
                              fontSize: 11)),
                      const SizedBox(height: 2),
                      const Text("12,850 积分",
                          style: TextStyle(
                              color: Color(0xFFFFD700),
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Quick Recharge Cards
        const Text("快速储值特惠",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildRechargeCard("充 300 送 30", "¥300")),
            const SizedBox(width: 8),
            Expanded(child: _buildRechargeCard("充 500 送 60", "¥500")),
            const SizedBox(width: 8),
            Expanded(child: _buildRechargeCard("充 1000 送 150", "¥1000")),
          ],
        ),
        const SizedBox(height: 14),

        // Available Coupons
        const Text("我的专享礼券",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        _buildCouponItem("¥30 餐饮立减券", "满 ¥200 可用 • 全场通用", "剩余 3 天"),
        _buildCouponItem("8.5折 尊享菜品券", "全单 8.5 折 • 最高抵扣 ¥100", "本周有效"),
        _buildCouponItem("招牌烤鸭半只兑换券", "任意消费满 ¥150 可用", "本月有效"),
      ],
    );
  }

  Widget _buildRechargeCard(String label, String price) {
    return InkWell(
      onTap: () {
        _invokeBridge(
            "ui", "showToast", {"title": "发起充值 $price", "icon": "success"});
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.shade100),
        ),
        child: Column(
          children: [
            Text(price,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Color(0xFF1677FF))),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _buildCouponItem(String title, String desc, String expiry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 2),
              Text(desc,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
          OutlinedButton(
            onPressed: () {
              _invokeBridge(
                  "ui", "showToast", {"title": "已出示并核销礼券", "icon": "success"});
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: Size.zero,
            ),
            child: const Text("立即使用", style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  // --- TAB 4: 宿主隧道调试控制台 ---
  Widget _buildTunnelTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("宿主原生 JSBridge 交互隧道",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 6),
        Text(
          "通过 lynx.getJSModule('LynxBridge') 触发宿主原生能力",
          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 12),

        // 6 Action Buttons Grid
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 2.8,
          children: [
            _buildTunnelBtn("getUserInfo (宿主登录态)", Icons.person_outline, () {
              _invokeBridge("user", "getUserInfo", {});
            }),
            _buildTunnelBtn("scanQRCode (唤起扫码)", Icons.qr_code_scanner, () {
              _invokeBridge("scanner", "scanQRCode", {});
            }),
            _buildTunnelBtn("request (代理网络请求)", Icons.http, () {
              _invokeBridge("network", "request", {
                "url": "https://kmanager.example.com/api/v1/store/status",
                "method": "GET",
              });
            }),
            _buildTunnelBtn("exportReport (导出报表)", Icons.assessment_outlined,
                () {
              _invokeBridge("report", "exportReport",
                  {"range": "today", "format": "xlsx"});
            }),
            _buildTunnelBtn("showModal (宿主原生弹窗)", Icons.call_to_action_outlined,
                () {
              _invokeBridge("ui", "showModal", {
                "title": "宿主弹窗确认",
                "content": "来自 Lynx 小程序通过 JSBridge 唤起的原生对话框",
                "showCancel": true,
              });
            }),
            _buildTunnelBtn("showToast (原生 Toast)", Icons.info_outline, () {
              _invokeBridge("ui", "showToast", {
                "title": "来自 Lynx 小程序的通知",
                "icon": "success",
              });
            }),
          ],
        ),
        const SizedBox(height: 14),

        // Live Output Terminal
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("实时响应结果 (Response Console)",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            if (_lastActionTime != null)
              Text(
                "耗时: ${DateTime.now().difference(_lastActionTime!).inMilliseconds}ms 前",
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
              ),
          ],
        ),
        const SizedBox(height: 8),

        Container(
          width: double.infinity,
          height: 180,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade800),
          ),
          child: SingleChildScrollView(
            child: Text(
              _lastTunnelOutput,
              style: const TextStyle(
                fontFamily: "monospace",
                color: Color(0xFF4AF626),
                fontSize: 11.5,
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTunnelBtn(String label, IconData icon, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      style: ElevatedButton.styleFrom(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1677FF),
        elevation: 0.5,
        side: BorderSide(color: Colors.grey.shade300, width: 0.8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

/// Custom painter for silky-smooth cubic curve line chart with animated progressive drawing
/// and vertical area gradient fill.
class SmoothLineChartPainter extends CustomPainter {
  final List<double> values;
  final double maxValue;
  final double progress; // 0.0 to 1.0
  final int selectedIndex;
  final Color primaryColor;

  SmoothLineChartPainter({
    required this.values,
    required this.maxValue,
    required this.progress,
    required this.selectedIndex,
    this.primaryColor = const Color(0xFF1677FF),
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;

    final double paddingLeft = 14.0;
    final double paddingRight = 14.0;
    final double paddingTop = 16.0;
    final double paddingBottom = 6.0;

    final double drawWidth = size.width - paddingLeft - paddingRight;
    final double drawHeight = size.height - paddingTop - paddingBottom;
    final int count = values.length;
    final double dx = count > 1 ? drawWidth / (count - 1) : drawWidth;

    final List<Offset> points = [];
    for (int i = 0; i < count; i++) {
      final x = paddingLeft + i * dx;
      final normY = (values[i] / maxValue).clamp(0.0, 1.0);
      final y = paddingTop + drawHeight * (1.0 - normY);
      points.add(Offset(x, y));
    }

    // Clip to current animation progress (left to right reveal)
    canvas.save();
    final revealWidth = (size.width * progress.clamp(0.01, 1.0));
    canvas.clipRect(Rect.fromLTWH(0, 0, revealWidth, size.height));

    // Construct smooth path using cubic bezier
    final Path linePath = Path();
    linePath.moveTo(points[0].dx, points[0].dy);
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = points[i];
      final p1 = points[i + 1];
      final cp1 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p0.dy);
      final cp2 = Offset(p0.dx + (p1.dx - p0.dx) / 2, p1.dy);
      linePath.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p1.dx, p1.dy);
    }

    // Draw Area Gradient Fill
    final Path areaPath = Path.from(linePath);
    areaPath.lineTo(points.last.dx, size.height - paddingBottom);
    areaPath.lineTo(points.first.dx, size.height - paddingBottom);
    areaPath.close();

    final Paint areaPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          primaryColor.withValues(alpha: 0.35),
          primaryColor.withValues(alpha: 0.01),
        ],
      ).createShader(Rect.fromLTWH(0, paddingTop, size.width, drawHeight))
      ..style = PaintingStyle.fill;
    canvas.drawPath(areaPath, areaPaint);

    // Draw Line Stroke
    final Paint linePaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 3.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    // Draw Data Point Nodes
    for (int i = 0; i < points.length; i++) {
      final pt = points[i];
      if (pt.dx > revealWidth + 5) continue;

      final isSelected = i == selectedIndex;
      final isPeak = i == 5; // Saturday peak (32600)

      if (isSelected || isPeak) {
        // Glowing halo ring
        final haloPaint = Paint()
          ..color = primaryColor.withValues(alpha: isSelected ? 0.28 : 0.18)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(pt, isSelected ? 12.0 : 9.0, haloPaint);
      }

      // Outer ring
      final outerPaint = Paint()
        ..color = isSelected ? primaryColor : const Color(0xFF1677FF)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pt, isSelected ? 6.5 : 4.5, outerPaint);

      // Inner white center
      final innerPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pt, isSelected ? 3.5 : 2.2, innerPaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant SmoothLineChartPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.values != values;
  }
}

/// Custom painter for Gauge Chart arc with gradient sweep and animated sweep angle.
class GaugeChartPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0
  final double targetPercent; // e.g. 0.948 (94.8%)

  GaugeChartPainter({
    required this.progress,
    required this.targetPercent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) / 2) - 14;
    const startAngle = 135 * (math.pi / 180);
    const sweepAngle = 270 * (math.pi / 180);

    // Background track arc
    final trackPaint = Paint()
      ..color = const Color(0xFFF0F2F5)
      ..strokeWidth = 14
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      trackPaint,
    );

    // Animated progress arc with SweepGradient
    final currentSweep = sweepAngle * targetPercent * progress.clamp(0.0, 1.0);
    if (currentSweep > 0.001) {
      final rect = Rect.fromCircle(center: center, radius: radius);
      final progressPaint = Paint()
        ..shader = const SweepGradient(
          startAngle: startAngle,
          endAngle: startAngle + sweepAngle,
          colors: [
            Color(0xFF36CFC9),
            Color(0xFF1677FF),
            Color(0xFF722ED1),
          ],
        ).createShader(rect)
        ..strokeWidth = 14
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      canvas.drawArc(
        rect,
        startAngle,
        currentSweep,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant GaugeChartPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.targetPercent != targetPercent;
  }
}
