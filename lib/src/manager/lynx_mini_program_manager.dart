import "dart:io";
import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";
import "package:flutter/services.dart" show rootBundle;
import "mini_program_manifest.dart";
import "bundle_downloader.dart";
import "../utils/lynx_logger.dart";

/// Manager responsible for downloading, caching, hot updating and launching Lynx dynamic mini programs.
class LynxMiniProgramManager {
  static final LynxMiniProgramManager _instance =
      LynxMiniProgramManager._internal();
  factory LynxMiniProgramManager() => _instance;
  static LynxMiniProgramManager get instance => _instance;

  final BundleDownloader _downloader;

  LynxMiniProgramManager._internal({BundleDownloader? downloader})
      : _downloader = downloader ?? BundleDownloader();

  /// Resolve root storage directory for mini programs.
  Future<String> getMiniProgramsRootDirectory() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final path = p.join(docsDir.path, "lynx_miniapps");
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return path;
  }

  /// Get specific directory for an appId and version.
  Future<String> getMiniProgramDirectory(String appId, String version) async {
    final root = await getMiniProgramsRootDirectory();
    return p.join(root, appId, version);
  }

  /// Prepare the mini program bundle.
  /// If bundle is local asset (starts with assets/ or asset://), it unpacks it to disk for the native engine.
  /// 缓存只负责定位文件，是否可执行由原生引擎加载结果判断。
  /// Otherwise downloads, extracts and returns the local file path.
  Future<String> prepareBundle(
    MiniProgramManifest manifest, {
    void Function(double progress)? onProgress,
  }) async {
    final startTime = DateTime.now();
    LynxLogger.info("Manager",
        "[1/4] 开始装载小程序: ${manifest.name} (appId: ${manifest.appId}, v${manifest.version})");

    final url = manifest.bundleUrl;
    final targetDir =
        await getMiniProgramDirectory(manifest.appId, manifest.version);
    final bundlePath = p.join(targetDir, "main.lynx.bundle");
    final bundleFile = File(bundlePath);

    // 1. Check if it is a local Flutter asset bundle
    if (url.startsWith("assets/") || url.startsWith("asset://")) {
      final cleanAssetPath = url.replaceFirst("asset://", "");
      LynxLogger.info("Manager", "[2/4] 检测到内置 Asset 资源: $cleanAssetPath");
      if (!await bundleFile.exists()) {
        await bundleFile.parent.create(recursive: true);
        // 缺失资源必须报错，禁止创建演示替代包掩盖失败。
        final byteData = await rootBundle.load(cleanAssetPath);
        final bytes = byteData.buffer
            .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
        await bundleFile.writeAsBytes(bytes);
        LynxLogger.info("Manager",
            "已成功从 Flutter Asset 解包至沙盒: $bundlePath (${bytes.length} 字节)");
      } else {
        LynxLogger.info("Manager", "内置 Asset 沙盒缓存已存在: $bundlePath");
      }
      onProgress?.call(1.0);
      final cost = DateTime.now().difference(startTime).inMilliseconds;
      LynxLogger.info("Manager", "[3/4] Bundle 准备完毕，耗时 ${cost}ms");
      return bundlePath;
    }

    // 2. Check if it is a direct local file
    if (url.startsWith("file://") || p.isAbsolute(url)) {
      final localPath =
          url.startsWith("file://") ? Uri.parse(url).toFilePath() : url;
      if (!await File(localPath).exists()) {
        throw FileSystemException("Lynx bundle does not exist", localPath);
      }
      LynxLogger.info("Manager", "[2/4] 直接加载本地开发文件 Bundle: $localPath");
      onProgress?.call(1.0);
      return localPath;
    }

    // 3. Remote URL -> Check local cache
    if (await bundleFile.exists()) {
      final size = await bundleFile.length();
      LynxLogger.info(
          "Manager", "[2/4] 命中小程序本地离线缓存: $bundlePath (文件大小: $size 字节)");
      onProgress?.call(1.0);
      final cost = DateTime.now().difference(startTime).inMilliseconds;
      LynxLogger.info("Manager", "[3/4] 本地秒开就绪，总耗时 ${cost}ms");
      return bundlePath;
    }

    // 4. Cache miss -> Download and cache
    LynxLogger.info("Manager", "[2/4] 本地未命中缓存，发起网络拉取: $url");
    try {
      final downloadedPath = await _downloader.downloadAndExtract(
        url: url,
        targetDirectory: targetDir,
        expectedMd5: manifest.md5,
        onProgress: onProgress,
      );
      final cost = DateTime.now().difference(startTime).inMilliseconds;
      LynxLogger.info(
          "Manager", "[3/4] 远程 Bundle 下载解包成功: $downloadedPath (耗时: ${cost}ms)");
      return downloadedPath;
    } catch (e) {
      LynxLogger.warn("Manager", "远程拉取失败: $e");
      rethrow;
    }
  }

  /// Delete cached mini programs.
  Future<void> clearCache({String? appId}) async {
    final root = await getMiniProgramsRootDirectory();
    if (appId != null) {
      final appDir = Directory(p.join(root, appId));
      if (await appDir.exists()) {
        await appDir.delete(recursive: true);
        LynxLogger.info("Manager", "已清除小程序缓存: $appId");
      }
    } else {
      final rootDir = Directory(root);
      if (await rootDir.exists()) {
        await rootDir.delete(recursive: true);
        LynxLogger.info("Manager", "已清除全部离线小程序缓存");
      }
    }
  }
}
