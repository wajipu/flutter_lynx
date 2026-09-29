import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:crypto/crypto.dart";
import "package:dio/dio.dart";

import "bundle_downloader.dart";
import "../utils/lynx_logger.dart";

/// OSS 下发的 bundle 版本清单（manifest.json）。
class LynxBundleRemoteManifest {
  final String url;
  final String version;
  final String md5;

  const LynxBundleRemoteManifest({
    required this.url,
    required this.version,
    required this.md5,
  });

  static LynxBundleRemoteManifest? tryParse(Uint8List raw) {
    try {
      final map = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      final url = map["url"]?.toString() ?? "";
      final version = map["version"]?.toString() ?? "";
      final md5 = map["md5"]?.toString() ?? "";
      if (url.isEmpty || version.isEmpty || md5.length != 32) return null;
      return LynxBundleRemoteManifest(url: url, version: version, md5: md5);
    } catch (_) {
      return null;
    }
  }
}

/// 解析结果来源：network（本次下载）/ cache（本地缓存命中）/ builtin（回退内置）。
enum LynxBundleSource { network, cache, builtin }

class LynxBundleResolved {
  final Uint8List bytes;
  final LynxBundleSource source;
  final String? version;
  final Object? error;

  const LynxBundleResolved({
    required this.bytes,
    required this.source,
    this.version,
    this.error,
  });
}

/// OSS bundle 动态下发统一入口：版本检查 → 下载校验 → 缓存 → 失败回退内置。
///
/// 适用于 templateBytes 直喂链路（确认卡 / A2UI 渲染器等随包内置的 bundle
/// 需要 OTA 更新的场景）。URL 链路的小程序请走 [LynxMiniProgramManager]
/// （其下载/缓存/回退已内建）。
///
/// 流程：
/// 1. 拉 manifest（{"version","url","md5"}），失败回退内置
/// 2. 本地缓存存在且 version+md5 与 manifest 一致 → 缓存命中
/// 3. 否则下载 bundle → md5 校验 → 原子写缓存 → 返回
/// 4. 下载/校验失败 → 回退内置（缓存损坏时一并清除）
class LynxBundleUpdater {
  final BundleDownloader _downloader;

  LynxBundleUpdater({BundleDownloader? downloader})
      : _downloader = downloader ?? BundleDownloader();

  /// 拉取 manifest 原始字节（带查询参数防 CDN 缓存）。
  Future<Uint8List> fetchManifestRaw(String manifestUrl) async {
    final response = await Dio(
      BaseOptions(
        connectTimeout: const Duration(milliseconds: 2500),
        receiveTimeout: const Duration(milliseconds: 2500),
      ),
    ).get<List<int>>(
      manifestUrl,
      options: Options(responseType: ResponseType.bytes),
      queryParameters: {"t": DateTime.now().millisecondsSinceEpoch},
    );
    if (response.statusCode != 200 || response.data == null) {
      throw Exception("manifest 请求失败: HTTP ${response.statusCode}");
    }
    return Uint8List.fromList(response.data!);
  }

  /// 统一装载解析。任何环节失败都回退 [builtinBytes]（宿主从内置资产读出），
  /// 不抛出——A2UI/确认卡功能永不因下发链路中断。
  Future<LynxBundleResolved> resolve({
    required String manifestUrl,
    required Uint8List builtinBytes,
    required String cacheDirectory,
    // 缓存文件名与 BundleDownloader 产物名一致（main.lynx.bundle）
    String cacheFileName = "main.lynx.bundle",
  }) async {
    LynxBundleRemoteManifest? manifest;
    Object? manifestError;
    try {
      manifest = LynxBundleRemoteManifest.tryParse(
        await fetchManifestRaw(manifestUrl),
      );
    } catch (error) {
      manifestError = error;
    }

    if (manifest == null) {
      LynxLogger.info(
        "BundleUpdater",
        "manifest 不可用（${manifestError ?? "格式非法"}），回退内置版本",
      );
      return LynxBundleResolved(
        bytes: builtinBytes,
        source: LynxBundleSource.builtin,
        error: manifestError,
      );
    }

    final cacheFile = File("$cacheDirectory/$cacheFileName");
    final metaFile = File("$cacheDirectory/$cacheFileName.meta");

    // 缓存命中：版本与 md5 双一致
    if (await cacheFile.exists() && await metaFile.exists()) {
      try {
        final meta =
            jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
        final cachedBytes = await cacheFile.readAsBytes();
        final cachedMd5 = md5.convert(cachedBytes).toString();
        if (meta["version"] == manifest.version &&
            meta["md5"] == manifest.md5 &&
            cachedMd5 == manifest.md5) {
          LynxLogger.info(
            "BundleUpdater",
            "缓存命中 version=${manifest.version}",
          );
          return LynxBundleResolved(
            bytes: cachedBytes,
            source: LynxBundleSource.cache,
            version: manifest.version,
          );
        }
      } catch (_) {
        // 缓存损坏，走重新下载
      }
    }

    // 下载 + md5 校验 + 原子落缓存
    try {
      final path = await _downloader.downloadAndExtract(
        url: manifest.url,
        targetDirectory: cacheDirectory,
        expectedMd5: manifest.md5,
      );
      final bytes = await File(path).readAsBytes();
      await metaFile.writeAsString(
        jsonEncode({"version": manifest.version, "md5": manifest.md5}),
      );
      LynxLogger.info(
        "BundleUpdater",
        "新版本下载完成 version=${manifest.version}（${bytes.length} 字节）",
      );
      return LynxBundleResolved(
        bytes: bytes,
        source: LynxBundleSource.network,
        version: manifest.version,
      );
    } catch (error) {
      LynxLogger.info(
        "BundleUpdater",
        "下载/校验失败（$error），清除损坏缓存并回退内置版本",
      );
      // 下载失败可能留下半截缓存文件，清掉防止下次误判命中
      try {
        if (await cacheFile.exists()) await cacheFile.delete();
        if (await metaFile.exists()) await metaFile.delete();
      } catch (_) {}
      return LynxBundleResolved(
        bytes: builtinBytes,
        source: LynxBundleSource.builtin,
        error: error,
      );
    }
  }
}
