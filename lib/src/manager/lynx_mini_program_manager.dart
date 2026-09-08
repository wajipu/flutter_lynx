import "dart:io";
import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";
import "mini_program_manifest.dart";
import "bundle_downloader.dart";

/// Manager responsible for downloading, caching, hot updating and launching Lynx dynamic mini programs.
class LynxMiniProgramManager {
  static final LynxMiniProgramManager _instance = LynxMiniProgramManager._internal();
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
  /// If bundle is local asset (starts with assets/ or asset://), returns it directly.
  /// If already downloaded and verified, returns local bundle path immediately.
  /// Otherwise downloads, extracts and returns the local file path.
  Future<String> prepareBundle(
    MiniProgramManifest manifest, {
    void Function(double progress)? onProgress,
  }) async {
    final url = manifest.bundleUrl;

    // 1. Check if it is a local asset bundle
    if (url.startsWith("assets/") || url.startsWith("asset://")) {
      return url;
    }

    // 2. Check if it is a direct local file
    if (url.startsWith("file://") || (Platform.isMacOS || Platform.isLinux) && url.startsWith("/")) {
      return url;
    }

    // 3. Remote URL -> Check local cache
    final targetDir = await getMiniProgramDirectory(manifest.appId, manifest.version);
    final bundlePath = p.join(targetDir, "main.lynx.bundle");
    final bundleFile = File(bundlePath);

    if (await bundleFile.exists()) {
      // Cache hit!
      onProgress?.call(1.0);
      return bundlePath;
    }

    // 4. Cache miss -> Download and cache
    final downloadedPath = await _downloader.downloadAndExtract(
      url: url,
      targetDirectory: targetDir,
      expectedMd5: manifest.md5,
      onProgress: onProgress,
    );

    return downloadedPath;
  }

  /// Delete cached mini programs.
  Future<void> clearCache({String? appId}) async {
    final root = await getMiniProgramsRootDirectory();
    if (appId != null) {
      final appDir = Directory(p.join(root, appId));
      if (await appDir.exists()) {
        await appDir.delete(recursive: true);
      }
    } else {
      final rootDir = Directory(root);
      if (await rootDir.exists()) {
        await rootDir.delete(recursive: true);
      }
    }
  }
}
