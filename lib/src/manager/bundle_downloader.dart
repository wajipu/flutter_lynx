import "dart:io";
import "dart:typed_data";
import "package:archive/archive.dart";
import "package:crypto/crypto.dart";
import "package:dio/dio.dart";
import "package:path/path.dart" as p;
import "../utils/lynx_logger.dart";

/// Downloader and integrity verifier for dynamic mini-program bundles.
class BundleDownloader {
  final Dio _dio;

  BundleDownloader({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(milliseconds: 2500),
                receiveTimeout: const Duration(milliseconds: 3500),
                sendTimeout: const Duration(milliseconds: 2500),
              ),
            );

  /// Download bundle or zip archive from URL, verify MD5, and save to target directory.
  /// Returns the absolute path to the ready-to-load `main.lynx.bundle`.
  Future<String> downloadAndExtract({
    required String url,
    required String targetDirectory,
    String? expectedMd5,
    void Function(double progress)? onProgress,
  }) async {
    final startTime = DateTime.now();
    LynxLogger.info("Downloader", "开始请求 Bundle: $url (超时保护 2.5s)");
    final dir = Directory(targetDirectory);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final targetBundlePath = p.join(targetDirectory, "main.lynx.bundle");

    // Download to a temporary file
    final tempFilePath = p.join(targetDirectory, "temp_download_${DateTime.now().millisecondsSinceEpoch}.tmp");

    try {
      final response = await _dio.download(
        url,
        tempFilePath,
        onReceiveProgress: (received, total) {
          if (total > 0 && onProgress != null) {
            final progress = received / total;
            onProgress(progress);
            LynxLogger.info("Downloader", "下载进度: ${(progress * 100).toStringAsFixed(0)}% ($received / $total 字节)");
          }
        },
      );

      if (response.statusCode != 200) {
        throw Exception("Failed to download bundle: HTTP ${response.statusCode}");
      }

      final cost = DateTime.now().difference(startTime).inMilliseconds;
      LynxLogger.info("Downloader", "Bundle 下载完成，耗时: ${cost}ms");

      final downloadedFile = File(tempFilePath);
      final bytes = await downloadedFile.readAsBytes();

      // Verify MD5 if provided
      if (expectedMd5 != null && expectedMd5.isNotEmpty) {
        final computedMd5 = md5.convert(bytes).toString().toLowerCase();
        if (computedMd5 != expectedMd5.toLowerCase()) {
          throw Exception("MD5 checksum mismatch! Expected: $expectedMd5, Got: $computedMd5");
        }
      }

      // Check if it is a ZIP archive
      if (_isZip(bytes)) {
        final archive = ZipDecoder().decodeBytes(bytes);
        for (final file in archive) {
          final filename = file.name;
          if (file.isFile) {
            final data = file.content as List<int>;
            final outFile = File(p.join(targetDirectory, filename));
            await outFile.parent.create(recursive: true);
            await outFile.writeAsBytes(data);
          }
        }
      } else {
        // Direct bundle file
        await downloadedFile.copy(targetBundlePath);
      }

      // Cleanup temp
      if (await downloadedFile.exists()) {
        await downloadedFile.delete();
      }

      if (!await File(targetBundlePath).exists()) {
        throw Exception("main.lynx.bundle was not found in the downloaded package");
      }

      return targetBundlePath;
    } catch (e) {
      LynxLogger.error("Downloader", "下载异常: $e");
      // Clean up on failure
      final tempFile = File(tempFilePath);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
      rethrow;
    }
  }

  bool _isZip(Uint8List bytes) {
    if (bytes.length < 4) return false;
    // ZIP magic number: PK\x03\x04
    return bytes[0] == 0x50 && bytes[1] == 0x4B && bytes[2] == 0x03 && bytes[3] == 0x04;
  }
}
