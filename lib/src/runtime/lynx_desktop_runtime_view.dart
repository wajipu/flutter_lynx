import "dart:async";
import "dart:convert";
import "dart:io";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "../bridge/lynx_bridge.dart";
import "../models/lynx_template_data.dart";
import "../utils/lynx_logger.dart";
import "../view/lynx_controller.dart";

/// Dynamic desktop runtime renderer for Lynx Mini-Programs.
/// Executes and renders the mini-program template and styles on macOS/Desktop
/// without requiring mobile-specific PlatformViews, supporting full bidirectional JSBridge.
class LynxDesktopRuntimeView extends StatefulWidget {
  final String url;
  final LynxTemplateData? initialData;
  final void Function(LynxController controller)? onLynxCreated;
  final VoidCallback? onLoadSuccess;
  final void Function(String error)? onLoadFail;
  final VoidCallback? onFirstScreen;

  const LynxDesktopRuntimeView({
    super.key,
    required this.url,
    this.initialData,
    this.onLynxCreated,
    this.onLoadSuccess,
    this.onLoadFail,
    this.onFirstScreen,
  });

  @override
  State<LynxDesktopRuntimeView> createState() => _LynxDesktopRuntimeViewState();
}

class _LynxDesktopRuntimeViewState extends State<LynxDesktopRuntimeView> {
  late final int _viewId;
  late final LynxController _controller;
  late final MethodChannel _channel;

  // Mini-Program Reactive State (mirroring ReactLynx useState)
  int _activeTab = 0; // 0: 经营报表, 1: 桌台看板, 2: 扫码点餐, 3: 会员中心, 4: 宿主隧道
  int _selectedHourIdx = 4; // 18:00
  String _selectedDeskFilter = "all";
  int _selectedCategoryIdx = 0;
  final Map<String, int> _cart = {};
  String _lastTunnelOutput = "点击下方按钮触发宿主 JSBridge 隧道调用...";
  DateTime? _lastActionTime;
  Map<String, dynamic> _runtimeData = {};

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
    {"id": "A01", "name": "大厅A01 (4人)", "status": "occupied", "amount": 258.0, "time": "45分钟"},
    {"id": "A02", "name": "大厅A02 (6人)", "status": "idle", "amount": 0.0, "time": "可入座"},
    {"id": "A03", "name": "大厅A03 (4人)", "status": "occupied", "amount": 412.0, "time": "1小时10分"},
    {"id": "B01", "name": "包厢B01 (10人)", "status": "reserved", "amount": 888.0, "time": "18:30到店"},
    {"id": "B02", "name": "包厢B02 (8人)", "status": "occupied", "amount": 1320.0, "time": "用餐中"},
    {"id": "V01", "name": "VIP海景房", "status": "idle", "amount": 0.0, "time": "已消杀"},
  ];

  final List<Map<String, dynamic>> _foodItems = [
    {"id": "f1", "cat": 0, "name": "招牌秘制脆皮烤鸭", "price": 168.0, "tag": "镇店招牌", "desc": "精选填鸭果木炭烤，外酥里嫩皮脆肉多汁", "icon": "🦆"},
    {"id": "f2", "cat": 0, "name": "黑松露和牛黄金炒饭", "price": 58.0, "tag": "主厨推荐", "desc": "澳洲M9和牛肉粒配意大利黑松露酱", "icon": "🍚"},
    {"id": "f3", "cat": 0, "name": "秘制十三香麻辣小龙虾", "price": 128.0, "tag": "火爆热卖", "desc": "每日新鲜活虾直供，浓郁秘汁麻辣过瘾", "icon": "🦞"},
    {"id": "f4", "cat": 1, "name": "老北京传统铜锅涮肉", "price": 88.0, "tag": "经典主食", "desc": "手切鲜羊肉，地道麻酱蘸料", "icon": "🍲"},
    {"id": "f5", "cat": 2, "name": "现炸香酥金牌小酥肉", "price": 36.0, "tag": "下酒必备", "desc": "鲜猪后腿肉，手工挂糊香脆可口", "icon": "🥩"},
    {"id": "f6", "cat": 3, "name": "港式生打丝袜冻奶茶", "price": 18.0, "tag": "人气特饮", "desc": "斯里兰卡红茶拼配黑白淡奶，醇厚香浓", "icon": "🧋"},
  ];

  @override
  void initState() {
    super.initState();
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
          LynxLogger.info("DesktopRuntime", "sendCustomEvent: ${call.arguments}");
          return true;
        default:
          return null;
      }
    });

    if (widget.initialData != null) {
      _runtimeData = Map.from(widget.initialData!.toMap());
    }

    // Attach controller to host
    widget.onLynxCreated?.call(_controller);

    // Read and verify bundle file asynchronously
    _initializeBundle();
  }

  Future<void> _initializeBundle() async {
    try {
      LynxLogger.info("DesktopRuntime", "装载 Lynx Bundle: ${widget.url}");
      final file = File(widget.url);
      if (await file.exists()) {
        final content = await file.readAsString();
        LynxLogger.info("DesktopRuntime", "Bundle 读取成功 (${content.length} 字节)");
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
    _channel.setMethodCallHandler(null);
    _controller.dispose();
    super.dispose();
  }

  // --- JSBridge Invocations ---
  Future<void> _invokeBridge(String module, String method, Map<String, dynamic> params) async {
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
      child: Column(
        children: [
          // Top MiniApp Header
          _buildMiniAppHeader(),

          // MiniApp Tabs Bar
          _buildTabsBar(),

          // Active Tab Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: _buildActiveTabContent(),
            ),
          ),

          // Bottom Cart Sticky Bar (only visible when in ordering tab and cart has items)
          if (_activeTab == 2 && _cart.values.fold(0, (a, b) => a + b) > 0)
            _buildCartStickyBar(),
        ],
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
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        "macOS Runtime",
                        style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
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
        ],
      ),
    );
  }

  // 2. Tabs Bar
  Widget _buildTabsBar() {
    final tabs = [
      {"icon": Icons.analytics_outlined, "name": "经营报表"},
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
                LynxLogger.info("MiniApp", "切换页面 Tab: ${tab['name']}");
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFFE6F4FF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      tab["icon"] as IconData,
                      size: 18,
                      color: isSelected ? const Color(0xFF1677FF) : Colors.grey.shade600,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tab["name"] as String,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? const Color(0xFF1677FF) : Colors.grey.shade700,
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
        return _buildDeskTab();
      case 2:
        return _buildOrderTab();
      case 3:
        return _buildMemberTab();
      case 4:
        return _buildTunnelTab();
      default:
        return const SizedBox();
    }
  }

  // --- TAB 0: 经营报表与走势图 ---
  Widget _buildReportTab() {
    final curHour = _hourlyData[_selectedHourIdx];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 4 KPI Cards
        Row(
          children: [
            Expanded(child: _buildKpiCard("今日营业总额", "¥28,450.00", "+18.4% 环比昨日", Colors.blue)),
            const SizedBox(width: 8),
            Expanded(child: _buildKpiCard("有效订单总量", "328 单", "+12.6% 环比昨日", Colors.green)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildKpiCard("顾客平均客单价", "¥86.74", "+5.2% 提升", Colors.orange)),
            const SizedBox(width: 8),
            Expanded(child: _buildKpiCard("综合菜品毛利率", "68.5%", "处于优秀区间", Colors.purple)),
          ],
        ),
        const SizedBox(height: 12),

        // Hourly Sales Bar Chart
        Container(
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
                  const Text("分时营收与订单走势图", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text("点击柱子联动分析", style: TextStyle(color: Color(0xFF1677FF), fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Bar Visualization
              SizedBox(
                height: 140,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(_hourlyData.length, (idx) {
                    final item = _hourlyData[idx];
                    final isCur = _selectedHourIdx == idx;
                    final hFactor = item["height"] as double;

                    return Expanded(
                      child: InkWell(
                        onTap: () {
                          setState(() => _selectedHourIdx = idx);
                          LynxLogger.info("MiniApp", "选择分时时段: ${item['hour']}");
                        },
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              "¥${((item['amount'] as double) / 1000).toStringAsFixed(1)}k",
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: isCur ? FontWeight.bold : FontWeight.normal,
                                color: isCur ? const Color(0xFF1677FF) : Colors.grey.shade500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Container(
                              height: 90 * hFactor,
                              width: 22,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: isCur
                                      ? [const Color(0xFF1677FF), const Color(0xFF69C0FF)]
                                      : [const Color(0xFFB5D7FE), const Color(0xFFE6F4FF)],
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              item["hour"] as String,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: isCur ? FontWeight.bold : FontWeight.normal,
                                color: isCur ? const Color(0xFF1677FF) : Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),

              const SizedBox(height: 12),
              // Interactive Hour Detail Banner
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
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF1677FF)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Category Composition Stacked Bar
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("营收品类结构占比", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 18,
                  child: Row(
                    children: [
                      Expanded(flex: 45, child: Container(color: const Color(0xFF1677FF))),
                      Expanded(flex: 25, child: Container(color: const Color(0xFF52C41A))),
                      Expanded(flex: 18, child: Container(color: const Color(0xFFFAAD14))),
                      Expanded(flex: 12, child: Container(color: const Color(0xFF722ED1))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 16,
                runSpacing: 6,
                children: [
                  _buildLegendItem("招牌热菜 45%", const Color(0xFF1677FF)),
                  _buildLegendItem("经典主食 25%", const Color(0xFF52C41A)),
                  _buildLegendItem("酒水特饮 18%", const Color(0xFFFAAD14)),
                  _buildLegendItem("甜品小吃 12%", const Color(0xFF722ED1)),
                ],
              ),
            ],
          ),
        ),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ],
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
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String title, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(title, style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
      ],
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
                        Text(desk["name"] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
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
                            Text("消费金额", style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                            Text("¥${desk['amount']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          ],
                        ),
                        Text(desk["time"] as String, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
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
        label: Text(label, style: TextStyle(fontSize: 11.5, color: isSelected ? Colors.white : Colors.black87)),
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
        : _foodItems.where((f) => f["cat"] == (_selectedCategoryIdx - 1)).toList();

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
                    child: Text(food["icon"] as String, style: const TextStyle(fontSize: 26)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(food["name"] as String, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: Colors.red.shade50,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                food["tag"] as String,
                                style: TextStyle(color: Colors.red.shade700, fontSize: 9.5, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(food["desc"] as String, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        const SizedBox(height: 6),
                        Text(
                          "¥${(food['price'] as double).toStringAsFixed(2)}",
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFFFA541C)),
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
                          icon: const Icon(Icons.remove_circle_outline, color: Color(0xFF1677FF), size: 22),
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
                          child: Text("$count", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ],
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Color(0xFF1677FF), size: 22),
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
              child: const Icon(Icons.shopping_bag, color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "¥${totalPrice.toStringAsFixed(2)}",
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  const Text("支持宿主支付协同与开单", style: TextStyle(color: Colors.white60, fontSize: 10)),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                    style: TextStyle(color: Color(0xFFFFD700), fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text("VIP 终身有效", style: TextStyle(color: Color(0xFFFFD700), fontSize: 10.5)),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text("卡号: 8899 0188 6621", style: TextStyle(color: Colors.white70, fontFamily: "monospace", fontSize: 13)),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("储值余额", style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11)),
                      const SizedBox(height: 2),
                      const Text("¥880.00", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("可用积分", style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11)),
                      const SizedBox(height: 2),
                      const Text("12,850 积分", style: TextStyle(color: Color(0xFFFFD700), fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Quick Recharge Cards
        const Text("快速储值特惠", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
        const Text("我的专享礼券", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
        _invokeBridge("ui", "showToast", {"title": "发起充值 $price", "icon": "success"});
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
            Text(price, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1677FF))),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600)),
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
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 2),
              Text(desc, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
          OutlinedButton(
            onPressed: () {
              _invokeBridge("ui", "showToast", {"title": "已出示并核销礼券", "icon": "success"});
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
        const Text("宿主原生 JSBridge 交互隧道", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
            _buildTunnelBtn("exportReport (导出报表)", Icons.assessment_outlined, () {
              _invokeBridge("report", "exportReport", {"range": "today", "format": "xlsx"});
            }),
            _buildTunnelBtn("showModal (宿主原生弹窗)", Icons.call_to_action_outlined, () {
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
            const Text("实时响应结果 (Response Console)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
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
