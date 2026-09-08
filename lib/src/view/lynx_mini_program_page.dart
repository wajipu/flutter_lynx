import "dart:async";
import "dart:convert";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "lynx_view.dart";
import "lynx_controller.dart";
import "../manager/mini_program_manifest.dart";
import "../manager/lynx_mini_program_manager.dart";
import "../models/lynx_template_data.dart";
import "../models/lynx_load_status.dart";
import "../bridge/lynx_bridge.dart";
import "../bridge/lynx_bridge_request.dart";
import "../utils/lynx_logger.dart";

/// Ready-to-use Dynamic Mini Program Page container.
/// Provides a WeChat/Alipay style mini-program capsule bar, real-time loading logs,
/// bundle download progress, error recovery, dual layout modes (Native Engine / Business UI),
/// and comprehensive Host JSBridge Tunnel testing.
class LynxMiniProgramPage extends StatefulWidget {
  final MiniProgramManifest manifest;
  final Map<String, dynamic>? initialData;

  const LynxMiniProgramPage({
    super.key,
    required this.manifest,
    this.initialData,
  });

  @override
  State<LynxMiniProgramPage> createState() => _LynxMiniProgramPageState();
}

class _LynxMiniProgramPageState extends State<LynxMiniProgramPage> {
  LynxLoadStatus _status = LynxLoadStatus.initial;
  double _downloadProgress = 0.0;
  String? _errorMessage;
  String? _bundlePath;
  String _pageTitle = "";
  LynxController? _controller;

  // View Mode: 'business' = Rich layout rendering, 'platform' = Native Lynx Engine
  bool _showNativePlatformView = false;

  // Current active layout tab for comprehensive demo
  int _activeLayoutIndex = 0;

  // Real-time lifecycle logging
  final List<String> _logs = [];
  final ScrollController _logScrollController = ScrollController();
  String _currentStep = "初始化运行环境...";
  Timer? _compilingWatchdog;
  final DateTime _startTime = DateTime.now();

  // Bridge Tunnel Debug State
  String _lastBridgeMethod = "";
  String _lastBridgeResult = "尚未触发宿主调用";
  int _lastBridgeLatencyMs = 0;

  // Order Menu State
  int _selectedCategoryIndex = 0;
  final Map<String, int> _cart = {};

  // Desk State
  String _deskFilter = "全部";

  @override
  void initState() {
    super.initState();
    _pageTitle = widget.manifest.name;

    // Default layout based on manifest appId
    if (widget.manifest.appId.contains("desk")) {
      _activeLayoutIndex = 0;
    } else if (widget.manifest.appId.contains("order")) {
      _activeLayoutIndex = 1;
    } else if (widget.manifest.appId.contains("member")) {
      _activeLayoutIndex = 2;
    } else {
      _activeLayoutIndex = 3; // Tunnel console
    }

    _loadMiniProgram();
  }

  @override
  void dispose() {
    _compilingWatchdog?.cancel();
    _logScrollController.dispose();
    super.dispose();
  }

  void _addLog(String msg) {
    final now = DateTime.now();
    final cost = now.difference(_startTime).inMilliseconds;
    final timestamp = now.toIso8601String().substring(11, 19);
    final logEntry = "[$timestamp +${cost}ms] $msg";

    LynxLogger.info("MiniApp:${widget.manifest.appId}", msg);

    if (mounted) {
      setState(() {
        _logs.add(logEntry);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_logScrollController.hasClients) {
          _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
        }
      });
    }
  }

  Future<void> _loadMiniProgram() async {
    setState(() {
      _status = LynxLoadStatus.downloading;
      _downloadProgress = 0.0;
      _errorMessage = null;
      _logs.clear();
      _currentStep = "正在准备小程序依赖资源...";
    });

    _addLog("启动小程序: ${widget.manifest.name} (v${widget.manifest.version})");
    _addLog("App ID: ${widget.manifest.appId}");
    _addLog("资源地址: ${widget.manifest.bundleUrl}");

    try {
      _currentStep = "检查本地缓存与资源...";
      _addLog("正在检索本地沙盒缓存与内置包...");

      final path = await LynxMiniProgramManager.instance.prepareBundle(
        widget.manifest,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
              _currentStep = "下载资源中: ${(progress * 100).toStringAsFixed(0)}%";
            });
            if (progress >= 1.0 || progress == 0.0 || (progress * 100).toInt() % 25 == 0) {
              _addLog("Bundle 下载进度: ${(progress * 100).toStringAsFixed(0)}%");
            }
          }
        },
      );

      if (mounted) {
        _addLog("Bundle 资源就绪: $path");
        _addLog("启动原生 Lynx 渲染引擎与 JSBridge 隧道...");
        setState(() {
          _bundlePath = path;
          _status = LynxLoadStatus.compiling;
          _currentStep = "正在加载 Lynx 原生视图...";
        });

        // Watchdog: auto-promote to success within 400ms so the user never gets stuck
        _compilingWatchdog?.cancel();
        _compilingWatchdog = Timer(const Duration(milliseconds: 400), () {
          if (mounted && _status == LynxLoadStatus.compiling) {
            _addLog("首屏就绪保底生效 (快速呈现)");
            setState(() {
              _status = LynxLoadStatus.success;
              _currentStep = "运行中";
            });
          }
        });
      }
    } catch (e) {
      if (mounted) {
        _addLog("加载失败: $e");
        setState(() {
          _status = LynxLoadStatus.failed;
          _errorMessage = e.toString();
          _currentStep = "加载遇到错误";
        });
      }
    }
  }

  /// Invoke Host JSBridge Tunnel
  Future<void> _invokeHostTunnel(String module, String method, Map<String, dynamic> params) async {
    final start = DateTime.now();
    _addLog("隧道调用 >> $module.$method(${jsonEncode(params)})");

    final req = LynxBridgeRequest(
      callId: "call_${DateTime.now().millisecondsSinceEpoch}",
      module: module,
      method: method,
      params: params,
    );

    final res = await LynxBridge.instance.dispatch(req.toMap());
    final cost = DateTime.now().difference(start).inMilliseconds;

    _addLog("隧道返回 << $module.$method (耗时: ${cost}ms)");

    if (mounted) {
      setState(() {
        _lastBridgeMethod = "$module.$method";
        _lastBridgeLatencyMs = cost;
        final encoder = const JsonEncoder.withIndent("  ");
        _lastBridgeResult = encoder.convert(res);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("宿主隧道 $module.$method 响应成功 (${cost}ms)"),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showLogModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.terminal, color: Colors.greenAccent, size: 20),
                const SizedBox(width: 8),
                Text(
                  "${widget.manifest.name} - 运行与调试日志",
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy, color: Colors.white70, size: 18),
                  tooltip: "复制日志",
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _logs.join("\n")));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("日志已复制到剪贴板")),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Text("AppID: ${widget.manifest.appId}", style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  const SizedBox(width: 12),
                  Text("版本: v${widget.manifest.version}", style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  const Spacer(),
                  Text("状态: ${_status.name}", style: const TextStyle(color: Colors.amberAccent, fontSize: 11)),
                ],
              ),
            ),
            const Divider(color: Colors.white24),
            Expanded(
              child: ListView.builder(
                itemCount: _logs.length,
                itemBuilder: (ctx, idx) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      _logs[idx],
                      style: const TextStyle(
                        fontFamily: "monospace",
                        color: Color(0xFFA6E3A1),
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white30),
                    ),
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await LynxMiniProgramManager.instance.clearCache(appId: widget.manifest.appId);
                      _addLog("已清空本地沙盒缓存");
                      _loadMiniProgram();
                    },
                    icon: const Icon(Icons.cleaning_services, size: 16),
                    label: const Text("清除缓存重新拉取"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1677FF),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _controller?.reload();
                      _addLog("重载原生视图");
                    },
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text("重载页面"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: Color(0xFF1677FF)),
            const SizedBox(width: 8),
            Text(widget.manifest.name),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("App ID: ${widget.manifest.appId}"),
            const SizedBox(height: 4),
            Text("版本: v${widget.manifest.version}"),
            if (widget.manifest.description != null) ...[
              const SizedBox(height: 4),
              Text("描述: ${widget.manifest.description}"),
            ],
            const SizedBox(height: 8),
            const Text(
              "双向宿主 JSBridge 隧道已就绪",
              style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              "基于 LynxJS 动态引擎架构驱动",
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              _showLogModal();
            },
            icon: const Icon(Icons.terminal, size: 16),
            label: const Text("查看调测日志"),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("关闭"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Column(
          children: [
            // Top Mini Program Capsule Bar
            _buildCapsuleBar(),

            // Multi-Layout Navigation Bar
            _buildLayoutTabBar(),

            // Content Area
            Expanded(
              child: _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapsuleBar() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFEEEEEE), width: 0.8),
        ),
      ),
      child: Row(
        children: [
          // Close button on left
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, size: 18),
            onPressed: () => Navigator.of(context).pop(),
            tooltip: "返回",
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),

          // Mini Program Title
          Expanded(
            child: Text(
              _pageTitle,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Toggle View Mode: Business Layout vs Native Platform Engine
          InkWell(
            onTap: () {
              setState(() {
                _showNativePlatformView = !_showNativePlatformView;
              });
              _addLog(_showNativePlatformView ? "切换至 Lynx 原生 PlatformView" : "切换至 小程序业务渲染视图");
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: _showNativePlatformView ? Colors.orange.shade50 : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _showNativePlatformView ? Colors.orange.shade300 : Colors.blue.shade300,
                  width: 0.6,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _showNativePlatformView ? Icons.developer_board : Icons.palette_outlined,
                    size: 12,
                    color: _showNativePlatformView ? Colors.orange.shade800 : const Color(0xFF1677FF),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    _showNativePlatformView ? "引擎视图" : "业务视图",
                    style: TextStyle(
                      fontSize: 11,
                      color: _showNativePlatformView ? Colors.orange.shade800 : const Color(0xFF1677FF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Quick Log Badge Button
          InkWell(
            onTap: _showLogModal,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300, width: 0.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.terminal, size: 12, color: Color(0xFF1677FF)),
                  const SizedBox(width: 3),
                  Text(
                    "日志 (${_logs.length})",
                    style: const TextStyle(fontSize: 11, color: Color(0xFF1677FF), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),

          // Capsule Buttons (··· | ✕)
          Container(
            height: 28,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade300, width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.more_horiz, size: 15, color: Colors.black87),
                  onPressed: _showInfoDialog,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  constraints: const BoxConstraints(),
                ),
                Container(
                  width: 0.8,
                  height: 14,
                  color: Colors.grey.shade300,
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 15, color: Colors.black87),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Multi-layout tab bar allowing the user to switch between 4 different layouts
  Widget _buildLayoutTabBar() {
    final tabs = [
      {"icon": Icons.table_restaurant, "label": "桌台看板"},
      {"icon": Icons.restaurant_menu, "label": "点餐双列"},
      {"icon": Icons.card_membership, "label": "会员瀑布"},
      {"icon": Icons.cable, "label": "宿主隧道"},
    ];

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: List.generate(tabs.length, (idx) {
          final isSelected = _activeLayoutIndex == idx;
          final tab = tabs[idx];
          return Expanded(
            child: InkWell(
              onTap: () {
                setState(() {
                  _activeLayoutIndex = idx;
                });
                _addLog("切换布局: ${tab['label']}");
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF1677FF).withValues(alpha: 0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      tab["icon"] as IconData,
                      size: 16,
                      color: isSelected ? const Color(0xFF1677FF) : Colors.grey.shade600,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tab["label"] as String,
                      style: TextStyle(
                        fontSize: 11,
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

  Widget _buildContent() {
    switch (_status) {
      case LynxLoadStatus.initial:
      case LynxLoadStatus.downloading:
      case LynxLoadStatus.compiling:
        return _buildLoadingScreen();

      case LynxLoadStatus.success:
        if (_bundlePath == null) return const SizedBox();

        // If toggled to Native PlatformView
        if (_showNativePlatformView) {
          final combinedInitialData = <String, dynamic>{
            ...?widget.manifest.initialData,
            ...?widget.initialData,
          };

          return LynxView(
            url: _bundlePath!,
            initialData: LynxTemplateData(combinedInitialData),
            onLynxCreated: (controller) {
              _controller = controller;
              _addLog("原生 PlatformView 已挂载 (viewId: ${controller.viewId})");
            },
            onLoadSuccess: () {
              _addLog("Lynx 页面首屏加载成功！");
            },
            onLoadFail: (err) {
              _addLog("Lynx 渲染错误: $err");
              if (mounted) {
                setState(() {
                  _status = LynxLoadStatus.failed;
                  _errorMessage = err;
                });
              }
            },
          );
        }

        // Render the active Layout
        switch (_activeLayoutIndex) {
          case 0:
            return _buildDeskManagementLayout();
          case 1:
            return _buildOrderMenuLayout();
          case 2:
            return _buildMemberCenterLayout();
          case 3:
          default:
            return _buildBridgePlaygroundLayout();
        }

      case LynxLoadStatus.failed:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 56, color: Colors.redAccent),
                const SizedBox(height: 16),
                const Text(
                  "小程序加载失败",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage ?? "未知错误",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _showLogModal,
                  icon: const Icon(Icons.terminal, size: 16),
                  label: const Text("查看排查日志"),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _loadMiniProgram,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text("重新加载"),
                ),
              ],
            ),
          ),
        );
    }
  }

  // ==========================================
  // Layout 1: 餐饮桌台管理看板 (Desk Grid Layout)
  // ==========================================
  Widget _buildDeskManagementLayout() {
    final List<Map<String, dynamic>> desks = [
      {"id": "A01", "name": "大厅A01", "capacity": 4, "status": "occupied", "amount": 288.0, "time": "42m"},
      {"id": "A02", "name": "大厅A02", "capacity": 4, "status": "idle", "amount": 0.0, "time": "-"},
      {"id": "A03", "name": "大厅A03", "capacity": 6, "status": "reserved", "amount": 500.0, "time": "18:30"},
      {"id": "A05", "name": "靠窗A05", "capacity": 2, "status": "occupied", "amount": 168.0, "time": "15m"},
      {"id": "B01", "name": "包厢B01 (聚宝阁)", "capacity": 10, "status": "occupied", "amount": 1288.0, "time": "1h10m"},
      {"id": "B02", "name": "包厢B02 (如意居)", "capacity": 12, "status": "idle", "amount": 0.0, "time": "-"},
      {"id": "C01", "name": "露台C01", "capacity": 4, "status": "idle", "amount": 0.0, "time": "-"},
      {"id": "C02", "name": "露台C02", "capacity": 4, "status": "occupied", "amount": 340.0, "time": "58m"},
    ];

    final filteredDesks = desks.where((d) {
      if (_deskFilter == "空闲") return d["status"] == "idle";
      if (_deskFilter == "就餐中") return d["status"] == "occupied";
      if (_deskFilter == "预定") return d["status"] == "reserved";
      return true;
    }).toList();

    return Column(
      children: [
        // Stats bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Colors.white,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem("空闲桌台", "3", Colors.green),
              _buildStatItem("就餐中", "4", const Color(0xFF1677FF)),
              _buildStatItem("今日已预定", "1", Colors.orange),
              _buildStatItem("累计流水", "¥2,084", Colors.black87),
            ],
          ),
        ),

        // Filter chips
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: ["全部", "空闲", "就餐中", "预定"].map((f) {
              final isSel = _deskFilter == f;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(f, style: TextStyle(fontSize: 12, color: isSel ? Colors.white : Colors.black87)),
                  selected: isSel,
                  selectedColor: const Color(0xFF1677FF),
                  backgroundColor: Colors.white,
                  checkmarkColor: Colors.white,
                  onSelected: (val) {
                    setState(() => _deskFilter = f);
                  },
                ),
              );
            }).toList(),
          ),
        ),

        // Desk Grid
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.35,
            ),
            itemCount: filteredDesks.length,
            itemBuilder: (ctx, idx) {
              final desk = filteredDesks[idx];
              final status = desk["status"] as String;
              final isOccupied = status == "occupied";
              final isIdle = status == "idle";

              Color statusColor = Colors.grey;
              String statusText = "未知";
              if (isIdle) {
                statusColor = Colors.green;
                statusText = "空闲中";
              } else if (isOccupied) {
                statusColor = const Color(0xFF1677FF);
                statusText = "就餐中";
              } else {
                statusColor = Colors.orange;
                statusText = "已预定";
              }

              return InkWell(
                onTap: () {
                  _showDeskActionSheet(desk);
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isOccupied ? const Color(0xFF1677FF).withValues(alpha: 0.4) : Colors.grey.shade200,
                      width: isOccupied ? 1.5 : 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            desk["name"],
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
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
                      Text(
                        "容量: ${desk['capacity']}人 • 时长: ${desk['time']}",
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isOccupied ? "¥${desk['amount']}" : "-",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isOccupied ? Colors.redAccent : Colors.grey,
                            ),
                          ),
                          const Icon(Icons.arrow_forward_ios, size: 10, color: Colors.grey),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: color)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }

  void _showDeskActionSheet(Map<String, dynamic> desk) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.table_bar, color: Color(0xFF1677FF)),
                const SizedBox(width: 8),
                Text(
                  desk["name"],
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
                const Spacer(),
                Text("状态: ${desk['status']}", style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _invokeHostTunnel("scanner", "scanQRCode", {"deskId": desk["id"]});
                    },
                    icon: const Icon(Icons.qr_code_scanner, size: 16),
                    label: const Text("扫码加菜 (调用宿主)"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _invokeHostTunnel("network", "request", {
                        "url": "/api/v1/desk/checkout",
                        "method": "POST",
                        "deskId": desk["id"],
                        "amount": desk["amount"],
                      });
                    },
                    icon: const Icon(Icons.payment, size: 16),
                    label: const Text("清台结账 (代理网络)"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // Layout 2: 扫码点餐双列货架 (Sidebar + Product Shelf)
  // ==========================================
  Widget _buildOrderMenuLayout() {
    final categories = ["🔥 热销榜", "🥩 精选主菜", "🍜 特色主食", "🥤 现调饮品", "🍰 甜点小吃"];
    final List<Map<String, dynamic>> products = [
      {"id": "p01", "name": "招牌秘制牛腩煲", "price": 68.0, "sales": 320, "rate": "98%", "cat": 0, "emoji": "🥘"},
      {"id": "p02", "name": "潮汕手打鲜牛肉丸", "price": 38.0, "sales": 450, "rate": "99%", "cat": 0, "emoji": "🍢"},
      {"id": "p03", "name": "极佳级安格斯眼肉", "price": 98.0, "sales": 180, "rate": "96%", "cat": 1, "emoji": "🥩"},
      {"id": "p04", "name": "香辣鲜脆毛肚", "price": 42.0, "sales": 510, "rate": "99%", "cat": 1, "emoji": "🍲"},
      {"id": "p05", "name": "广式腊味煲仔饭", "price": 32.0, "sales": 260, "rate": "95%", "cat": 2, "emoji": "🍚"},
      {"id": "p06", "name": "原汤牛腩手工粉", "price": 26.0, "sales": 390, "rate": "97%", "cat": 2, "emoji": "🍜"},
      {"id": "p07", "name": "生椰爆打柠檬茶", "price": 18.0, "sales": 680, "rate": "98%", "cat": 3, "emoji": "🍋"},
      {"id": "p08", "name": "经典港式冻奶茶", "price": 16.0, "sales": 420, "rate": "96%", "cat": 3, "emoji": "🧋"},
      {"id": "p09", "name": "酥炸金黄鸡中翅", "price": 28.0, "sales": 210, "rate": "94%", "cat": 4, "emoji": "🍗"},
      {"id": "p10", "name": "红糖软糯手工糍粑", "price": 22.0, "sales": 340, "rate": "97%", "cat": 4, "emoji": "🥮"},
    ];

    final filteredProducts = products.where((p) => p["cat"] == _selectedCategoryIndex).toList();

    int totalCount = 0;
    double totalPrice = 0.0;
    _cart.forEach((pid, count) {
      if (count > 0) {
        final p = products.firstWhere((element) => element["id"] == pid, orElse: () => {});
        if (p.isNotEmpty) {
          totalCount += count;
          totalPrice += (p["price"] as double) * count;
        }
      }
    });

    return Column(
      children: [
        // Desk info banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: Colors.amber.shade50,
          child: Row(
            children: [
              const Icon(Icons.table_restaurant, size: 16, color: Colors.orange),
              const SizedBox(width: 8),
              const Text(
                "当前就餐桌号: 大厅 A08 • 4人就餐",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.brown),
              ),
              const Spacer(),
              InkWell(
                onTap: () => _invokeHostTunnel("ui", "showToast", {"title": "呼叫服务员已收到"}),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text("呼叫服务", style: TextStyle(color: Colors.white, fontSize: 11)),
                ),
              ),
            ],
          ),
        ),

        // Dual-Column Body
        Expanded(
          child: Row(
            children: [
              // Left Category Sidebar
              Container(
                width: 90,
                color: const Color(0xFFF1F2F5),
                child: ListView.builder(
                  itemCount: categories.length,
                  itemBuilder: (ctx, idx) {
                    final isSel = _selectedCategoryIndex == idx;
                    return InkWell(
                      onTap: () {
                        setState(() => _selectedCategoryIndex = idx);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                        decoration: BoxDecoration(
                          color: isSel ? Colors.white : Colors.transparent,
                          border: Border(
                            left: BorderSide(
                              color: isSel ? const Color(0xFF1677FF) : Colors.transparent,
                              width: 3.5,
                            ),
                          ),
                        ),
                        child: Text(
                          categories[idx],
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            color: isSel ? const Color(0xFF1677FF) : Colors.grey.shade700,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Right Product List
              Expanded(
                child: Container(
                  color: Colors.white,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: filteredProducts.length,
                    separatorBuilder: (_, __) => const Divider(height: 16, color: Color(0xFFEEEEEE)),
                    itemBuilder: (ctx, idx) {
                      final item = filteredProducts[idx];
                      final pid = item["id"] as String;
                      final count = _cart[pid] ?? 0;

                      return Row(
                        children: [
                          Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(item["emoji"], style: const TextStyle(fontSize: 28)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item["name"],
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  "月售 ${item['sales']} • 好评率 ${item['rate']}",
                                  style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "¥${item['price']}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.redAccent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Stepper
                          Row(
                            children: [
                              if (count > 0) ...[
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      _cart[pid] = count - 1;
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.grey.shade300),
                                    ),
                                    child: const Icon(Icons.remove, size: 14, color: Colors.black87),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  child: Text(
                                    "$count",
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                              ],
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    _cart[pid] = count + 1;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color(0xFF1677FF),
                                  ),
                                  child: const Icon(Icons.add, size: 14, color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),

        // Bottom Sticky Cart Bar
        Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2937),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Badge(
                label: Text("$totalCount"),
                isLabelVisible: totalCount > 0,
                child: const Icon(Icons.shopping_bag_outlined, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "合计: ¥${totalPrice.toStringAsFixed(1)}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const Text(
                      "支持宿主微信/支付宝免密快捷结算",
                      style: TextStyle(color: Colors.white54, fontSize: 10),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: totalCount == 0
                    ? null
                    : () {
                        _invokeHostTunnel("network", "request", {
                          "url": "/api/v1/order/create",
                          "method": "POST",
                          "items": _cart,
                          "totalAmount": totalPrice,
                        });
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1677FF),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text("立即下单"),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // Layout 3: 会员资产与营销中心 (Hero VIP Card + Waterfall)
  // ==========================================
  Widget _buildMemberCenterLayout() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Black-Gold VIP Card
        Container(
          height: 170,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF232526), Color(0xFF414345)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.workspace_premium, color: Color(0xFFFFD700), size: 22),
                      SizedBox(width: 8),
                      Text(
                        "黑金尊享 VIP 会员",
                        style: TextStyle(color: Color(0xFFFFD700), fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD700).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFFD700), width: 0.8),
                    ),
                    child: const Text(
                      "NO. 8866 2026",
                      style: TextStyle(color: Color(0xFFFFD700), fontSize: 10, fontFamily: "monospace"),
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
                      const Text("当前积分余额", style: TextStyle(color: Colors.white54, fontSize: 11)),
                      const SizedBox(height: 2),
                      const Text(
                        "3,580 积分",
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        "储值钱包: ¥1,280.00",
                        style: TextStyle(color: Colors.amber.shade200, fontSize: 12),
                      ),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: () {
                      _invokeHostTunnel("ui", "showModal", {
                        "title": "会员快速充值",
                        "content": "确定调起宿主支付充值 ¥200 赠送 ¥30 吗？",
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    ),
                    child: const Text("在线充值", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Quick 6-Grid Actions
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.2,
            children: [
              _buildMemberGridItem("💳 充值有礼", () {
                _invokeHostTunnel("storage", "setStorage", {"key": "last_topup", "data": 200});
              }),
              _buildMemberGridItem("🎟 优惠卡券", () {
                _invokeHostTunnel("ui", "showToast", {"title": "您有 3 张可用券"});
              }),
              _buildMemberGridItem("🎁 积分兑换", () {
                _invokeHostTunnel("network", "request", {"url": "/api/v1/points/exchange"});
              }),
              _buildMemberGridItem("🧾 电子发票", () {
                _invokeHostTunnel("ui", "showToast", {"title": "正在拉取宿主抬头信息"});
              }),
              _buildMemberGridItem("📊 消费账单", () {
                _invokeHostTunnel("network", "request", {"url": "/api/v1/orders/history"});
              }),
              _buildMemberGridItem("💬 专属管家", () {
                _invokeHostTunnel("user", "getUserInfo", {});
              }),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Coupons Waterfall
        const Text(
          "会员专享优惠券",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        const SizedBox(height: 10),
        _buildCouponCard("¥30", "无门槛堂食立减券", "全场通用 • 满0元可用 • 剩3天到期", Colors.redAccent),
        _buildCouponCard("¥50", "周末聚餐满减券", "限包厢堂食 • 满200元可用 • 剩7天到期", Colors.orange),
        _buildCouponCard("8.8折", "周三会员日专属折扣券", "全单通用 • 最高抵扣100元", const Color(0xFF1677FF)),
      ],
    );
  }

  Widget _buildMemberGridItem(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(label.substring(0, 2), style: const TextStyle(fontSize: 22)),
          const SizedBox(height: 4),
          Text(label.substring(3), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildCouponCard(String value, String title, String subtitle, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 80,
            height: 75,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(10)),
            ),
            alignment: Alignment.center,
            child: Text(
              value,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ElevatedButton(
              onPressed: () {
                _invokeHostTunnel("ui", "showToast", {"title": "领取成功: $title"});
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: const Size(60, 28),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text("领取", style: TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // Layout 4: 宿主隧道 (JSBridge) 双向交互调试面板
  // ==========================================
  Widget _buildBridgePlaygroundLayout() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Tunnel Intro Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1677FF), Color(0xFF0050B3)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.cable, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text(
                    "双向宿主 JSBridge 隧道",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ],
              ),
              SizedBox(height: 6),
              Text(
                "Mini-Program JS ⇄ Native MethodChannel ⇄ Flutter Host",
                style: TextStyle(color: Colors.white70, fontSize: 11, fontFamily: "monospace"),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Section 1: User & System Tunnel
        const Text("1. 身份与环境隧道", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _invokeHostTunnel("user", "getUserInfo", {}),
                icon: const Icon(Icons.person_outline, size: 16),
                label: const Text("getUserInfo", style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _invokeHostTunnel("system", "getSystemInfo", {}),
                icon: const Icon(Icons.phone_iphone, size: 16),
                label: const Text("getSystemInfo", style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Section 2: Hardware & UI Tunnel
        const Text("2. 硬件与原生交互隧道", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _invokeHostTunnel("scanner", "scanQRCode", {}),
                icon: const Icon(Icons.qr_code_scanner, size: 16),
                label: const Text("scanQRCode", style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _invokeHostTunnel("ui", "showModal", {
                  "title": "宿主原生弹窗",
                  "content": "这是由 Lynx 小程序透过 JSB 隧道触发的 Flutter 宿主原生模态框。",
                }),
                icon: const Icon(Icons.chat_bubble_outline, size: 16),
                label: const Text("showModal", style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Section 3: Network & Storage Tunnel
        const Text("3. 网络代理与本地存储隧道", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _invokeHostTunnel("network", "request", {
                  "url": "https://kmanager.example.com/api/v1/store/desks",
                  "method": "GET",
                }),
                icon: const Icon(Icons.cloud_sync, size: 16),
                label: const Text("request (代理)", style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _invokeHostTunnel("storage", "setStorage", {
                  "key": "app_theme",
                  "data": "dark_mode_2026",
                }),
                icon: const Icon(Icons.save_outlined, size: 16),
                label: const Text("setStorage", style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        // Result Terminal Display
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E2E),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade800),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.code, color: Colors.greenAccent, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    "最新隧道调用结果 (${_lastBridgeMethod.isEmpty ? '待触发' : _lastBridgeMethod})",
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  if (_lastBridgeLatencyMs > 0)
                    Text(
                      "耗时: ${_lastBridgeLatencyMs}ms",
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 11),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(color: Colors.white12, height: 1),
              const SizedBox(height: 8),
              SelectableText(
                _lastBridgeResult,
                style: const TextStyle(
                  fontFamily: "monospace",
                  color: Color(0xFFA6E3A1),
                  fontSize: 11,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Loading screen with step-by-step logs and progress
  Widget _buildLoadingScreen() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // App Avatar / Badge
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF1677FF).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF1677FF).withValues(alpha: 0.3)),
              ),
              child: const Icon(
                Icons.widgets_outlined,
                size: 32,
                color: Color(0xFF1677FF),
              ),
            ),
            const SizedBox(height: 16),

            // Title & Version
            Text(
              widget.manifest.name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "v${widget.manifest.version}",
                style: TextStyle(fontSize: 11, color: Colors.blue.shade700, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 20),

            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _downloadProgress > 0 ? _downloadProgress : null,
                minHeight: 4,
                backgroundColor: Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF1677FF)),
              ),
            ),
            const SizedBox(height: 10),

            // Step text
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _currentStep,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  "${(_downloadProgress * 100).toStringAsFixed(0)}%",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontFamily: "monospace"),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Live Loading Logs Box
            Container(
              height: 140,
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1B26),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade800),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.greenAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        "加载实时日志 (Live Logs)",
                        style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      Text(
                        "${_logs.length} 条",
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 6),
                  Expanded(
                    child: ListView.builder(
                      controller: _logScrollController,
                      itemCount: _logs.length,
                      itemBuilder: (ctx, i) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            "> ${_logs[i]}",
                            style: const TextStyle(
                              fontFamily: "monospace",
                              color: Color(0xFF7AA2F7),
                              fontSize: 10.5,
                              height: 1.3,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Force skip / instant load button
            TextButton(
              onPressed: () {
                _compilingWatchdog?.cancel();
                _addLog("用户手动跳过等待，立即呈现视图");
                setState(() {
                  _status = LynxLoadStatus.success;
                });
              },
              child: const Text(
                "跳过等待 (秒开进入)",
                style: TextStyle(fontSize: 12, color: Color(0xFF1677FF)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
