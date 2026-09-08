import "package:flutter/material.dart";
import "lynx_view.dart";
import "lynx_controller.dart";
import "../manager/mini_program_manifest.dart";
import "../manager/lynx_mini_program_manager.dart";
import "../models/lynx_template_data.dart";
import "../models/lynx_load_status.dart";

/// Ready-to-use Dynamic Mini Program Page container.
/// Provides a WeChat/Alipay style mini-program capsule bar, bundle download progress,
/// error recovery, and seamless embedding of the Lynx runtime.
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

  @override
  void initState() {
    super.initState();
    _pageTitle = widget.manifest.name;
    _loadMiniProgram();
  }

  Future<void> _loadMiniProgram() async {
    setState(() {
      _status = LynxLoadStatus.downloading;
      _downloadProgress = 0.0;
      _errorMessage = null;
    });

    try {
      final path = await LynxMiniProgramManager.instance.prepareBundle(
        widget.manifest,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _bundlePath = path;
          _status = LynxLoadStatus.compiling;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = LynxLoadStatus.failed;
          _errorMessage = e.toString();
        });
      }
    }
  }

  void _showInfoDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.blue),
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
              "基于 LynxJS 动态小程序引擎驱动",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 0.5),
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
          const SizedBox(width: 12),

          // Mini Program Title
          Expanded(
            child: Text(
              _pageTitle,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // Mini Program Capsule Buttons (··· | ✕)
          Container(
            height: 30,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.grey.shade300, width: 0.8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.more_horiz, size: 16, color: Colors.black87),
                  onPressed: () {
                    _controller?.reload();
                    _showInfoDialog();
                  },
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  constraints: const BoxConstraints(),
                ),
                Container(
                  width: 0.8,
                  height: 16,
                  color: Colors.grey.shade300,
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16, color: Colors.black87),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
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
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                "正在加载小程序... ${(_downloadProgress * 100).toStringAsFixed(0)}%",
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
            ],
          ),
        );

      case LynxLoadStatus.compiling:
      case LynxLoadStatus.success:
        if (_bundlePath == null) return const SizedBox();
        final combinedInitialData = <String, dynamic>{
          ...?widget.manifest.initialData,
          ...?widget.initialData,
        };

        return Stack(
          children: [
            LynxView(
              url: _bundlePath!,
              initialData: LynxTemplateData(combinedInitialData),
              onLynxCreated: (controller) {
                _controller = controller;
              },
              onLoadSuccess: () {
                if (mounted) {
                  setState(() {
                    _status = LynxLoadStatus.success;
                  });
                }
              },
              onLoadFail: (err) {
                if (mounted) {
                  setState(() {
                    _status = LynxLoadStatus.failed;
                    _errorMessage = err;
                  });
                }
              },
            ),
            if (_status == LynxLoadStatus.compiling)
              Container(
                color: Colors.white,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
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
                const SizedBox(height: 20),
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
}
