import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_lynx_example/a2ui_card_preview.dart';
import 'package:flutter_test/flutter_test.dart';

/// 用真实产物（example/assets 下的 bundle 与 messages）验证整条链路。
///
/// 与 [a2ui_card_preview_test.dart] 的区别：那边用假字节验证校验与拒绝分支，
/// 这里用真 bundle 真 messages 验证 md5 校验、大小上限与消息形状能真实通过。
void main() {
  late HttpServer server;
  late String base;
  late Map<String, List<int>> routes;

  final bundleBytes =
      File('assets/miniapp/a2ui-card.lynx.bundle').readAsBytesSync();
  final confirmBytes =
      File('assets/a2ui/confirm-card-messages.json').readAsBytesSync();
  final displayBytes =
      File('assets/a2ui/display-card-messages.json').readAsBytesSync();

  setUp(() async {
    routes = {};
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}/preview';
    server.listen((req) async {
      final body = routes[req.uri.path];
      if (body == null) {
        req.response.statusCode = 404;
      } else {
        req.response.add(body);
      }
      await req.response.close();
    });
  });

  tearDown(() async => server.close(force: true));

  void serve(String path, List<int> bytes) => routes[path] = bytes;
  String md5Hex(List<int> b) => md5.convert(b).toString();
  String tempDir() => Directory.systemTemp.createTempSync('preview-real').path;

  String specJson({
    required String version,
    required String kind,
    required List<int> bundle,
    required List<int> messages,
  }) =>
      jsonEncode({
        'version': version,
        'kind': kind,
        'bundle': {'url': '$base/b', 'md5': md5Hex(bundle)},
        'messages': {'url': '$base/m', 'md5': md5Hex(messages)},
      });

  test('真实确认卡产物走通并命中缓存', () async {
    final cacheDir = tempDir();
    serve('/preview/spec.json', utf8.encode(specJson(
      version: 'real-confirm',
      kind: 'confirm',
      bundle: bundleBytes,
      messages: confirmBytes,
    )));
    serve('/preview/b', bundleBytes);
    serve('/preview/m', confirmBytes);

    final loader = A2uiCardPreviewLoader();
    final first = await loader.load(
      specUrl: '$base/spec.json',
      allowlist: ['$base/'],
      cacheDirectory: cacheDir,
      allowHttp: true,
    );

    // 真实 bundle 约 1MB，md5 与字节数都应与源文件一致
    expect(first.bundleBytes.length, bundleBytes.length);
    expect(md5Hex(first.bundleBytes), md5Hex(bundleBytes));
    expect(first.kind, 'confirm');
    expect(first.bundleSource, A2uiCardPreviewSource.network);

    // 真实 messages 是 v0.9 协议数组：createSurface + updateComponents
    expect(first.messages.length, 2);
    expect(first.messages.first, containsPair('createSurface', isA<Map<String, dynamic>>()));
    expect(first.messages.last, containsPair('updateComponents', isA<Object>()));

    // 二次加载应全部命中缓存（断开产物路由后仍能成功）
    routes.remove('/preview/b');
    routes.remove('/preview/m');
    final second = await loader.load(
      specUrl: '$base/spec.json',
      allowlist: ['$base/'],
      cacheDirectory: cacheDir,
      allowHttp: true,
    );
    expect(second.bundleSource, A2uiCardPreviewSource.cache);
    expect(second.messagesSource, A2uiCardPreviewSource.cache);
    expect(second.messages.length, first.messages.length);
  });

  test('真实展示卡产物走通（display 命名空间）', () async {
    final cacheDir = tempDir();
    serve('/preview/spec.json', utf8.encode(specJson(
      version: 'real-display',
      kind: 'display',
      bundle: bundleBytes,
      messages: displayBytes,
    )));
    serve('/preview/b', bundleBytes);
    serve('/preview/m', displayBytes);

    final result = await A2uiCardPreviewLoader().load(
      specUrl: '$base/spec.json',
      allowlist: ['$base/'],
      cacheDirectory: cacheDir,
      allowHttp: true,
    );
    expect(result.kind, 'display');
    expect(result.messages.length, jsonDecode(utf8.decode(displayBytes)).length);
  });

  test('真实 bundle 超过 10 MiB 时被拒（用填充字节构造超限产物）', () async {
    final cacheDir = tempDir();
    // 真实 bundle 约 1MB；构造 10 MiB + 1 的产物触发上限分支
    final oversized = List<int>.filled(A2uiCardPreviewLoader.maxBytes + 1, 0);
    serve('/preview/spec.json', utf8.encode(specJson(
      version: 'oversized',
      kind: 'confirm',
      bundle: oversized,
      messages: confirmBytes,
    )));
    serve('/preview/b', oversized);
    serve('/preview/m', confirmBytes);

    await expectLater(
      A2uiCardPreviewLoader().load(
        specUrl: '$base/spec.json',
        allowlist: ['$base/'],
        cacheDirectory: cacheDir,
        allowHttp: true,
      ),
      throwsA(isA<A2uiPreviewException>()
          .having((e) => e.message, 'message', contains('超出上限'))),
    );
  });

  test('messages 被篡改一字节即拒绝', () async {
    final cacheDir = tempDir();
    // spec 仍声明原始 md5，传输内容被改一字节——模拟传输损坏或内容被替换
    final tampered = List<int>.from(confirmBytes)..[10] ^= 0xFF;
    serve('/preview/spec.json', utf8.encode(jsonEncode({
      'version': 'tampered',
      'kind': 'confirm',
      'bundle': {'url': '$base/b', 'md5': md5Hex(bundleBytes)},
      'messages': {'url': '$base/m', 'md5': md5Hex(confirmBytes)},
    })));
    serve('/preview/b', bundleBytes);
    serve('/preview/m', tampered);

    await expectLater(
      A2uiCardPreviewLoader().load(
        specUrl: '$base/spec.json',
        allowlist: ['$base/'],
        cacheDirectory: cacheDir,
        allowHttp: true,
      ),
      throwsA(isA<A2uiPreviewException>()
          .having((e) => e.message, 'message', contains('MD5 不匹配'))),
    );
  });
}