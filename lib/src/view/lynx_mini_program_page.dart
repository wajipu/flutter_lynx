import "package:flutter/material.dart";
import "package:flutter/services.dart";

import "../host/lynx_host_capsule.dart";
import "../host/lynx_host_metrics.dart";
import "../manager/lynx_mini_program_manager.dart";
import "../manager/mini_program_manifest.dart";
import "../models/lynx_load_status.dart";
import "../models/lynx_template_data.dart";
import "../utils/lynx_logger.dart";
import "lynx_view.dart";

/// 小程序加载外壳；是否成功必须由原生运行时回调确认。
///
/// 小程序区域全屏铺满，关闭用右上角微信式胶囊，不使用 Flutter `AppBar`。
/// 胶囊由原生画在窗口层，不进 Flutter 树，也不挂在 Lynx PlatformView 上。
/// [applySafeArea] 只决定是否把安全区写进 initData 给小程序排版；宿主不再垫 Flutter 画布。
class LynxMiniProgramPage extends StatefulWidget {
  final MiniProgramManifest manifest;
  final Map<String, dynamic>? initialData;
  final Set<String> allowedModules;

  /// 为 null 时跟随 [MiniProgramManifest.applySafeArea]，默认打开。
  final bool? applySafeArea;

  const LynxMiniProgramPage({
    super.key,
    required this.manifest,
    this.initialData,
    this.allowedModules = const {'system'},
    this.applySafeArea,
  });

  @override
  State<LynxMiniProgramPage> createState() => _LynxMiniProgramPageState();
}

class _LynxMiniProgramPageState extends State<LynxMiniProgramPage> {
  LynxLoadStatus _status = LynxLoadStatus.initial;
  double _downloadProgress = 0.0;
  String? _errorMessage;
  String? _bundlePath;
  String _currentStep = "初始化运行环境...";
  int _loadGeneration = 0;
  bool? _capsuleDark;
  bool _capsuleDismissed = false;
  Animation<double>? _routeAnimation;

  @override
  void initState() {
    super.initState();
    _loadMiniProgram();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (!identical(animation, _routeAnimation)) {
      _routeAnimation?.removeStatusListener(_onRouteStatus);
      _routeAnimation = animation;
      _routeAnimation?.addStatusListener(_onRouteStatus);
    }
    _syncHostCapsule();
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_onRouteStatus);
    _routeAnimation = null;
    _dismissHostCapsule();
    super.dispose();
  }

  void _onRouteStatus(AnimationStatus status) {
    // 返回手势 / 系统返回一开始倒放，就摘胶囊，不等 dispose。
    if (status == AnimationStatus.reverse) {
      _dismissHostCapsule();
    }
  }

  void _dismissHostCapsule() {
    if (_capsuleDismissed) {
      return;
    }
    _capsuleDismissed = true;
    LynxHostCapsule.hide();
  }

  void _syncHostCapsule() {
    if (_capsuleDismissed) {
      return;
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (_capsuleDark == dark) {
      return;
    }
    if (_capsuleDark == null) {
      LynxHostCapsule.show(
        dark: dark,
        onMore: _showMoreActions,
        onClose: _closeMiniProgram,
      );
    } else {
      LynxHostCapsule.setDark(dark);
    }
    _capsuleDark = dark;
  }

  void _log(String msg) {
    LynxLogger.info("MiniApp:${widget.manifest.appId}", msg);
  }

  void _closeMiniProgram() {
    // 先摘窗口层胶囊，再 pop；否则要等转场结束 dispose 才会消失。
    _dismissHostCapsule();
    if (!mounted) {
      return;
    }
    _log("宿主胶囊关闭");
    Navigator.of(context).maybePop();
  }

  void _showMoreActions() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListTile(
          leading: const Icon(Icons.refresh),
          title: const Text("重新加载"),
          onTap: () {
            Navigator.of(ctx).pop();
            _loadMiniProgram();
          },
        ),
      ),
    );
  }

  Future<void> _loadMiniProgram() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    setState(() {
      _status = LynxLoadStatus.downloading;
      _downloadProgress = 0.0;
      _errorMessage = null;
      _bundlePath = null;
      _currentStep = "正在准备小程序依赖资源...";
    });

    _log("启动小程序: ${widget.manifest.name} (v${widget.manifest.version})");
    _log("Bundle URL: ${widget.manifest.bundleUrl}");

    try {
      _currentStep = "检查本地缓存与资源...";
      final path = await LynxMiniProgramManager.instance.prepareBundle(
        widget.manifest,
        onProgress: (progress) {
          if (!mounted || generation != _loadGeneration) return;
          setState(() {
            _downloadProgress = progress;
            _currentStep = "下载资源中: ${(progress * 100).toStringAsFixed(0)}%";
          });
        },
      );

      if (mounted && generation == _loadGeneration) {
        _log("Bundle 准备就绪: $path");
        setState(() {
          _bundlePath = path;
          _status = LynxLoadStatus.compiling;
          _currentStep = "正在加载 Lynx 原生视图...";
        });
      }
    } catch (e) {
      if (mounted && generation == _loadGeneration) {
        _log("加载失败: $e");
        setState(() {
          _status = LynxLoadStatus.failed;
          _errorMessage = e.toString();
          _currentStep = "加载遇到错误";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        extendBody: true,
        extendBodyBehindAppBar: true,
        // 全屏只铺 Lynx；胶囊在窗口层，不跟 PlatformView 一起被 Flutter 换掉。
        body: _buildContent(),
      ),
    );
  }

  bool get _applySafeArea =>
      widget.applySafeArea ?? widget.manifest.applySafeArea;

  Widget _buildContent() {
    switch (_status) {
      case LynxLoadStatus.initial:
      case LynxLoadStatus.downloading:
        return _buildLoadingScreen();

      case LynxLoadStatus.compiling:
      case LynxLoadStatus.success:
        if (_bundlePath == null) return const SizedBox();

        final hostMetrics = LynxHostMetrics.fromMediaQuery(
          MediaQuery.of(context),
          capsuleHasMore: true,
        );
        final applySafeArea = _applySafeArea;
        final combinedInitialData = <String, dynamic>{
          ...?widget.manifest.initialData,
          ...?widget.initialData,
          ...hostMetrics.toInitData(),
          // 过桥后 bool 常变成 1/0，小程序按数字判断，不要用 === true。
          "applySafeArea": applySafeArea ? 1 : 0,
        };

        return LynxView(
          key: ValueKey(_loadGeneration),
          url: _bundlePath!,
          allowedModules: widget.allowedModules,
          initialData: LynxTemplateData(combinedInitialData),
          onLynxCreated: (controller) {
            _log("原生 LynxView 挂载成功 (viewId: ${controller.viewId})");
          },
          onLoadSuccess: () {
            _log("Lynx 模板加载完成，等待真实首屏");
          },
          onFirstScreen: () {
            if (!mounted || _status != LynxLoadStatus.compiling) return;
            setState(() {
              _status = LynxLoadStatus.success;
              _currentStep = "运行中";
            });
            _log("Lynx 原生首屏已呈现");
          },
          onLoadFail: (err) {
            _log("Lynx 渲染错误: $err");
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
                const Icon(Icons.error_outline,
                    size: 56, color: Colors.redAccent),
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

  Widget _buildLoadingScreen() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.manifest.name,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _downloadProgress > 0 ? _downloadProgress : null,
                  minHeight: 4,
                  backgroundColor: Colors.grey.shade200,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Color(0xFF1677FF)),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _currentStep,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
