// Android原生运行时手动验收入口，不连接业务服务或替代真实小程序页面。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_lynx/flutter_lynx.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1677FF)),
      useMaterial3: true,
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1677FF),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    themeMode: ThemeMode.system,
    home: const RuntimeVerificationPage(),
  ));
}

/// A/B包使用同一个PlatformView；界面正文与计数逻辑位于编译后的TSX中。
class RuntimeVerificationPage extends StatefulWidget {
  const RuntimeVerificationPage({super.key});

  @override
  State<RuntimeVerificationPage> createState() =>
      _RuntimeVerificationPageState();
}

class _RuntimeVerificationPageState extends State<RuntimeVerificationPage> {
  final _bridge = LynxBridge.instance;
  final _run = DateTime.now().microsecondsSinceEpoch.toString();
  LynxController? _controller;
  String? _path;
  String _status = 'Preparing';
  int _generation = 0;
  int _bridgeCalls = 0;
  int _loads = 0;
  int _screens = 0;
  int _errors = 0;
  int _sentEvents = 0;

  @override
  void initState() {
    super.initState();
    // 只统计真实内置系统能力的调用，不返回模拟设备信息。
    _bridge.register('getSystemInfo', (params) async {
      final response = await _bridge.systemHandler.handle(LynxBridgeRequest(
        callId: 'runtime-verification',
        module: 'system',
        method: 'getSystemInfo',
        params: params,
      ));
      if (mounted) setState(() => _bridgeCalls += 1);
      debugPrint('LYNX_VERIFY bridge=$_bridgeCalls data=${response.data}');
      return response.data;
    }, module: 'system');
    _load('a');
  }

  Future<void> _load(String variant) async {
    final generation = ++_generation;
    setState(() => _status = 'Loading $variant');
    try {
      final manager = LynxMiniProgramManager.instance;
      final String bundlePath;
      if (variant == 'bad') {
        final directory = await manager.getMiniProgramDirectory(
            'runtime_verification_bad', _run);
        final file = File('$directory/invalid.lynx.bundle');
        await file.parent.create(recursive: true);
        await file.writeAsString('{"invalid":"not a Lynx binary"}');
        bundlePath = file.path;
      } else {
        bundlePath = await manager.prepareBundle(MiniProgramManifest(
          appId: 'runtime_verification_$variant',
          name: 'Runtime $variant',
          version: _run,
          bundleUrl: 'assets/miniapp/runtime-$variant.lynx.bundle',
        ));
      }
      if (!mounted || generation != _generation) return;
      // URL变化触发已有控制器reload，viewId应保持不变。
      if (_path == bundlePath) {
        await _controller?.reload(newUrl: bundlePath);
      } else {
        setState(() => _path = bundlePath);
      }
    } catch (error) {
      if (mounted && generation == _generation) _failed(error.toString());
    }
  }

  void _failed(String error) {
    if (!mounted) return;
    setState(() {
      _errors += 1;
      _status = 'FAILED: $error';
    });
    debugPrint('LYNX_VERIFY failure=$_errors error=$error');
  }

  Future<void> _sendEvent() async {
    if (_controller == null) return;
    try {
      final count = _sentEvents + 1;
      await _controller!.sendCustomEvent('host-ping', {'count': count});
      if (mounted) setState(() => _sentEvents = count);
      debugPrint('LYNX_VERIFY host-ping=$count view=${_controller!.viewId}');
    } catch (error) {
      _failed(error.toString());
    }
  }

  /// 验证标准容器的真实首屏回调能移除加载遮罩，而不只验证裸LynxView。
  void _openContainer() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => LynxMiniProgramPage(
          manifest: MiniProgramManifest(
        appId: 'runtime_verification_container',
        name: 'Standard Lynx container',
        version: _run,
        bundleUrl: 'assets/miniapp/runtime-a.lynx.bundle',
      )),
    ));
  }

  @override
  void dispose() {
    _generation += 1;
    _bridge.unregister('getSystemInfo', module: 'system');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lynx native runtime verification')),
      body: Column(children: [
        Wrap(spacing: 12, children: [
          ElevatedButton(
              onPressed: () => _load('a'), child: const Text('Load A')),
          ElevatedButton(
              onPressed: () => _load('b'), child: const Text('Load B')),
          ElevatedButton(onPressed: _sendEvent, child: const Text('Host ping')),
          ElevatedButton(
              onPressed: () => _load('bad'), child: const Text('Bad bundle')),
          ElevatedButton(
              onPressed: _openContainer, child: const Text('Open container')),
        ]),
        Text('view=${_controller?.viewId} loads=$_loads screens=$_screens '
            'bridge=$_bridgeCalls host=$_sentEvents errors=$_errors'),
        Text(_status, maxLines: 2, overflow: TextOverflow.ellipsis),
        const Divider(),
        Expanded(
            child: _path == null
                ? const SizedBox()
                : LynxView(
                    url: _path!,
                    allowedModules: const {'system'},
                    onLynxCreated: (controller) {
                      setState(() => _controller = controller);
                      debugPrint('LYNX_VERIFY created=${controller.viewId}');
                    },
                    onLoadSuccess: () {
                      setState(() => _loads += 1);
                      debugPrint(
                          'LYNX_VERIFY load=$_loads view=${_controller?.viewId}');
                    },
                    onFirstScreen: () {
                      setState(() {
                        _screens += 1;
                        _status = 'Native first screen';
                      });
                      debugPrint(
                          'LYNX_VERIFY screen=$_screens view=${_controller?.viewId}');
                    },
                    onLoadFail: _failed,
                  )),
      ]),
    );
  }
}
