import 'dart:io';

import 'package:flutter_lynx_example/a2ui_card_preview.dart';
import 'package:flutter_test/flutter_test.dart';

/// 固化「Makefile 派生的白名单」与「发布脚本产出的 spec 路径」之间的不变量。
///
/// 背景：Makefile 用 `$(PUBLIC_BASE)/preview/` 派生 A2UI_PREVIEW_ALLOWED，
/// 而 `npm run a2ui:preview` 把产物写在 `${PUBLIC_BASE}/preview/${version}/`。
/// 两边如果漂移，表现是「扫了没反应」——加载器在白名单判定就拒了，
/// 不会走到下载，因此非常难排查。这里把路径形状钉死。
void main() {
  group('白名单派生与 spec 路径对齐', () {
    test('Makefile 派生的前缀能覆盖发布脚本产出的 spec', () {
      const publicBase = 'https://bucket.oss-cn-hangzhou.aliyuncs.com/cards/a2ui';
      // Makefile: ALLOWLIST := $(PUBLIC_BASE)/preview/
      final allowlist = ['$publicBase/preview/'];

      // release-a2ui.mjs preview 分支: spec 的 URL 形状
      const version = 'preview-abc123-202610170723';
      final specUrl = '$publicBase/preview/$version/card-spec.json';
      final bundleUrl = '$publicBase/preview/$version/a2ui-card.lynx.bundle';
      final messagesUrl =
          '$publicBase/preview/$version/confirm-card-messages.json';

      expect(A2uiCardPreviewLoader.isAllowed(specUrl, allowlist), isTrue,
          reason: 'spec 地址必须被放行，否则扫码完全无响应');
      expect(A2uiCardPreviewLoader.isAllowed(bundleUrl, allowlist), isTrue,
          reason: 'bundle 地址必须被放行');
      expect(A2uiCardPreviewLoader.isAllowed(messagesUrl, allowlist), isTrue,
          reason: 'messages 地址必须被放行');
    });

    test('白名单不覆盖线上热更路径（preview 与线上分区隔离）', () {
      const publicBase = 'https://bucket.oss-cn-hangzhou.aliyuncs.com/cards/a2ui';
      final allowlist = ['$publicBase/preview/'];

      // 线上版本化产物路径不带 preview/ 段
      const version = 'abc123-202610170723';
      final onlineBundle = '$publicBase/$version/a2ui-card.lynx.bundle';
      final manifest = '$publicBase/manifest.json';

      expect(A2uiCardPreviewLoader.isAllowed(onlineBundle, allowlist), isFalse);
      expect(A2uiCardPreviewLoader.isAllowed(manifest, allowlist), isFalse);
    });

    test('PUBLIC_BASE 带尾斜杠时派生仍正确（避免 //preview 双重斜杠）', () {
      const publicBaseWithSlash =
          'https://bucket.oss-cn-hangzhou.aliyuncs.com/cards/a2ui/';
      // 发布脚本对 PUBLIC_BASE 做了 replace(/\/$/, "") 去尾斜杠，
      // Makefile 侧用 $(PUBLIC_BASE)/preview/ 拼接会得到 //preview/，
      // 此处确保这种情况在加载器侧仍能匹配（白名单按前缀语义不解析 URL）。
      final allowlist = ['$publicBaseWithSlash/preview/'];
      final specUrl = '$publicBaseWithSlash/preview/v1/card-spec.json';
      expect(A2uiCardPreviewLoader.isAllowed(specUrl, allowlist), isTrue);
    });

    test('A2UI_PREVIEW_ALLOW_HTTP 默认关闭时拒绝 http 产物', () {
      // Makefile 的 preview-run 不传 ALLOW_HTTP，因此编译期默认 false。
      const allowlist = ['http://127.0.0.1:8000/preview/'];
      const specUrl = 'http://127.0.0.1:8000/preview/v1/card-spec.json';
      expect(
        A2uiCardPreviewLoader.isAllowed(specUrl, allowlist),
        isFalse,
        reason: '默认必须拒绝明文 http',
      );
      // 仅 preview-run-local 显式开启后才放行
      expect(
        A2uiCardPreviewLoader.isAllowed(specUrl, allowlist, allowHttp: true),
        isTrue,
      );
    });
  });

  group('Makefile 存在且注入正确的 define', () {
    test('Makefile 声明了预览目标', () {
      final makefile = File('../Makefile');
      expect(makefile.existsSync(), isTrue,
          reason: 'Makefile 应存在于 flutter_lynx 仓库根');
      final content = makefile.readAsStringSync();
      expect(content, contains('A2UI_PREVIEW_ALLOWED'));
      expect(content, contains(r'$(PUBLIC_BASE)/preview/'));

      // preview-run 的实际命令行不得带 http 开关。
      // 只看 flutter run 那一行，避开上方注释里对该开关的说明文字。
      final previewRunBody = content
          .split('preview-run: require_public_base')
          .last
          .split('preview-run-local:')
          .first;
      expect(previewRunBody, isNot(contains('ALLOW_HTTP')),
          reason: 'preview-run 必须默认只认 https');
      expect(previewRunBody, contains('A2UI_PREVIEW_ALLOWED'));
    });
  });
}