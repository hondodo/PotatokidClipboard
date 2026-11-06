import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/core/update/app_update_cache.dart';
import 'package:pscreen_screen/core/update/app_update_downloader.dart';
import 'package:pscreen_screen/core/update/app_update_models.dart';

Future<HttpServer> _serve(Uint8List full) async {
  final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((HttpRequest request) {
    final String? range = request.headers.value(HttpHeaders.rangeHeader);
    if (range != null) {
      final int start = int.parse(range.replaceAll('bytes=', '').split('-').first);
      final Uint8List rest = Uint8List.sublistView(full, start);
      request.response
        ..statusCode = HttpStatus.partialContent
        ..headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-${full.length - 1}/${full.length}',
        )
        ..contentLength = rest.length
        ..add(rest)
        ..close();
      return;
    }
    request.response
      ..contentLength = full.length
      ..add(full)
      ..close();
  });
  return server;
}

AppUpdateCheckResult _result(String url, int size, String sha) => AppUpdateCheckResult(
      appId: 'potatokid-tv',
      platform: 'apk',
      currentVersion: '1.0.0',
      currentBuild: 1,
      hasUpdate: true,
      forceUpdate: false,
      latest: const AppUpdateRelease(
        releaseId: 'rel_test',
        version: '1.0.1',
        build: 2,
        distribution: 'file',
        fileAvailable: true,
      ),
      download: AppUpdateDownload(
        url: url,
        size: size,
        sha256: sha,
        filename: 'update.apk',
      ),
    );

void main() {
  test('配置限速后平均速率受控', () async {
    final Directory tmp = await Directory.systemTemp.createTemp('pk_update_throttle_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    final Uint8List full = Uint8List.fromList(
      List<int>.generate(256 * 1024, (int i) => i % 251),
    );
    final String sha = sha256.convert(full).toString();
    final HttpServer server = await _serve(full);
    addTearDown(() => server.close(force: true));

    final AppUpdateCache cache = AppUpdateCache(tmp);
    final AppUpdateDownloader downloader =
        AppUpdateDownloader(maxBytesPerSecond: 256 * 1024);

    final Stopwatch watch = Stopwatch()..start();
    await downloader.download(
      appId: 'potatokid-tv',
      result: _result('http://127.0.0.1:${server.port}/update.apk', full.length, sha),
      cache: cache,
      onProgress: (int received, int total) {},
    );
    watch.stop();

    // 256 KiB / 256 KiB/s 理论约 1000ms；40ms 粒度允许少量误差。
    expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(700));
  });

  test('续传时限速按本次连接字节计算，不因历史字节长时间休眠', () async {
    final Directory tmp = await Directory.systemTemp.createTemp('pk_update_resume_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    const int existingSize = 2 * 1024 * 1024;
    const int restSize = 64 * 1024;
    final Uint8List full = Uint8List.fromList(
      List<int>.generate(existingSize + restSize, (int i) => i % 251),
    );
    final String sha = sha256.convert(full).toString();
    final HttpServer server = await _serve(full);
    addTearDown(() => server.close(force: true));

    final AppUpdateCache cache = AppUpdateCache(tmp);
    final File part = cache.partFile(
      appId: 'potatokid-tv',
      releaseId: 'rel_test',
      sha256: sha,
    );
    part.writeAsBytesSync(Uint8List.sublistView(full, 0, existingSize));

    final AppUpdateDownloader downloader =
        AppUpdateDownloader(maxBytesPerSecond: 1024 * 1024);

    final Stopwatch watch = Stopwatch()..start();
    await downloader.download(
      appId: 'potatokid-tv',
      result: _result('http://127.0.0.1:${server.port}/update.apk', full.length, sha),
      cache: cache,
      onProgress: (int received, int total) {},
    );
    watch.stop();

    // 旧实现会把 2MB 历史字节算进“落后”，在 1MiB/s 下额外睡约 2s；本次应只按 64KiB 计。
    expect(watch.elapsedMilliseconds, lessThan(600));
  });
}
