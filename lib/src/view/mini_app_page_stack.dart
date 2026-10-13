import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// 工作台小程序页面栈容器：native 自治页面栈（LynxNavigator + LynxHolder）。
///
/// Flutter 层只承载原生视图并监听一条单向通知——栈底背滑时关闭容器页；
/// Lynx 内部的页面导航完全在原生层，Dart 不参与。
class MiniAppPageStack extends StatefulWidget {
  final String bundlePath;
  final Map<String, Object?> initialData;
  final List<String> allowedModules;
  /// 宿主关联当前原生视图的来源，独立于模板初始数据和 JS 参数。
  final String? sourceContextId;
  final VoidCallback? onStackBottomBack;

  const MiniAppPageStack({
    super.key,
    required this.bundlePath,
    required this.initialData,
    required this.allowedModules,
    this.sourceContextId,
    this.onStackBottomBack,
  });

  @override
  State<MiniAppPageStack> createState() => _MiniAppPageStackState();
}

class _MiniAppPageStackState extends State<MiniAppPageStack> {
  static const String _viewType = "com.kmanager.flutter_lynx/mini_app_page_stack";

  MethodChannel? _stackChannel;

  @override
  void didUpdateWidget(covariant MiniAppPageStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceContextId != widget.sourceContextId) {
      _stackChannel?.setMethodCallHandler(null);
      _stackChannel = null;
      return;
    }
    if (!mapEquals(oldWidget.initialData, widget.initialData)) {
      _updateNativeData();
    }
  }

  void _updateNativeData() {
    final channel = _stackChannel;
    if (channel != null) {
      unawaited(channel.invokeMethod<bool>('updateData', widget.initialData));
    }
  }

  @override
  void dispose() {
    _stackChannel?.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final sourceContextId = widget.sourceContextId;
      return UiKitView(
        key: ValueKey(widget.sourceContextId),
        viewType: _viewType,
        creationParams: _buildCreationParams(),
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (id) {
          if (sourceContextId == widget.sourceContextId) {
            _onPlatformViewCreated(id);
          }
        },
        hitTestBehavior: PlatformViewHitTestBehavior.opaque,
      );
    }
    return const SizedBox.shrink();
  }

  Map<String, Object?> _buildCreationParams() => <String, Object?>{
        'bundlePath': widget.bundlePath,
        'initialData': widget.initialData,
        'allowedModules': widget.allowedModules,
        'sourceContextId': widget.sourceContextId,
        'applySafeArea': true,
      };

  void _onPlatformViewCreated(int id) {
    _stackChannel?.setMethodCallHandler(null);
    final channel = MethodChannel("com.kmanager.flutter_lynx/page_stack_$id");
    channel.setMethodCallHandler((call) async {
      if (call.method == 'dismiss') {
        widget.onStackBottomBack?.call();
      }
      return null;
    });
    _stackChannel = channel;
    _updateNativeData();
  }
}
