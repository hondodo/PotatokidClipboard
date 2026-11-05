import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/core/update/app_update_cache.dart';
import 'package:pscreen_screen/core/update/app_update_downloader.dart';
import 'package:pscreen_screen/core/update/app_update_models.dart';

Uint8List _payload(int length) =>
    Uint8List.fromList(List<int>.generate(length, (int i) => (i % 90) + 32));

String _sha(Uint8List bytes) => sha256.convert(bytes).toString();

AppUpdateCheckResult _resultFor(String url, {required int size, required String sha, String releaseId = 'rel_t'}) =>
    AppUpdateCheckResult.fromJson(
      <String, dynamic>{
        'code': 0,
        'data': <String, dynamic>{
          'app': 'potatokid-screen',
          'platform': 'apk',
          'hasUpdate': true,
          'forceUpdate': false,
          'current': <String, dynamic>{'version': '1.0.3', 'build': 8},
          'latest': <String, dynamic>{
            'releaseId': releaseId,
            'version': '1.0.4',
            'build': 9,
            'distribution': 'file',
            'fileAvailable': true,
          },
          'download': <String, dynamic>{
            'url': url,
            'size': size,
            'sha256': sha,
            'filename': 'app.apk',
            'expiresAt': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
          },
        },
      },
      appId: 'potatokid-screen',
      platform: 'apk',
    );

void main() {
  late Directory tmp;
  late AppUpdateCache cache;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('pk_update_dl_test_');
    cache = AppUpdateCache(tmp);
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('缓存复用：sha256 一致直接返回，不发起下载', () async {
    final Uint8List bytes = _payload(200);
    final String sha = _sha(bytes);
    final File file = cache.finalFile(appId: 'potatokid-screen', releaseId: 'rel_t', sha256: sha);
    file.writeAsBytesSync(bytes);

    // 用一个不可达的 URL：如果发生下载请求会报错，从而证明没有重复下载。
    final result = _resultFor('http://127.0.0.1:9/none.apk', size: bytes.length, sha: sha);
    final File out = await AppUpdateDownloader().download(
      appId: 'potatokid-screen',
      result: result,
      cache: cache,
      onProgress: (_, _) {},
    );
    expect(out.path, file.path);
    expect(await appCacheReady(cache, sha), isTrue);
  });

  test('缓存 sha 不一致 → 删除缓存并重下', () async {
    final Uint8List good = _payload(200);
    final String sha = _sha(good);
    cache.finalFile(appId: 'potatokid-screen', releaseId: 'rel_t', sha256: sha).writeAsBytesSync(Uint8List.fromList(<int>[1, 2, 3]));

    final HttpServer server = await _serve((HttpRequest req) {
      req.response.statusCode = 200;
      req.response.headers.contentType = ContentType.binary;
      req.response.add(good);
      return req.response.close();
    });
    addTearDown(() => server.close(force: true));

    final result = _resultFor('http://127.0.0.1:${server.port}/app.apk', size: good.length, sha: sha);
    final File out = await AppUpdateDownloader().download(
      appId: 'potatokid-screen',
      result: result,
      cache: cache,
      onProgress: (_, _) {},
    );
    expect(out.readAsBytesSync(), good);
    expect(await AppUpdateCache.sha256OfFile(out), sha);
  });

  test('Range 续传：已有 .part 时带 Range 头，服务端 206 只回剩余字节', () async {
    final Uint8List bytes = _payload(100);
    final String sha = _sha(bytes);
    final int split = 40;
    final File part = cache.partFile(appId: 'potatokid-screen', releaseId: 'rel_t', sha256: sha);
    part.writeAsBytesSync(bytes.sublist(0, split));

    final List<String> rangeHeaders = <String>[];
    final HttpServer server = await _serve((HttpRequest req) {
      rangeHeaders.add(req.headers.value(HttpHeaders.rangeHeader) ?? '');
      expect(req.headers.value(HttpHeaders.rangeHeader), 'bytes=$split-');
      expect(req.headers.value('accept-encoding'), 'identity');
      req.response.statusCode = HttpStatus.partialContent;
      req.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $split-${bytes.length - 1}/${bytes.length}');
      req.response.add(bytes.sublist(split));
      return req.response.close();
    });
    addTearDown(() => server.close(force: true));

    final result = _resultFor('http://127.0.0.1:${server.port}/app.apk', size: bytes.length, sha: sha);
    int lastReceived = 0;
    final File out = await AppUpdateDownloader().download(
      appId: 'potatokid-screen',
      result: result,
      cache: cache,
      onProgress: (int received, int total) => lastReceived = received,
    );
    expect(rangeHeaders.single, 'bytes=$split-');
    expect(out.readAsBytesSync(), bytes, reason: '续传不应重复写入已下载部分');
    expect(lastReceived, bytes.length);
  });

  test('服务端忽略 Range 返回 200 → 从头重写，不产生重复前缀', () async {
    final Uint8List bytes = _payload(80);
    final String sha = _sha(bytes);
    final File part = cache.partFile(appId: 'potatokid-screen', releaseId: 'rel_t', sha256: sha);
    part.writeAsBytesSync(bytes.sublist(0, 30));

    final HttpServer server = await _serve((HttpRequest req) {
      req.response.statusCode = 200;
      req.response.add(bytes);
      return req.response.close();
    });
    addTearDown(() => server.close(force: true));

    final result = _resultFor('http://127.0.0.1:${server.port}/app.apk', size: bytes.length, sha: sha);
    final File out = await AppUpdateDownloader().download(
      appId: 'potatokid-screen',
      result: result,
      cache: cache,
      onProgress: (_, _) {},
    );
    expect(out.readAsBytesSync(), bytes);
  });

  test('sha256 不一致 → 抛校验错误且删除半成品（下次重下）', () async {
    final Uint8List bytes = _payload(64);
    final HttpServer server = await _serve((HttpRequest req) {
      req.response.statusCode = 200;
      req.response.add(bytes);
      return req.response.close();
    });
    addTearDown(() => server.close(force: true));

    final result = _resultFor('http://127.0.0.1:${server.port}/app.apk', size: bytes.length, sha: 'deadbeef');
    await expectLater(
      AppUpdateDownloader().download(
        appId: 'potatokid-screen',
        result: result,
        cache: cache,
        onProgress: (_, _) {},
      ),
      throwsA(isA<AppUpdateShaMismatchException>()),
    );
    final File part = cache.partFile(appId: 'potatokid-screen', releaseId: 'rel_t', sha256: 'deadbeef');
    expect(part.existsSync(), isFalse);
  });

  test('410（安装包被清理 300008）→ 先重新取链，取不到再抛 needRenewUrl（可静默重试）', () async {
    int hits = 0;
    final Uint8List bytes = _payload(64);
    final HttpServer server = await _serve((HttpRequest req) {
      hits += 1;
      req.response.statusCode = HttpStatus.gone;
      req.response.write('{"code":300008}');
      return req.response.close();
    });
    addTearDown(() => server.close(force: true));

    final result = _resultFor('http://127.0.0.1:${server.port}/app.apk', size: bytes.length, sha: _sha(bytes));
    await expectLater(
      AppUpdateDownloader().download(
        appId: 'potatokid-screen',
        result: result,
        cache: cache,
        onProgress: (_, _) {},
        renewDownload: () async => null,
      ),
      throwsA(predicate((Object? e) => e is AppUpdateDownloadException && e.needRenewUrl)),
    );
    expect(hits, 1);
  });

  test('410 后重新取链成功 → 续传完成（不转阻断）', () async {
    final Uint8List bytes = _payload(64);
    final String sha = _sha(bytes);
    int hits = 0;
    final HttpServer server = await _serve((HttpRequest req) {
      hits += 1;
      if (hits == 1) {
        req.response.statusCode = HttpStatus.gone;
        req.response.write('{"code":300008}');
        return req.response.close();
      }
      final String? range = req.headers.value(HttpHeaders.rangeHeader);
      if (range != null && range.startsWith('bytes=')) {
        final int start = int.parse(range.substring(6, range.length - 1));
        req.response.statusCode = HttpStatus.partialContent;
        req.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes $start-${bytes.length - 1}/${bytes.length}');
        req.response.add(bytes.sublist(start));
      } else {
        req.response.statusCode = 200;
        req.response.add(bytes);
      }
      return req.response.close();
    });
    addTearDown(() => server.close(force: true));

    final result = _resultFor('http://127.0.0.1:${server.port}/app.apk', size: bytes.length, sha: sha);
    final File out = await AppUpdateDownloader().download(
      appId: 'potatokid-screen',
      result: result,
      cache: cache,
      onProgress: (_, _) {},
      renewDownload: () async => result.download,
    );
    expect(hits, 2);
    expect(out.readAsBytesSync(), bytes);
  });
}

Future<bool> appCacheReady(AppUpdateCache cache, String sha) =>
    cache.isReady(appId: 'potatokid-screen', releaseId: 'rel_t', sha256: sha);

Future<HttpServer> _serve(Future<void> Function(HttpRequest request) handler) async {
  final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((HttpRequest request) {
    handler(request);
  });
  return server;
}
