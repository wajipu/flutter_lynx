import "package:flutter/foundation.dart";
import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter/services.dart";
import "lynx_controller.dart";
import "../models/lynx_template_data.dart";
import "../runtime/lynx_desktop_runtime_view.dart";

typedef LynxCreatedCallback = void Function(LynxController controller);
typedef LynxLoadSuccessCallback = void Function();
typedef LynxLoadFailCallback = void Function(String error);
typedef LynxFirstScreenCallback = void Function();

/// Flutter widget embedding the native LynxView rendering engine.
class LynxView extends StatefulWidget {
  /// The bundle URL (remote https://, local file://, or asset://).
  final String url;

  /// Optional initial data to pass to the Lynx template.
  final LynxTemplateData? initialData;

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

  Map<String, dynamic> _buildCreationParams() {
    return {
      "url": widget.url,
      if (widget.initialData != null) "initialData": widget.initialData!.toMap(),
    };
  }

  void _onPlatformViewCreated(int id) {
    final controller = LynxController(id);
    _controller = controller;
    widget.onLynxCreated?.call(controller);

    // Register callback channel from native view
    final eventChannel = MethodChannel("com.kmanager.flutter_lynx/lynx_view_${id}_events");
    eventChannel.setMethodCallHandler((call) async {
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
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return PlatformViewLink(
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
            ..addOnPlatformViewCreatedListener(_onPlatformViewCreated)
            ..create();
        },
      );
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: _viewType,
        creationParams: _buildCreationParams(),
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
      );
    } else {
      // Dynamic desktop & simulator Lynx runtime renderer (macOS, Windows, Linux, Web)
      return LynxDesktopRuntimeView(
        url: widget.url,
        initialData: widget.initialData,
        onLynxCreated: widget.onLynxCreated,
        onLoadSuccess: widget.onLoadSuccess,
        onLoadFail: widget.onLoadFail,
        onFirstScreen: widget.onFirstScreen,
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}
