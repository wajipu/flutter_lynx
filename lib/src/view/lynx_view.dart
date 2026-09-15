import "package:flutter/foundation.dart";
import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter/services.dart";
import "lynx_controller.dart";
import "../models/lynx_template_data.dart";

typedef LynxCreatedCallback = void Function(LynxController controller);
typedef LynxLoadSuccessCallback = void Function();
typedef LynxLoadFailCallback = void Function(String error);
typedef LynxFirstScreenCallback = void Function();

/// Flutter widget embedding the native LynxView rendering engine.
class LynxView extends StatefulWidget {
  /// 已准备的本地包路径或file URI；远端/asset先交给包管理器准备。
  final String url;

  /// Optional initial data to pass to the Lynx template.
  final LynxTemplateData? initialData;

  /// Android / iOS JSBridge modules granted to this native view, matched exactly.
  /// Custom modules must be listed explicitly; changing grants recreates the view.
  final Set<String> allowedModules;

  /// Callback when the LynxController is created and attached.
  final LynxCreatedCallback? onLynxCreated;

  /// Callback when the Lynx template finishes loading successfully.
  final LynxLoadSuccessCallback? onLoadSuccess;

  /// Callback when the Lynx template fails to load.
  final LynxLoadFailCallback? onLoadFail;

  /// Callback when the first screen of the Lynx template is rendered.
  final LynxFirstScreenCallback? onFirstScreen;

  const LynxView({
    super.key,
    required this.url,
    this.initialData,
    this.allowedModules = const {
      "system",
      "ui",
      "storage",
      "router",
      "default"
    },
    this.onLynxCreated,
    this.onLoadSuccess,
    this.onLoadFail,
    this.onFirstScreen,
  });

  @override
  State<LynxView> createState() => _LynxViewState();
}

class _LynxViewState extends State<LynxView> {
  static const String _viewType = "com.kmanager.flutter_lynx/lynx_view";
  LynxController? _controller;
  MethodChannel? _eventChannel;
  late Set<String> _allowedModules;
  int _platformGeneration = 0;

  @override
  void initState() {
    super.initState();
    _allowedModules = Set.of(widget.allowedModules);
  }

  Map<String, dynamic> _buildCreationParams() {
    return {
      "url": widget.url,
      "allowedModules": _allowedModules.toList(growable: false),
      if (widget.initialData != null)
        "initialData": widget.initialData!.toMap(),
    };
  }

  Future<void> _onPlatformViewCreated(int id, int generation) async {
    if (!mounted || generation != _platformGeneration) return;
    final controller = LynxController(id);
    _controller = controller;

    // 先安装监听再通知原生开始加载，避免快速首屏回调丢失。
    final eventChannel =
        MethodChannel("com.kmanager.flutter_lynx/lynx_view_${id}_events");
    _eventChannel = eventChannel;
    eventChannel.setMethodCallHandler((call) async {
      if (!mounted || !identical(_controller, controller)) return;
      switch (call.method) {
        case "onLoadSuccess":
          widget.onLoadSuccess?.call();
          break;
        case "onLoadFail":
          final error = call.arguments?.toString() ?? "Unknown error";
          widget.onLoadFail?.call(error);
          break;
        case "onFirstScreen":
          widget.onFirstScreen?.call();
          break;
      }
    });
    widget.onLynxCreated?.call(controller);
    if (_hasOfficialLynxEngine) {
      await _reload(controller);
    }
  }

  bool get _hasOfficialLynxEngine =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _reload(LynxController controller) async {
    try {
      await controller.reload(
        newUrl: widget.url,
        newInitialData: widget.initialData?.toMap() ?? {},
      );
    } catch (error) {
      if (mounted && identical(_controller, controller)) {
        widget.onLoadFail?.call(error.toString());
      }
    }
  }

  @override
  void didUpdateWidget(covariant LynxView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Grants belong to a native view's lifetime; never reuse a broader old binding.
    if (!setEquals(widget.allowedModules, _allowedModules)) {
      _allowedModules = Set.of(widget.allowedModules);
      _platformGeneration += 1;
      _detachController();
      return;
    }
    // initialData只用于首次加载；运行时数据更新由控制器显式执行。
    if (widget.url != oldWidget.url &&
        _controller != null &&
        _hasOfficialLynxEngine) {
      _reload(_controller!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final generation = _platformGeneration;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return PlatformViewLink(
        key: ValueKey(generation),
        viewType: _viewType,
        surfaceFactory: (context, controller) {
          return AndroidViewSurface(
            controller: controller as AndroidViewController,
            gestureRecognizers: const <Factory<OneSequenceGestureRecognizer>>{},
            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
          );
        },
        onCreatePlatformView: (params) {
          return PlatformViewsService.initSurfaceAndroidView(
            id: params.id,
            viewType: _viewType,
            layoutDirection: TextDirection.ltr,
            creationParams: _buildCreationParams(),
            creationParamsCodec: const StandardMessageCodec(),
            onFocus: () {
              params.onFocusChanged(true);
            },
          )
            ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
            ..addOnPlatformViewCreatedListener(
                (id) => _onPlatformViewCreated(id, generation))
            ..create();
        },
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        key: ValueKey(generation),
        viewType: _viewType,
        creationParams: _buildCreationParams(),
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (id) => _onPlatformViewCreated(id, generation),
      );
    } else {
      return _UnsupportedOfficialLynxRuntime(
        onLoadFail: widget.onLoadFail,
      );
    }
  }

  @override
  void dispose() {
    _detachController();
    super.dispose();
  }

  void _detachController() {
    _eventChannel?.setMethodCallHandler(null);
    _eventChannel = null;
    _controller?.dispose();
    _controller = null;
  }
}

/// Official Lynx 3.2 only ships Android and iOS engines. Desktop support starts at 3.7.
class _UnsupportedOfficialLynxRuntime extends StatefulWidget {
  final LynxLoadFailCallback? onLoadFail;

  const _UnsupportedOfficialLynxRuntime({this.onLoadFail});

  @override
  State<_UnsupportedOfficialLynxRuntime> createState() =>
      _UnsupportedOfficialLynxRuntimeState();
}

class _UnsupportedOfficialLynxRuntimeState
    extends State<_UnsupportedOfficialLynxRuntime> {
  static const String _message =
      "Official Lynx 3.2 has no engine on this platform; desktop support starts at Lynx 3.7";

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.onLoadFail?.call(_message);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand();
  }
}
