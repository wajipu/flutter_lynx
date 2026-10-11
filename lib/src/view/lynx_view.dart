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

/// Host scrollables and tap wrappers must not win the arena over Lynx.
Set<Factory<OneSequenceGestureRecognizer>> lynxPlatformViewGestures() {
  return <Factory<OneSequenceGestureRecognizer>>{
    Factory<EagerGestureRecognizer>(EagerGestureRecognizer.new),
  };
}

/// Flutter widget embedding the native LynxView rendering engine.
class LynxView extends StatefulWidget {
  /// 已准备的本地包路径或file URI；远端/asset先交给包管理器准备。
  ///
  /// 与 [source] 二选一；既有小程序文件链路继续用它，语义不变。
  final String? url;

  /// 模板内容直喂入口（UTF-8 文本），不经本地 bundle 文件与缓存链路。
  ///
  /// 对齐官方 `LynxView.loadTemplate`：原生把内容按 UTF-8 编成 bytes 直喂引擎，
  /// 渲染入口与文件链路相同。内容必须是引擎可执行的模板产物（如随 App 版本内置的
  /// 编译产物文本）。
  final String? source;

  /// 模板 bytes 直喂入口，语义同 [source]。
  ///
  /// rspeedy/tasm 编译出的 `main.lynx.bundle` 是二进制模板，不经 UTF-8 无损转换，
  /// 这类内容必须走本入口。[url]、[source]、[templateBytes] 必须且只能提供一个。
  final Uint8List? templateBytes;

  /// 内容自适应高度（仅 iOS 生效）：原生按模板内容高回传 [onHeightChanged]，
  /// 由宿主调整容器高度；Android 引擎无对等公开 API，保持固定高容器。
  ///
  /// 注意 PlatformView 的高度始终由 Flutter 容器决定，"自适应"是
  /// 原生把内容高报给 Dart 后宿主主动改容器，不是原生自己变高。
  final bool autoHeight;

  /// [autoHeight] 开启时，原生测得的内容高度回调（逻辑像素）。
  final ValueChanged<double>? onHeightChanged;

  /// Overrides native-view gesture arbitration; null keeps eager ownership.
  /// An empty set lets parent scrollables claim drags while native still receives
  /// touch sequences that no competing recognizer claims.
  ///
  /// 空集合让父滚动参与手势竞争，无竞争的触摸仍交给原生；null 保持原策略，
  /// 需要原生内部滚动的卡片可沿用默认值。
  final Set<Factory<OneSequenceGestureRecognizer>>? gestureRecognizers;

  /// Optional initial data to pass to the Lynx template.
  final LynxTemplateData? initialData;

  /// Android / iOS JSBridge modules granted to this native view, matched exactly.
  /// Custom modules must be listed explicitly; changing grants recreates the view.
  final Set<String> allowedModules;

  /// Host-owned native-view origin; never exposed through template initial data.
  final String? sourceContextId;

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
    this.url,
    this.source,
    this.templateBytes,
    this.autoHeight = false,
    this.onHeightChanged,
    this.gestureRecognizers,
    this.initialData,
    this.sourceContextId,
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
  }) : assert(
          (url != null ? 1 : 0) +
                  (source != null ? 1 : 0) +
                  (templateBytes != null ? 1 : 0) ==
              1,
          "url、source、templateBytes 必须且只能提供一个：文件链路用 url，源码直喂用 source，二进制模板产物直喂用 templateBytes");

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
      if (widget.url != null) "url": widget.url,
      if (widget.source != null) "source": widget.source,
      if (widget.templateBytes != null) "templateBytes": widget.templateBytes,
      "autoHeight": widget.autoHeight,
      "allowedModules": _allowedModules.toList(growable: false),
      "sourceContextId": widget.sourceContextId,
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
        case "onHeightChanged":
          final height = (call.arguments as num?)?.toDouble();
          if (height != null && height > 0) {
            widget.onHeightChanged?.call(height);
          }
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
      // 三种入口在原生侧最终走同一个 bytes 直喂渲染入口，只是取数方式不同。
      final initialData = widget.initialData?.toMap() ?? {};
      if (widget.source != null) {
        await controller.loadFromSource(widget.source!, initialData: initialData);
      } else if (widget.templateBytes != null) {
        await controller.loadFromTemplateBytes(
            widget.templateBytes!, initialData: initialData);
      } else {
        await controller.reload(
          newUrl: widget.url,
          newInitialData: initialData,
        );
      }
    } catch (error) {
      if (mounted && identical(_controller, controller)) {
        widget.onLoadFail?.call(error.toString());
      }
    }
  }

  @override
  void didUpdateWidget(covariant LynxView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Grants and origin belong to a native view's lifetime; recreate when either changes.
    if (!setEquals(widget.allowedModules, _allowedModules) ||
        widget.sourceContextId != oldWidget.sourceContextId) {
      _allowedModules = Set.of(widget.allowedModules);
      _platformGeneration += 1;
      _detachController();
      return;
    }
    // initialData只用于首次加载；运行时数据更新由控制器显式执行。
    if ((widget.url != oldWidget.url ||
            widget.source != oldWidget.source ||
            widget.templateBytes != oldWidget.templateBytes) &&
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
            gestureRecognizers:
                widget.gestureRecognizers ?? lynxPlatformViewGestures(),
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
        gestureRecognizers:
            widget.gestureRecognizers ?? lynxPlatformViewGestures(),
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
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

/// Official Flutter embedding only covers Android and iOS. Desktop is a CMake SDK, not this plugin.
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
      "Official Lynx 4.1.0 is not embedded on this Flutter platform; desktop uses a separate CMake SDK";

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
