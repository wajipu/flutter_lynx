import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_lynx_example/a2ui_card_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('scheme 解析', () {
    test('取出 spec 参数', () {
      expect(
        A2uiCardPreviewLoader.parseSpecUrl(
            'koklam://card?spec=https%3A%2F%2Fexample.com%2Fa.json'),
        'https://example.com/a.json',
      );
    });

    test('拒绝错误 scheme / host / 空 spec', () {
      expect(A2uiCardPreviewLoader.parseSpecUrl('koklam:://card?spec=x'), isNull);
      expect(A2uiCardPreviewLoader.parseSpecUrl('koklam://other?spec=x'), isNull);
      expect(A2uiCardPreviewLoader.parseSpecUrl('koklam://card'), isNull);
      expect(A2uiCardPreviewLoader.parseSpecUrl('koklam://card?spec='), isNull);
      expect(A2uiCardPreviewLoader.parseSpecUrl('不是 URI'), isNull);
    });
  });

  group('白名单判定', () {
    const allow = ['https://cdn.example.com/preview/'];

    test('放行白名单内地址', () {
      expect(
        A2uiCardPreviewLoader.isAllowed(
            'https://cdn.example.com/preview/a.json', allow),
        isTrue,
      );
    });

    test('拒绝域名不同 / 路径越界 / http / 空白名单', () {
      expect(
        A2uiCardPreviewLoader.isAllowed(
            'https://evil.com/preview/a.json', allow),
        isFalse,
      );
      expect(
        A2uiCardPreviewLoader.isAllowed(
            'https://cdn.example.com/other/a.json', allow),
        isFalse,
      );
      expect(
        A2uiCardPreviewLoader.isAllowed(
            'http://cdn.example.com/preview/a.json', allow),
        isFalse,
      );
      expect(
        A2uiCardPreviewLoader.isAllowed('https://cdn.example.com/x', const []),
        isFalse,
      );
    });

    test('http 仅在 debug 开关下放行', () {
      expect(
        A2uiCardPreviewLoader.isAllowed(
            'http://127.0.0.1:8000/preview/a.json',
            const ['http://127.0.0.1:8000/preview/'],
            allowHttp: true,
          ),
        isTrue,
      );
      // 即使开关放行 http，https 白名单也不该匹配 http 地址
      expect(
        A2uiCardPreviewLoader.isAllowed(
          'http://127.0.0.1:8000/preview/a.json',
          const ['https://127.0.0.1:8000/preview/'],
          allowHttp: true,
        ),
        isFalse,
      );
    });

    test('白名单项不以斜杠结尾也能前缀匹配', () {
      expect(
        A2uiCardPreviewLoader.isAllowed(
            'https://cdn.example.com/preview/a.json',
            const ['https://cdn.example.com/preview']),
        isTrue,
      );
    });
  });

  group('spec 解析', () {
    test('完整 spec', () {
      final spec = A2uiCardSpec.tryParse(jsonEncode({
        'version': 'v1',
        'title': '预览',
        'kind': 'display',
        'bundle': {
          'url': 'https://x/b.lynx.bundle',
          'md5': 'a' * 32,
        },
        'messages': {
          'url': 'https://x/m.json',
          'md5': 'b' * 32,
        },
      }));
      expect(spec, isNotNull);
      expect(spec!.version, 'v1');
      expect(spec.title, '预览');
      expect(spec.kind, 'display');
    });

    test('kind 缺失按 confirm 处理', () {
      final spec = A2uiCardSpec.tryParse(jsonEncode({
        'version': 'v1',
        'bundle': {'url': 'https://x/b', 'md5': 'a' * 32},
        'messages': {'url': 'https://x/m', 'md5': 'b' * 32},
      }));
      expect(spec!.kind, 'confirm');
    });

    test('md5 缺失或长度不对一律拒绝，不降级放行', () {
      expect(
        A2uiCardSpec.tryParse(jsonEncode({
          'version': 'v1',
          'bundle': {'url': 'https://x/b'},
          'messages': {'url': 'https://x/m', 'md5': 'b' * 32},
        })),
        isNull,
      );
      expect(
        A2uiCardSpec.tryParse(jsonEncode({
          'version': 'v1',
          'bundle': {'url': 'https://x/b', 'md5': 'abc'},
          'messages': {'url': 'https://x/m', 'md5': 'b' * 32},
        })),
        isNull,
      );
      // 大写 hex 同样拒绝
      expect(
        A2uiCardSpec.tryParse(jsonEncode({
          'version': 'v1',
          'bundle': {'url': 'https://x/b', 'md5': 'A' * 32},
          'messages': {'url': 'https://x/m', 'md5': 'b' * 32},
        })),
        isNull,
      );
    });

    test('未知 kind 拒绝', () {
      expect(
        A2uiCardSpec.tryParse(jsonEncode({
          'version': 'v1',
          'kind': 'whatever',
          'bundle': {'url': 'https://x/b', 'md5': 'a' * 32},
          'messages': {'url': 'https://x/m', 'md5': 'b' * 32},
        })),
        isNull,
      );
    });

    test('非法 JSON / 非对象 / 缺 version 拒绝', () {
      expect(A2uiCardSpec.tryParse('not json'), isNull);
      expect(A2uiCardSpec.tryParse('[1,2]'), isNull);
      expect(
        A2uiCardSpec.tryParse(jsonEncode({
          'bundle': {'url': 'https://x/b', 'md5': 'a' * 32},
          'messages': {'url': 'https://x/m', 'md5': 'b' * 32},
        })),
        isNull,
      );
    });
  });

  group('端到端装载', () {
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

    String tempDir() => Directory.systemTemp.createTempSync('preview-test').path;

    test('spec 在白名单外时不发起任何下载', () async {
      final loader = A2uiCardPreviewLoader();
      await expectLater(
        loader.load(
          specUrl: '$base/spec.json',
          allowlist: const ['https://other.example.com/'],
          cacheDirectory: tempDir(),
        ),
        throwsA(isA<A2uiPreviewException>()
            .having((e) => e.message, 'message', contains('域名不在允许范围'))),
      );
      // 白名单外时不应留下任何请求痕迹
      expect(routes.containsKey('/preview/spec.json'), isFalse);
    });

    test('产物地址越出白名单时被拒绝', () async {
      serve('/preview/spec.json', utf8.encode(jsonEncode({
        'version': 'v1',
        'bundle': {'url': 'https://evil.com/b', 'md5': 'a' * 32},
        'messages': {'url': '$base/m.json', 'md5': 'b' * 32},
      })));
      final loader = A2uiCardPreviewLoader();
      await expectLater(
        loader.load(
          specUrl: '$base/spec.json',
          allowlist: ['$base/'],
          cacheDirectory: tempDir(),
          allowHttp: true,
        ),
        throwsA(isA<A2uiPreviewException>()
            .having((e) => e.message, 'message', contains('https://evil.com/b'))),
      );
    });

    test('MD5 不匹配时拒绝加载', () async {
      final payload = utf8.encode('bundle-bytes');
      serve('/preview/spec.json', utf8.encode(jsonEncode({
        'version': 'v1',
        'bundle': {'url': '$base/b', 'md5': _md5Hex(utf8.encode('other'))},
        'messages': {'url': '$base/m', 'md5': _md5Hex(utf8.encode('other'))},
      })));
      serve('/preview/b', payload);
      serve('/preview/m', payload);
      final loader = A2uiCardPreviewLoader();
      await expectLater(
        loader.load(
          specUrl: '$base/spec.json',
          allowlist: ['$base/'],
          cacheDirectory: tempDir(),
          allowHttp: true,
        ),
        throwsA(isA<A2uiPreviewException>()
            .having((e) => e.message, 'message', contains('MD5 不匹配'))),
      );
    });

    test('messages 不是 JSON 数组时拒绝', () async {
      // 让两个产物内容一致，从而通过 MD5，再由 messages 的形状校验拦下
      final payload = utf8.encode('{"not":"a list"}');
      final md5sum = _md5Hex(payload);
      serve('/preview/spec.json', utf8.encode(jsonEncode({
        'version': 'v1',
        'bundle': {'url': '$base/b', 'md5': md5sum},
        'messages': {'url': '$base/m', 'md5': md5sum},
      })));
      serve('/preview/b', payload);
      serve('/preview/m', payload);
      final loader = A2uiCardPreviewLoader();
      await expectLater(
        loader.load(
          specUrl: '$base/spec.json',
          allowlist: ['$base/'],
          cacheDirectory: tempDir(),
          allowHttp: true,
        ),
        throwsA(isA<A2uiPreviewException>()
            .having((e) => e.message, 'message', contains('不是可解析的 JSON 数组'))),
      );
    });

    test('装载成功且二次命中缓存', () async {
      final bundleBytes = utf8.encode('fake-lynx-bundle');
      final messageBytes = utf8.encode('[{"id":"root","type":"Box"}]');
      final cacheDir = tempDir();
      serve('/preview/spec.json', utf8.encode(jsonEncode({
        'version': 'v1',
        'kind': 'display',
        'bundle': {'url': '$base/b', 'md5': _md5Hex(bundleBytes)},
        'messages': {'url': '$base/m', 'md5': _md5Hex(messageBytes)},
      })));
      serve('/preview/b', bundleBytes);
      serve('/preview/m', messageBytes);

      final loader = A2uiCardPreviewLoader();
      final first = await loader.load(
        specUrl: '$base/spec.json',
        allowlist: ['$base/'],
        cacheDirectory: cacheDir,
        allowHttp: true,
      );
      expect(first.kind, 'display');
      expect(first.messages.length, 1);
      expect(first.bundleSource, A2uiCardPreviewSource.network);
      expect(first.bundleBytes, bundleBytes);

      // 第二次断掉产物路由，只剩缓存可用
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
      expect(second.messages, first.messages);
    });
  });
}

String _md5Hex(List<int> bytes) => md5.convert(bytes).toString();