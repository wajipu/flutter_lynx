import "dart:async";
import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "lynx_view.dart";
import "lynx_controller.dart";
import "../manager/mini_program_manifest.dart";
import "../manager/lynx_mini_program_manager.dart";
import "../models/lynx_template_data.dart";
import "../models/lynx_load_status.dart";
import "../utils/lynx_logger.dart";

/// Pure, production-grade Dynamic Mini Program Host Container.
/// Does NOT hardcode any business UI: all business layouts, styles, and logic
/// are fully decoupled and rendered from the Lynx TSX/CSS bundle via LynxView.
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

  // Real-time lifecycle logging
  final List<String> _logs = [];
  final ScrollController _logScrollController = ScrollController();
  String _currentStep = "初始化运行环境...";
  Timer? _compilingWatchdog;
  final DateTime _startTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _pageTitle = widget.manifest.name;
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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _logs.add(logEntry);
          });
          if (_logScrollController.hasClients) {
            _logScrollController.jumpTo(_logScrollController.position.maxScrollExtent);
          }
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
    _addLog("Bundle URL: ${widget.manifest.bundleUrl}");

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
        _addLog("Bundle 准备就绪: $path");
        _addLog("启动原生 Lynx 渲染引擎 (PlatformView)...");
        setState(() {
          _bundlePath = path;
          _status = LynxLoadStatus.compiling;
          _currentStep = "正在加载 Lynx 原生视图...";
        });

        // Watchdog: auto-promote to success within 300ms
        _compilingWatchdog?.cancel();
        _compilingWatchdog = Timer(const Duration(milliseconds: 300), () {
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
              "纯 TSX / CSS 动态驱动 • 宿主零侵入",
              style: TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              "基于 LynxJS 引擎原生 PlatformView 渲染",
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
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Top Mini Program Capsule Bar
            _buildCapsuleBar(),

            // Pure Lynx Runtime View
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

          // Quick Log Badge Button
          InkWell(
            onTap: _showLogModal,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: const EdgeInsets.only(right: 8),
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

  Widget _buildContent() {
    switch (_status) {
      case LynxLoadStatus.initial:
      case LynxLoadStatus.downloading:
      case LynxLoadStatus.compiling:
        return _buildLoadingScreen();

      case LynxLoadStatus.success:
        if (_bundlePath == null) return const SizedBox();

        final combinedInitialData = <String, dynamic>{
          ...?widget.manifest.initialData,
          ...?widget.initialData,
        };

        // Pure Lynx PlatformView: all business UI is executed dynamically inside Lynx engine
        return LynxView(
          url: _bundlePath!,
          initialData: LynxTemplateData(combinedInitialData),
          onLynxCreated: (controller) {
            _controller = controller;
            _addLog("原生 LynxView 挂载成功 (viewId: ${controller.viewId})");
          },
          onLoadSuccess: () {
            _addLog("Lynx 动态模板首屏编译渲染完成！");
          },
          onLoadFail: (err) {
            _addLog("Lynx 渲染错误: $err");
            if (mounted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) {
                  setState(() {
                    _status = LynxLoadStatus.failed;
                    _errorMessage = err;
                  });
                }
              });
            }
          },
        );

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
                Icons.bolt,
                size: 36,
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

            // Force skip button
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
