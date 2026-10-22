import "dart:convert";
import "dart:io";

import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:flutter_lynx/flutter_lynx.dart";
// 桌面运行时视图未从包入口导出（桌面专用演示件），按深路径引入。
import "package:flutter_lynx/src/runtime/lynx_desktop_runtime_view.dart";

/// 源码直喂加载链路测试：验证 loadFromSource/templateBytes 与既有文件链路
/// 在 Dart 协议层与原生入口上同源一致。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final binding = TestDefaultBinaryMessengerBinding.instance;

  void unrecordViewChannel(int viewId) {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      MethodChannel("io.github.wajipu.flutter_lynx/lynx_view_$viewId"),
      null,
    );
  }

  List<MethodCall> recordViewChannel(int viewId) {
    final calls = <MethodCall>[];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      MethodChannel("io.github.wajipu.flutter_lynx/lynx_view_$viewId"),
      (call) async {
        calls.add(call);
        return true;
      },
    );
    addTearDown(() => unrecordViewChannel(viewId));
    return calls;
  }

  group("LynxController 直喂协议", () {
    test("loadFromSource 走 loadFromSource action 并携带 source/initialData",
        () async {
      final calls = recordViewChannel(4201);

      final controller = LynxController(4201);
      addTearDown(controller.dispose);
      await controller.loadFromSource("inline-template-content",
          initialData: {"title": "确认卡片"});

      expect(calls, hasLength(1));
      expect(calls.single.method, "loadFromSource");
      expect(calls.single.arguments["source"], "inline-template-content");
      expect(calls.single.arguments["initialData"], {"title": "确认卡片"});
    });

    test("loadFromTemplateBytes 与文件链路喂给引擎的字节逐位一致", () async {
      final calls = recordViewChannel(4202);

      // 故意携带非 UTF-8 安全字节（0x00/0xFF），模拟 rspeedy/tasm 二进制模板产物；
      // 文本 String 通道无法无损承载这类内容，只有 bytes 通道可行。
      final templateBytes =
          Uint8List.fromList([...utf8.encode("LYNX_BUNDLE"), 0x00, 0xFF, 0x10]);
      final tempDir = await Directory.systemTemp.createTemp("lynx_parity_");
      addTearDown(() async => tempDir.delete(recursive: true));
      final bundleFile = File("${tempDir.path}/main.lynx.bundle");
      await bundleFile.writeAsBytes(templateBytes);

      // 文件链路的字节来源：原生 reload 正是 readBytes 后直喂引擎。
      final fromFile = await bundleFile.readAsBytes();

      final controller = LynxController(4202);
      addTearDown(controller.dispose);
      await controller.loadFromTemplateBytes(templateBytes);

      expect(calls.single.method, "loadFromSource");
      final inlineBytes = calls.single.arguments["templateBytes"] as Uint8List;
      // 同一份模板产物，两条链路最终到达原生渲染入口的字节完全相同。
      expect(inlineBytes, equals(fromFile));
      expect(inlineBytes, equals(templateBytes));
    });
  });

  group("LynxView 直喂入口", () {
    test("url、source、templateBytes 必须且只能提供一个", () {
      // 非 const 调用，构造期断言在运行时触发。
      expect(() => LynxView(url: "a", source: "b"),
          throwsA(isA<AssertionError>()));
      expect(() => LynxView(url: "a", templateBytes: Uint8List(1)),
          throwsA(isA<AssertionError>()));
      expect(() => LynxView(source: "a", templateBytes: Uint8List(1)),
          throwsA(isA<AssertionError>()));
      expect(() => LynxView(), throwsA(isA<AssertionError>()));
      expect(() => LynxView(url: "a"), returnsNormally);
      expect(() => LynxView(source: "a"), returnsNormally);
      expect(
          () => LynxView(templateBytes: Uint8List.fromList([1])),
          returnsNormally);
    });

    testWidgets("source/templateBytes 与文件路径在创建与重载协议上同源",
        (tester) async {
      final viewCalls = <MethodCall>[];

      // 平台视图创建桩：TLHC 模式 create 响应 textureId(int)，resize 要求
      // 回显 {width, height}，其余消息不应答内容，直接放行。
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        (call) async {
          final args = call.arguments;
          if (call.method == "create") {
            final id = (args as Map)["id"] as int;
            binding.defaultBinaryMessenger.setMockMethodCallHandler(
              MethodChannel("io.github.wajipu.flutter_lynx/lynx_view_$id"),
              (m) async {
                viewCalls.add(m);
                return true;
              },
            );
            addTearDown(() => unrecordViewChannel(id));
            return 1;
          }
          if (call.method == "resize") {
            return {"width": args["width"], "height": args["height"]};
          }
          return null;
        },
      );
      addTearDown(() => binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform_views,
            null,
          ));

      // 同一份模板内容：先落盘走文件链路，再直喂走 source/templateBytes 链路。
      // testWidgets 运行在 FakeAsync zone，dart:io 真实异步 IO 永不完成；
      // 必须用同步 IO 准备夹具（仅测试夹具，被测链路仍是真实协议）。
      const templateContent = " Lynx 确认卡片模板内容（文本）\nline2";
      final templateBytes =
          Uint8List.fromList([...utf8.encode(templateContent), 0x00]);
      final bundleFile = File(
          "${Directory.systemTemp.path}/lynx_view_parity_${DateTime.now().microsecondsSinceEpoch}.lynx.bundle");
      bundleFile.writeAsBytesSync(templateBytes);
      addTearDown(() {
        try {
          bundleFile.deleteSync();
        } catch (_) {}
      });
      final fromFile = bundleFile.readAsBytesSync();

      Future<List<MethodCall>> pumpAndCapture(Widget view) async {
        viewCalls.clear();
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: view)));
        // 不用 pumpAndSettle：测试桩下平台视图会持续调度帧，永不稳定；
        // 协议握手（create -> reload/loadFromSource）是微任务链，固定几拍足够。
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
        return List.of(viewCalls);
      }

      // 1) 既有文件链路（回归基线，保持不变）。
      final fileCalls = await pumpAndCapture(LynxView(url: bundleFile.path));
      expect(fileCalls, isNotEmpty);
      expect(fileCalls.first.method, "reload");
      expect(fileCalls.first.arguments["url"], bundleFile.path);

      // 2) 源码直喂链路：同一内容不再要求先落盘。
      final sourceCalls =
          await pumpAndCapture(LynxView(source: templateContent));
      expect(sourceCalls, isNotEmpty);
      expect(sourceCalls.first.method, "loadFromSource");
      final sourceArg = sourceCalls.first.arguments["source"] as String;
      // 与文件链路终局喂给引擎的内容一致（UTF-8 无损往返，尾部 0x00 为二进制标记位）。
      expect(utf8.encode(sourceArg), templateBytes.sublist(0, templateBytes.length - 1));

      // 3) 二进制模板直喂链路：字节逐位等于文件链路读取结果。
      final bytesCalls =
          await pumpAndCapture(LynxView(templateBytes: templateBytes));
      expect(bytesCalls, isNotEmpty);
      expect(bytesCalls.first.method, "loadFromSource");
      expect(bytesCalls.first.arguments["templateBytes"] as Uint8List,
          equals(fromFile));
    });
  });

  group("LynxDesktopRuntimeView 直喂入口", () {
    testWidgets("source 直喂时不读文件即可完成装载回调", (tester) async {
      var loadSuccess = false;
      var firstScreen = false;

      // 桌面视图内建演示 UI 按桌面宽度排版；测试默认 800x600 配等宽测试字体会
      // 触发与被测逻辑无关的 RenderFlex 溢出，放大视口到桌面尺寸。
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LynxDesktopRuntimeView(
              // 不传 url：直喂模式必须完全绕开文件读取也能完成装载回调。
              source: "inline desktop template",
              onLoadSuccess: () => loadSuccess = true,
              onFirstScreen: () => firstScreen = true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(loadSuccess, isTrue);
      expect(firstScreen, isTrue);
      expect(find.byType(LynxDesktopRuntimeView), findsOneWidget);
    });

    test("url 与 source 必须且只能提供一个", () {
      expect(() => LynxDesktopRuntimeView(url: "a", source: "b"),
          throwsA(isA<AssertionError>()));
      expect(() => LynxDesktopRuntimeView(),
          throwsA(isA<AssertionError>()));
      expect(() => LynxDesktopRuntimeView(url: "a"), returnsNormally);
      expect(() => LynxDesktopRuntimeView(source: "a"), returnsNormally);
    });
  });

  group("真实模板产物直喂对照", () {
    // 复现：先用 lynx_miniapp_template 真实构建产物，再以环境变量传入：
    //   cd lynx_miniapp_template && npm ci
    //   export MINIAPP_BUILD_OUTPUT_DIR="$(mktemp -d /tmp/lynx-template-build.XXXXXX)"
    //   ./node_modules/.bin/rspeedy build --config lynx.upload.config.ts --no-env
    //   LYNX_REAL_BUNDLE="$MINIAPP_BUILD_OUTPUT_DIR/main.lynx.bundle" flutter test
    final realBundlePath = Platform.environment["LYNX_REAL_BUNDLE"];
    final realBundle = realBundlePath == null
        ? null
        : File(realBundlePath);
    final hasRealBundle = realBundle != null && realBundle.existsSync();

    test("真实 tasm 产物经 templateBytes 与文件链路喂给引擎的字节逐位一致",
        () async {
      final realBytes = await realBundle!.readAsBytes();
      // 真实 rspeedy/tasm 产物是二进制模板：无法经 UTF-8 文本无损承载，
      // 必须走 bytes 通道（source 入口只用于文本型模板内容）。
      expect(() => utf8.decode(realBytes), throwsA(isA<FormatException>()));

      final calls = recordViewChannel(4401);
      final controller = LynxController(4401);
      addTearDown(controller.dispose);
      await controller.loadFromTemplateBytes(realBytes);

      expect(calls.single.method, "loadFromSource");
      expect(calls.single.arguments["templateBytes"] as Uint8List, realBytes);
    }, skip: hasRealBundle
        ? false
        : "需 LYNX_REAL_BUNDLE 指向真实构建产物（见组注释的复现命令）");
  });
}
