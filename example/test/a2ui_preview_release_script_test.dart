import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_lynx_example/a2ui_card_preview.dart';
import 'package:flutter_test/flutter_test.dart';

/// 验证 `npm run a2ui:preview` 产出的 spec 能被客户端加载器真正消费。
///
/// 这个测试把 release-a2ui.mjs 生成的 card-spec.json 形状当作契约输入，
/// 防止发布侧与客户端各自演进后对不上。
void main() {
  late HttpServer server;
  late String base;
  late Map<String, List<int>> routes;

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
  String tempDir() => Directory.systemTemp.createTempSync('preview-spec').path;

  /// 与 release-a2ui.mjs preview 分支写出的 spec 完全同构。
  Map<String, dynamic> releaseSpecShape({
    required String version,
    required String kind,
    required List<int> bundle,
    required List<int> messages,
    String? title,
  }) {
    String md5Hex(List<int> b) => md5.convert(b).toString();
    return {
      'version': version,
      if (title != null) 'title': title,
      'kind': kind,
      'bundle': {
        'url': '$base/$version/a2ui-card.lynx.bundle',
        'md5': md5Hex(bundle),
      },
      'messages': {
        'url': '$base/$version/$kind-card-messages.json',
        'md5': md5Hex(messages),
      },
    };
  }

  test('release 产出的 spec（无 title）可被加载', () async {
    final bundleBytes = File('assets/miniapp/a2ui-card.lynx.bundle').readAsBytesSync();
    final messagesBytes =
        File('assets/a2ui/confirm-card-messages.json').readAsBytesSync();
    const version = 'preview-ee1d443-202610170643';

    serve(
      '/preview/$version/card-spec.json',
      utf8.encode(jsonEncode(releaseSpecShape(
        version: version,
        kind: 'confirm',
        bundle: bundleBytes,
        messages: messagesBytes,
      ))),
    );
    serve('/preview/$version/a2ui-card.lynx.bundle', bundleBytes);
    serve('/preview/$version/confirm-card-messages.json', messagesBytes);

    final result = await A2uiCardPreviewLoader().load(
      specUrl: '$base/$version/card-spec.json',
      allowlist: ['$base/'],
      cacheDirectory: tempDir(),
      allowHttp: true,
    );
    expect(result.version, version);
    expect(result.kind, 'confirm');
    expect(result.bundleBytes.length, bundleBytes.length);
    expect(result.messages.length, 2);
  });

  test('release 产出的 spec（含 title）可被加载且 title 生效', () async {
    final bundleBytes = File('assets/miniapp/a2ui-card.lynx.bundle').readAsBytesSync();
    final messagesBytes =
        File('assets/a2ui/display-card-messages.json').readAsBytesSync();
    const version = 'preview-with-title';

    serve(
      '/preview/$version/card-spec.json',
      utf8.encode(jsonEncode(releaseSpecShape(
        version: version,
        kind: 'display',
        bundle: bundleBytes,
        messages: messagesBytes,
        title: '展示卡预览',
      ))),
    );
    serve('/preview/$version/a2ui-card.lynx.bundle', bundleBytes);
    serve('/preview/$version/display-card-messages.json', messagesBytes);

    final result = await A2uiCardPreviewLoader().load(
      specUrl: '$base/$version/card-spec.json',
      allowlist: ['$base/'],
      cacheDirectory: tempDir(),
      allowHttp: true,
    );
    expect(result.title, '展示卡预览');
    expect(result.kind, 'display');
  });

  test('二维码 URL 里的 spec 参数可被 scheme 解析还原', () {
    final specUrl = 'https://stub.example.com/preview-cards/preview/preview-abc/card-spec.json';
    final uri = 'koklam://card?spec=${Uri.encodeComponent(specUrl)}';
    expect(A2uiCardPreviewLoader.parseSpecUrl(uri), specUrl);
  });
}