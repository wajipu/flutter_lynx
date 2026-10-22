import "dart:convert";
import "dart:io";
import "dart:typed_data";

import "package:crypto/crypto.dart";
import "package:flutter_lynx/src/manager/lynx_bundle_updater.dart";
import "package:flutter_test/flutter_test.dart";

/// LynxBundleUpdater 单测：本地 HttpServer 模拟 OSS（manifest + bundle），
/// 覆盖 版本检查/下载校验/缓存命中/损坏回退/失败回退 全路径。
void main() {
  late HttpServer server;
  late String manifestUrl;
  late String bundleUrl;
  late String cacheDirectory;

  // 内容稳定的 32 字节假 bundle（内容随机化由各用例覆写 handler 控制）
  final bundleBytes = Uint8List.fromList(List.generate(64, (i) => i));

  var servedManifest = <String, dynamic>{};
  var serveManifestOk = true;
  var serveBundleOk = true;
  var bundleRequests = 0;

  setUpAll(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final path = request.uri.path;
      if (path.endsWith("manifest.json")) {
        if (!serveManifestOk) {
          request.response.statusCode = 500;
          await request.response.close();
          return;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.add(utf8.encode(jsonEncode(servedManifest)));
        await request.response.close();
        return;
      }
      if (path.endsWith(".bundle")) {
        bundleRequests += 1;
        if (!serveBundleOk) {
          request.response.statusCode = 500;
          await request.response.close();
          return;
        }
        request.response.add(bundleBytes);
        await request.response.close();
        return;
      }
      request.response.statusCode = 404;
      await request.response.close();
    });
    bundleUrl = "http://${server.address.host}:${server.port}/a2ui.bundle";
  });

  tearDownAll(() async {
    await server.close(force: true);
  });

  setUp(() async {
    cacheDirectory =
        "${Directory.systemTemp.path}/updater-test-${DateTime.now().millisecondsSinceEpoch}";
    manifestUrl =
        "http://${server.address.host}:${server.port}/manifest.json";
    servedManifest = {
      "version": "5",
      "url": bundleUrl,
      "md5": "x" * 32, // 各用例覆写为真实值
    };
    serveManifestOk = true;
    serveBundleOk = true;
    bundleRequests = 0;
  });

  group("LynxBundleUpdater", () {
    test("首次装载：网络下载 + md5 校验通过，来源 network，缓存落盘", () async {
      final realMd5 = md5HexDigest(bundleBytes);
      servedManifest["md5"] = realMd5;
      final updater = LynxBundleUpdater();
      final result = await updater.resolve(
        manifestUrl: manifestUrl,
        builtinBytes: Uint8List.fromList([1, 2, 3]),
        cacheDirectory: cacheDirectory,
      );
      expect(result.source, LynxBundleSource.network);
      expect(result.version, "5");
      expect(result.bytes, bundleBytes);
      expect(result.error, isNull);
      // 缓存与元数据落盘
      expect(
        File("$cacheDirectory/main.lynx.bundle").readAsBytesSync(),
        bundleBytes,
      );
      expect(
        jsonDecode(
          File("$cacheDirectory/main.lynx.bundle.meta").readAsStringSync(),
        )["version"],
        "5",
      );
    });

    test("二次装载：版本一致走缓存，不再发起 bundle 下载", () async {
      servedManifest["md5"] = md5HexDigest(bundleBytes);
      final updater = LynxBundleUpdater();
      // 首次：建立缓存
      await updater.resolve(
        manifestUrl: manifestUrl,
        builtinBytes: Uint8List.fromList([9]),
        cacheDirectory: cacheDirectory,
      );
      final downloadsBefore = bundleRequests;
      // 关闭 bundle 下载通道：若实现错误再次发起下载会失败/回退
      serveBundleOk = false;
      final result = await updater.resolve(
        manifestUrl: manifestUrl,
        builtinBytes: Uint8List.fromList([9]),
        cacheDirectory: cacheDirectory,
      );
      expect(result.source, LynxBundleSource.cache);
      expect(result.bytes, bundleBytes);
      expect(bundleRequests, downloadsBefore, reason: "缓存命中不应再次下载");
    });

    test("缓存 md5 损坏：判为缓存失效，重新下载修复", () async {
      servedManifest["md5"] = md5HexDigest(bundleBytes);
      final updater = LynxBundleUpdater();
      await updater.resolve(
        manifestUrl: manifestUrl,
        builtinBytes: Uint8List.fromList([9]),
        cacheDirectory: cacheDirectory,
      );
      // 篡改缓存内容（md5 不再匹配 manifest）
      File("$cacheDirectory/main.lynx.bundle").writeAsBytesSync([1, 1, 1]);
      final result = await updater.resolve(
        manifestUrl: manifestUrl,
        builtinBytes: Uint8List.fromList([9]),
        cacheDirectory: cacheDirectory,
      );
      serveBundleOk = true;
      expect(result.source, isNot(LynxBundleSource.builtin));
      expect(result.bytes, bundleBytes);
    });

    test("下载 md5 不匹配：回退内置，缓存不落盘", () async {
      servedManifest["md5"] = "a" * 32; // 与实际内容不符
      final updater = LynxBundleUpdater();
      final builtin = Uint8List.fromList([7, 7, 7]);
      final result = await updater.resolve(
        manifestUrl: manifestUrl,
        builtinBytes: builtin,
        cacheDirectory: cacheDirectory,
      );
      expect(result.source, LynxBundleSource.builtin);
      expect(result.bytes, builtin);
      expect(result.error, isNotNull);
      expect(File("$cacheDirectory/main.lynx.bundle").existsSync(), isFalse,
          reason: "校验失败的半截缓存不应落盘");
    });

    test("manifest 请求失败：回退内置", () async {
      serveManifestOk = false;
      final updater = LynxBundleUpdater();
      final builtin = Uint8List.fromList([5, 5]);
      final result = await updater.resolve(
        manifestUrl: manifestUrl,
        builtinBytes: builtin,
        cacheDirectory: cacheDirectory,
      );
      expect(result.source, LynxBundleSource.builtin);
      expect(result.bytes, builtin);
      expect(result.error, isNotNull);
    });

    test("manifest 格式非法（md5 缺失）：回退内置", () async {
      servedManifest = {"version": "5", "url": bundleUrl};
      final updater = LynxBundleUpdater();
      final builtin = Uint8List.fromList([5, 5]);
      final result = await updater.resolve(
        manifestUrl: manifestUrl,
        builtinBytes: builtin,
        cacheDirectory: cacheDirectory,
      );
      expect(result.source, LynxBundleSource.builtin);
      expect(result.bytes, builtin);
    });

    test("灰度 100%：设备吃 gray 版本（network + gray 通道标记）", () async {
      final realMd5 = md5HexDigest(bundleBytes);
      servedManifest = {
        "stable": {"version": "5", "url": bundleUrl, "md5": realMd5},
        "gray": {
          "version": "6",
          "url": bundleUrl,
          "md5": realMd5,
          "percent": 100,
        },
      };
      final updater = LynxBundleUpdater();
      final result = await updater.resolve(
        manifestUrl: manifestUrl,
        builtinBytes: Uint8List.fromList([9]),
        cacheDirectory: cacheDirectory,
        deviceId: "device-abc",
      );
      expect(result.source, LynxBundleSource.network);
      expect(result.version, "6");
      expect(result.channel, "gray");
    });

    test("灰度 0%：所有设备吃 stable 版本", () async {
      final realMd5 = md5HexDigest(bundleBytes);
      servedManifest = {
        "stable": {"version": "5", "url": bundleUrl, "md5": realMd5},
        "gray": {
          "version": "6",
          "url": bundleUrl,
          "md5": realMd5,
          "percent": 0,
        },
      };
      final updater = LynxBundleUpdater();
      final result = await updater.resolve(
        manifestUrl: manifestUrl,
        builtinBytes: Uint8List.fromList([9]),
        cacheDirectory: cacheDirectory,
        deviceId: "device-abc",
      );
      expect(result.version, "5");
      expect(result.channel, "stable");
    });

    test("设备分桶：同一 deviceId 结果恒定，值域 0-99", () {
      final a = LynxBundleUpdater.deviceBucket("device-abc");
      expect(a, LynxBundleUpdater.deviceBucket("device-abc"));
      expect(a, inInclusiveRange(0, 99));
      expect(
        LynxBundleUpdater.deviceBucket("device-xyz"),
        inInclusiveRange(0, 99),
      );
    });

    test("装载失败熔断：markLoadFailed 后本机回退内置，新版本号放行", () async {
      final realMd5 = md5HexDigest(bundleBytes);
      servedManifest = {
        "stable": {"version": "5", "url": bundleUrl, "md5": realMd5},
      };
      final updater = LynxBundleUpdater();
      final builtin = Uint8List.fromList([9]);
      final first = await updater.resolve(
        manifestUrl: manifestUrl,
        builtinBytes: builtin,
        cacheDirectory: cacheDirectory,
      );
      expect(first.source, LynxBundleSource.network);
      // 装载失败熔断 v5
      await updater.markLoadFailed(cacheDirectory: cacheDirectory, version: "5");
      final after = await updater.resolve(
        manifestUrl: manifestUrl,
        builtinBytes: builtin,
        cacheDirectory: cacheDirectory,
      );
      expect(after.source, LynxBundleSource.builtin);
      expect(after.bytes, builtin);
      // OSS 发布新版本 v6：熔断名单不阻塞新版本
      servedManifest = {
        "stable": {"version": "6", "url": bundleUrl, "md5": realMd5},
      };
      final recovered = await updater.resolve(
        manifestUrl: manifestUrl,
        builtinBytes: builtin,
        cacheDirectory: cacheDirectory,
      );
      expect(recovered.source, LynxBundleSource.network);
      expect(recovered.version, "6");
    });
  });
}

String md5HexDigest(List<int> bytes) => md5.convert(bytes).toString();
