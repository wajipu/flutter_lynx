import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

/// A2UI 卡片扫码直开（OSS 预览）的加载器。
///
/// 协议与 spec 格式以 koklam-docs `features/a2ui-card-qr-open/03_contract.md` 为准。
///
/// 与 [LynxBundleUpdater]（manifest OTA 灰度链路）的根本区别：
/// - 本链路只服务开发与评审期的预览，**失败就失败**，不回退内置、不静默重试；
/// - 卡片由 bundle + messages 两部分组成，两者都必须下发（卡片内容在 messages 里）；
/// - 准入靠域名白名单，而不是 manifest 指针。
class A2uiCardPreviewLoader {
  /// 原生侧 `kMaxBundleBytes` 上限，远程产物同样不得越过。
  static const int maxBytes = 10 * 1024 * 1024;

  static const String _scheme = 'koklam';
  static const String _host = 'card';

  final Dio _dio;

  A2uiCardPreviewLoader({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 20),
            ));

  /// 从 `koklam://card?spec=...` 取出 spec 地址。
  ///
  /// 严格校验 scheme、host 与唯一的非空 spec 参数；不合法返回 null，
  /// 由调用方决定如何提示（本链路不做静默忽略）。
  static String? parseSpecUrl(String rawUri) {
    final uri = Uri.tryParse(rawUri.trim());
    if (uri == null) return null;
    if (uri.scheme != _scheme || uri.host != _host) return null;
    final spec = uri.queryParameters['spec']?.trim() ?? '';
    if (spec.isEmpty) return null;
    return spec;
  }

  /// 按白名单判定地址是否放行。
  ///
  /// [allowHttp] 仅为本机 `python3 -m http.server` 联调存在，不得带进评审或发布环境。
  static bool isAllowed(String url, List<String> allowlist, {bool allowHttp = false}) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return false;
    final schemeOk = uri.scheme == 'https' || (allowHttp && uri.scheme == 'http');
    if (!schemeOk) return false;
    if (allowlist.isEmpty) return false;
    return allowlist.any((prefix) => _matchesPrefix(url, prefix));
  }

  /// 前缀匹配。`allowlist` 项约定以 `/` 结尾，比对时补齐 origin 与路径。
  static bool _matchesPrefix(String url, String prefix) {
    if (prefix.isEmpty) return false;
    final p = prefix.endsWith('/') ? prefix : '$prefix/';
    return url.startsWith(p);
  }

  /// 下载并校验 spec 引用的两个产物，返回渲染所需的 bundle 与 messages。
  ///
  /// 任何一步失败都抛出 [A2uiPreviewException] 并在调用方停止渲染；
  /// 下载产生的部分文件由调用方按 [result] 为 null 的语义自行忽略（本类不留半截产物）。
  Future<A2uiCardPreviewResult> load({
    required String specUrl,
    required List<String> allowlist,
    required String cacheDirectory,
    bool allowHttp = false,
    void Function(String message)? onLog,
  }) async {
    void log(String m) => onLog?.call(m);

    if (!isAllowed(specUrl, allowlist, allowHttp: allowHttp)) {
      throw A2uiPreviewException(
        '域名不在允许范围：$specUrl\n'
        '请确认它匹配编译期 A2UI_PREVIEW_ALLOWED 配置的前缀。',
      );
    }

    final specRaw = await _download(specUrl, maxBytes: 1024 * 1024);
    final spec = A2uiCardSpec.tryParse(utf8.decode(specRaw));
    if (spec == null) {
      throw A2uiPreviewException('spec 解析失败或缺少必填字段：$specUrl');
    }
    log('Preview >> spec 解析成功 version=${spec.version} kind=${spec.kind}');

    // bundle 与 messages 的地址分别判定——spec 在白名单内不代表产物也在白名单内。
    for (final entry in [spec.bundle, spec.messages]) {
      if (!isAllowed(entry.url, allowlist, allowHttp: allowHttp)) {
        throw A2uiPreviewException('域名不在允许范围：${entry.url}');
      }
    }

    final versionDir = Directory('$cacheDirectory/${spec.version}');
    final bundle = await _loadArtifact(
      spec.bundle,
      'bundle',
      versionDir,
      'a2ui-card.lynx.bundle',
      spec.version,
      log,
    );
    final messages = await _loadArtifact(
      spec.messages,
      'messages',
      versionDir,
      '${spec.kind}-card-messages.json',
      spec.version,
      log,
    );

    final List<dynamic> decoded;
    try {
      final list = jsonDecode(utf8.decode(messages.bytes));
      if (list is! List) throw const FormatException('not a list');
      decoded = list;
    } catch (error) {
      throw A2uiPreviewException('messages 不是可解析的 JSON 数组：$error');
    }

    return A2uiCardPreviewResult(
      version: spec.version,
      title: spec.title ?? spec.version,
      kind: spec.kind,
      bundleBytes: bundle.bytes,
      messages: decoded,
      bundleSource: bundle.source,
      messagesSource: messages.source,
    );
  }

  /// 单个产物的缓存命中 / 下载 + MD5 校验。
  Future<_Artifact> _loadArtifact(
    A2uiCardSpecArtifact entry,
    String label,
    Directory versionDir,
    String fileName,
    String version,
    void Function(String) log,
  ) async {
    final file = File('${versionDir.path}/$fileName');
    final metaFile = File('${file.path}.meta');

    // 缓存命中：version 与 md5 双一致（与 LynxBundleUpdater 同样的纪律）
    if (await file.exists() && await metaFile.exists()) {
      try {
        final meta = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
        final cached = await file.readAsBytes();
        if (meta['version'] == version &&
            meta['md5'] == entry.md5 &&
            md5.convert(cached).toString() == entry.md5) {
          log('Preview >> $label 缓存命中 version=$version（${cached.length} 字节）');
          return _Artifact(cached, A2uiCardPreviewSource.cache);
        }
      } catch (_) {
        // 缓存损坏，走重新下载
      }
    }

    await versionDir.create(recursive: true);
    Uint8List bytes;
    try {
      bytes = await _download(entry.url, maxBytes: maxBytes);
    } catch (error) {
      // 下载失败可能留下半截缓存，清掉防止下次误判命中
      await _deleteQuietly(file);
      await _deleteQuietly(metaFile);
      throw A2uiPreviewException('$label 下载失败：$error');
    }

    final actual = md5.convert(bytes).toString();
    if (actual != entry.md5) {
      await _deleteQuietly(file);
      throw A2uiPreviewException(
        '$label MD5 不匹配：spec 声明 ${entry.md5}，实际 $actual',
      );
    }

    await file.writeAsBytes(bytes, flush: true);
    await metaFile.writeAsString(jsonEncode({'version': version, 'md5': entry.md5}));
    log('Preview >> $label 下载完成 version=$version（${bytes.length} 字节）');
    return _Artifact(bytes, A2uiCardPreviewSource.network);
  }

  Future<Uint8List> _download(String url, {required int maxBytes}) async {
    final response = await _dio.get<List<int>>(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final data = response.data;
    if (data == null || data.isEmpty) {
      throw A2uiPreviewException('响应为空：$url');
    }
    if (data.length > maxBytes) {
      throw A2uiPreviewException(
        '产物超出上限：${data.length} 字节 > $maxBytes 字节',
      );
    }
    return Uint8List.fromList(data);
  }

  Future<void> _deleteQuietly(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {
      // 清理失败不掩盖原始错误
    }
  }
}

/// 预览装载失败。消息面向开发者，须指出具体哪一项不合法。
class A2uiPreviewException implements Exception {
  final String message;
  const A2uiPreviewException(this.message);

  @override
  String toString() => message;
}

enum A2uiCardPreviewSource { network, cache }

/// spec 里指向单个产物的地址与校验和。
class A2uiCardSpecArtifact {
  final String url;
  final String md5;
  const A2uiCardSpecArtifact({required this.url, required this.md5});
}

/// card spec。契约见 koklam-docs `features/a2ui-card-qr-open/03_contract.md` §2。
class A2uiCardSpec {
  final String version;
  final String? title;
  final String kind;
  final A2uiCardSpecArtifact bundle;
  final A2uiCardSpecArtifact messages;

  const A2uiCardSpec({
    required this.version,
    required this.kind,
    required this.bundle,
    required this.messages,
    this.title,
  });

  /// MD5 必须恰好 32 位小写 hex——不接受缺失，不降级放行。
  static bool _isMd5(String? value) {
    if (value == null || value.length != 32) return false;
    return RegExp(r'^[0-9a-f]{32}$').hasMatch(value);
  }

  static A2uiCardSpec? tryParse(String text) {
    try {
      final map = jsonDecode(text);
      if (map is! Map<String, dynamic>) return null;
      final version = map['version']?.toString() ?? '';
      if (version.isEmpty) return null;

      final bundle = _parseArtifact(map['bundle']);
      final messages = _parseArtifact(map['messages']);
      if (bundle == null || messages == null) return null;

      // kind 缺失按 confirm 处理；只认这两个值，其余一律拒绝
      // （放行未知 kind 会渲染出形状不匹配的卡片，且难以定位）。
      final rawKind = map['kind']?.toString();
      final kind = (rawKind == null || rawKind.isEmpty) ? 'confirm' : rawKind;
      if (kind != 'confirm' && kind != 'display') return null;

      final title = map['title']?.toString();
      return A2uiCardSpec(
        version: version,
        title: (title == null || title.isEmpty) ? null : title,
        kind: kind,
        bundle: bundle,
        messages: messages,
      );
    } catch (_) {
      return null;
    }
  }

  static A2uiCardSpecArtifact? _parseArtifact(Object? value) {
    if (value is! Map<String, dynamic>) return null;
    final url = value['url']?.toString() ?? '';
    final md5 = value['md5']?.toString() ?? '';
    if (url.isEmpty || !_isMd5(md5)) return null;
    return A2uiCardSpecArtifact(url: url, md5: md5);
  }
}

/// 预览装载结果，渲染所需的全部数据。
class A2uiCardPreviewResult {
  final String version;
  final String title;
  final String kind;
  final Uint8List bundleBytes;
  final List<dynamic> messages;
  final A2uiCardPreviewSource bundleSource;
  final A2uiCardPreviewSource messagesSource;

  const A2uiCardPreviewResult({
    required this.version,
    required this.title,
    required this.kind,
    required this.bundleBytes,
    required this.messages,
    required this.bundleSource,
    required this.messagesSource,
  });
}

class _Artifact {
  final Uint8List bytes;
  final A2uiCardPreviewSource source;
  const _Artifact(this.bytes, this.source);
}