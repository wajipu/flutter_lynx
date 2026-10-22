import "dart:convert";
import "dart:io";

import "package:crypto/crypto.dart";
import "package:flutter/foundation.dart";
import "package:dio/dio.dart";

import "bundle_downloader.dart";
import "../utils/lynx_logger.dart";

/// 单通道版本条目（stable 或 gray）。
class LynxBundleChannelEntry {
  final String url;
  final String version;
  final String md5;

  /// 灰度百分比 0-100（仅 gray 通道有意义；0 = 关闭灰度）。
  final int percent;

  const LynxBundleChannelEntry({
    required this.url,
    required this.version,
    required this.md5,
    this.percent = 0,
  });

  static LynxBundleChannelEntry? tryParse(Map<String, dynamic> map) {
    final url = map["url"]?.toString() ?? "";
    final version = map["version"]?.toString() ?? "";
    final md5 = map["md5"]?.toString() ?? "";
    final percent = ((map["percent"] as num?)?.toInt() ?? 0).clamp(0, 100);
    if (url.isEmpty || version.isEmpty || md5.length != 32) return null;
    return LynxBundleChannelEntry(
      url: url,
      version: version,
      md5: md5,
      percent: percent,
    );
  }
}

/// OSS 下发的 bundle 版本清单。
///
/// v2：`{"stable": {...}, "gray": {..., "percent": 10}}`；
/// 兼容 v1 扁平 `{"version","url","md5"}`（视为仅 stable 通道）。
class LynxBundleRemoteManifest {
  final LynxBundleChannelEntry stable;
  final LynxBundleChannelEntry? gray;

  const LynxBundleRemoteManifest({required this.stable, this.gray});

  static LynxBundleRemoteManifest? tryParse(Uint8List raw) {
    try {
      final map = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
      // v2：带 stable 子对象
      final stableMap = map["stable"];
      if (stableMap is Map<String, dynamic>) {
        final stable = LynxBundleChannelEntry.tryParse(stableMap);
        if (stable == null) return null;
        LynxBundleChannelEntry? gray;
        final grayMap = map["gray"];
        if (grayMap is Map<String, dynamic>) {
          gray = LynxBundleChannelEntry.tryParse(grayMap);
        }
        return LynxBundleRemoteManifest(stable: stable, gray: gray);
      }
      // v1：扁平字段
      final stable = LynxBundleChannelEntry.tryParse(map);
      if (stable == null) return null;
      return LynxBundleRemoteManifest(stable: stable);
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

  /// 命中的通道："stable" | "gray"；builtin 时为 null。
  final String? channel;
  final String? version;
  final Object? error;

  const LynxBundleResolved({
    required this.bytes,
    required this.source,
    this.channel,
    this.version,
    this.error,
  });
}

/// OSS bundle 动态下发统一入口：灰度分桶 → 版本检查 → 下载校验 → 缓存
/// → 坏版本熔断 → 失败回退内置。
///
/// 适用于 templateBytes 直喂链路（确认卡 / A2UI 渲染器等随包内置的 bundle
/// 需要 OTA 更新的场景）。URL 链路的小程序请走 [LynxMiniProgramManager]。
///
/// manifest v2 支持双通道灰度：gray.percent > 0 时，按 deviceId 稳定分桶
/// （同一设备结果恒定），桶号 < percent 的设备吃 gray 版本，其余吃 stable。
/// 宿主装载失败后调用 [markLoadFailed] 熔断该版本：本机后续启动直接回退
/// 内置，直到 manifest 发布更新的版本号。
class LynxBundleUpdater {
  final BundleDownloader _downloader;

  LynxBundleUpdater({BundleDownloader? downloader})
      : _downloader = downloader ?? BundleDownloader();

  /// 设备分桶：deviceId 的 FNV-1a 稳定哈希 → 0-99。
  /// 同一 deviceId 结果恒定（不会忽新忽旧）；分布近似均匀。
  static int deviceBucket(String deviceId) {
    var hash = 0x811c9dc5;
    for (final code in deviceId.codeUnits) {
      hash ^= code;
      hash = (hash * 0x01000193) & 0x7ffffffffffffff;
    }
    return hash % 100;
  }

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

  /// 选择目标通道：gray 存在且 percent > 0 且设备落桶 → gray，否则 stable。
  @visibleForTesting
  LynxBundleChannelEntry pickTarget(
    LynxBundleRemoteManifest manifest,
    String? deviceId,
  ) {
    final gray = manifest.gray;
    if (gray != null &&
        gray.percent > 0 &&
        deviceId != null &&
        deviceId.isNotEmpty &&
        deviceBucket(deviceId) < gray.percent) {
      return gray;
    }
    return manifest.stable;
  }

  /// 本机坏版本清单（装载失败熔断记录）。
  File _badVersionsFile(String cacheDirectory) =>
      File("$cacheDirectory/bad_versions.json");

  Set<String> _readBadVersions(String cacheDirectory) {
    try {
      final file = _badVersionsFile(cacheDirectory);
      if (!file.existsSync()) return <String>{};
      final list = jsonDecode(file.readAsStringSync()) as List<dynamic>;
      return list.map((e) => e.toString()).toSet();
    } catch (_) {
      return <String>{};
    }
  }

  /// 熔断指定版本：装载失败后调用。该版本在本机后续 resolve 直接回退内置，
  /// 直到 OSS 发布新的版本号（坏清单按版本号记，不阻塞新版本）。
  Future<void> markLoadFailed({
    required String cacheDirectory,
    required String version,
    String cacheFileName = "main.lynx.bundle",
  }) async {
    final bad = _readBadVersions(cacheDirectory);
    if (bad.add(version)) {
      await _badVersionsFile(cacheDirectory)
          .writeAsString(jsonEncode(bad.toList()));
    }
    // 命中的缓存一并清除，防止缓存命中路径绕过熔断
    final cacheFile = File("$cacheDirectory/$cacheFileName");
    final metaFile = File("$cacheDirectory/$cacheFileName.meta");
    try {
      if (await cacheFile.exists()) await cacheFile.delete();
      if (await metaFile.exists()) await metaFile.delete();
    } catch (_) {}
    LynxLogger.info("BundleUpdater", "版本 $version 已熔断（本机回退内置）");
  }

  /// 统一装载解析。任何环节失败都回退 [builtinBytes]，不抛出——
  /// A2UI/确认卡功能永不因下发链路中断。
  Future<LynxBundleResolved> resolve({
    required String manifestUrl,
    required Uint8List builtinBytes,
    required String cacheDirectory,
    String? deviceId,
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

    final target = pickTarget(manifest, deviceId);
    final isGray = identical(target, manifest.gray);

    // 坏版本熔断：该版本曾装载失败，本机直接回退内置
    if (_readBadVersions(cacheDirectory).contains(target.version)) {
      LynxLogger.info(
        "BundleUpdater",
        "版本 ${target.version} 在本机熔断名单中，回退内置版本",
      );
      return LynxBundleResolved(
        bytes: builtinBytes,
        source: LynxBundleSource.builtin,
        channel: isGray ? "gray" : "stable",
        version: target.version,
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
        if (meta["version"] == target.version &&
            meta["md5"] == target.md5 &&
            cachedMd5 == target.md5) {
          LynxLogger.info(
            "BundleUpdater",
            "缓存命中 version=${target.version}",
          );
          return LynxBundleResolved(
            bytes: cachedBytes,
            source: LynxBundleSource.cache,
            channel: isGray ? "gray" : "stable",
            version: target.version,
          );
        }
      } catch (_) {
        // 缓存损坏，走重新下载
      }
    }

    // 下载 + md5 校验 + 原子落缓存
    try {
      final path = await _downloader.downloadAndExtract(
        url: target.url,
        targetDirectory: cacheDirectory,
        expectedMd5: target.md5,
      );
      final bytes = await File(path).readAsBytes();
      await metaFile.writeAsString(
        jsonEncode({"version": target.version, "md5": target.md5}),
      );
      LynxLogger.info(
        "BundleUpdater",
        "新版本下载完成 version=${target.version}"
        "${isGray ? "（灰度）" : ""}（${bytes.length} 字节）",
      );
      return LynxBundleResolved(
        bytes: bytes,
        source: LynxBundleSource.network,
        channel: isGray ? "gray" : "stable",
        version: target.version,
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
        channel: isGray ? "gray" : "stable",
        error: error,
      );
    }
  }
}
