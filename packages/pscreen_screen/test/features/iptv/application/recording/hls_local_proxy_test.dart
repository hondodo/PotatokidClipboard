import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/features/iptv/application/recording/hls_local_proxy.dart';

/// 假源站：一个本地 HttpServer，返回 HLS playlist 与分片，并统计请求次数。
class _FakeOrigin {
  int playlistHits = 0;
  final Map<String, int> segmentHits = <String, int>{};
  final List<String> segmentQuerySeen = <String>[];
  HttpServer? _server;
  late String baseUrl;
  String? playlistBody;

  /// 模拟带鉴权跳转的源：/live.m3u8 302 到 /real/live.m3u8?jsbt=<n>&jsbk=<sig>，
  /// 真实 playlist 用相对分片路径；签名每次递增。
  bool redirectMode = false;
  int _redirectSeq = 100;

  /// 前 N 次分片请求返回 500，用于验证预热失败后的有界重试。
  int failSegFirstN = 0;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    baseUrl = 'http://127.0.0.1:${_server!.port}';
    _server!.listen((req) async {
      final String path = req.uri.path;
      if (path == '/live.m3u8' && redirectMode) {
        playlistHits++;
        _redirectSeq++;
        final String sig = 'sig$_redirectSeq';
        req.response.statusCode = 302;
        req.response.headers.add(
          'location',
          '$baseUrl/real/live.m3u8?jsbt=$_redirectSeq&jsbk=$sig',
        );
        await req.response.close();
        return;
      }
      if (path == '/real/live.m3u8' && redirectMode) {
        // 相对分片路径，模拟广电源 gdxw/segment_N.ts
        final String body = '#EXTM3U\n#EXT-X-TARGETDURATION:2\n'
            '#EXTINF:2.0,\nseg/segment_1.ts\n'
            '#EXTINF:2.0,\nseg/segment_2.ts\n';
        req.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl');
        req.response.add(utf8.encode(body));
        await req.response.close();
        return;
      }
      if (path == '/live.m3u8') {
        playlistHits++;
        final String body = playlistBody ?? '#EXTM3U\n#EXT-X-TARGETDURATION:2\n'
            '#EXTINF:2.0,\n$baseUrl/seg1.ts\n'
            '#EXTINF:2.0,\nseg2.ts\n';
        req.response.headers.contentType = ContentType('application', 'vnd.apple.mpegurl');
        req.response.add(utf8.encode(body));
        await req.response.close();
        return;
      }
      if (path.startsWith('/seg') || path.startsWith('/real/seg')) {
        segmentHits[path] = (segmentHits[path] ?? 0) + 1;
        segmentQuerySeen.add(req.uri.query);
        if (failSegFirstN > 0) {
          failSegFirstN--;
          req.response.statusCode = 500;
          await req.response.close();
          return;
        }
        // 没有鉴权 query 就 404，模拟防盗链
        if (redirectMode && req.uri.query.isEmpty) {
          req.response.statusCode = 404;
          await req.response.close();
          return;
        }
        req.response.add(utf8.encode('TS-DATA-$path'));
        await req.response.close();
        return;
      }
      req.response.statusCode = 404;
      await req.response.close();
    });
  }

  Future<void> stop() async => _server?.close(force: true);
}

void main() {
  late _FakeOrigin origin;
  late HlsLocalProxy proxy;

  setUp(() async {
    origin = _FakeOrigin();
    await origin.start();
    proxy = HlsLocalProxy.instance;
    await proxy.stop();
    await proxy.ensureStarted();
    proxy.bind('${origin.baseUrl}/live.m3u8');
  });

  tearDown(() async {
    await proxy.stop();
    await origin.stop();
  });

  Future<String> getLocalPlaylist() async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest req = await client.getUrl(Uri.parse(proxy.playlistUrl));
      final HttpClientResponse res = await req.close();
      return await utf8.decoder.bind(res).join();
    } finally {
      client.close();
    }
  }

  Future<List<int>> fetchSegment(String url) async {
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest req = await client.getUrl(Uri.parse(url));
      final HttpClientResponse res = await req.close();
      return await res.toList().then((parts) => parts.expand((p) => p).toList());
    } finally {
      client.close();
    }
  }

  /// 等待后台预热把当前窗口的分片拉完（segmentHits 不再增长）。
  Future<void> waitWarmup(int expectedSegments) async {
    for (int i = 0;
        i < 30 && origin.segmentHits.length < expectedSegments;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  int totalSegmentHits() =>
      origin.segmentHits.values.fold(0, (int a, int b) => a + b);

  test('m3u8 分片 URL 被重写为本地地址', () async {
    final String body = await getLocalPlaylist();
    expect(body, contains('#EXTM3U'));
    expect(body, contains(proxy.playlistUrl.replaceFirst('/live.m3u8', '/seg/')));
    expect(body, isNot(contains('${origin.baseUrl}/seg1.ts')));
  });

  test('相对分片 URL 也按 base resolve 后重写', () async {
    final String body = await getLocalPlaylist();
    // seg2.ts 是相对路径，应被 resolve 成 origin base 再重写为本地 seg 行。
    final int segLines = body.split('\n').where((l) => l.trim().startsWith('http://127.0.0.1')).length;
    expect(segLines, 2);
  });

  test('分片缓存命中：重复请求同一分片不再回源', () async {
    final String body = await getLocalPlaylist();
    final String segUrl = body
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.startsWith('http://127.0.0.1') && l.contains('/seg/'));
    await waitWarmup(2);
    final int before = totalSegmentHits();

    await fetchSegment(segUrl);
    await fetchSegment(segUrl);
    await fetchSegment(segUrl);

    // 预热已把窗口分片拉进缓存，播放器请求不应再产生回源。
    expect(totalSegmentHits(), before);
  });

  test('预热：仅拉 playlist 未请求分片时，后台也会把窗口分片拉进缓存', () async {
    // 只拉 playlist，不主动请求任何分片。预热应把窗口的 2 片都拉下来。
    final String body = await getLocalPlaylist();
    final List<String> segUrls = body
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.startsWith('http://127.0.0.1') && l.contains('/seg/'))
        .toList();
    expect(segUrls.length, 2);

    // 预热是 fire-and-forget，轮询等它完成（最多 2s）。
    for (int i = 0; i < 20 && origin.segmentHits.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(origin.segmentHits.length, 2, reason: '窗口 2 片都应被预热');

    // 此时播放器再请求，应全部命中缓存，不再回源。
    final int hitsBefore = origin.segmentHits.values.fold(0, (a, b) => a + b);
    await fetchSegment(segUrls[0]);
    await fetchSegment(segUrls[1]);
    expect(origin.segmentHits.values.fold(0, (a, b) => a + b), hitsBefore);
  });

  test('playlist TTL：1 秒内重复请求只拉一次上游', () async {
    await getLocalPlaylist();
    await getLocalPlaylist();
    expect(origin.playlistHits, 1);
  });

  test('预热失败后有界重试：一次失败不会永久欠缓存，也不会无限重试', () async {
    // 首轮 2 片预热全部 500 失败；后续 playlist 重写时重试应成功。
    origin.failSegFirstN = 2;
    await getLocalPlaylist();

    // 等首轮预热失败落地：2 片各失败一次 = 2 次回源。
    for (int i = 0;
        i < 20 && origin.segmentHits.values.fold(0, (a, b) => a + b) < 2;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(origin.segmentHits.values.fold(0, (a, b) => a + b), 2);

    // 两次 playlist 重写触发重试（TTL 1s，间隔足够）。
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await getLocalPlaylist();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await getLocalPlaylist();
    // 等重试预热完成。
    for (int i = 0;
        i < 20 &&
            origin.segmentHits.values.fold(0, (a, b) => a + b) < 4;
        i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    // 2 片各失败一次再成功一次 = 4 次回源；成功后进缓存不再增长。
    final int afterRetry = origin.segmentHits.values.fold(0, (a, b) => a + b);
    expect(afterRetry, 4, reason: '两片各失败一次、重试各成功一次');

    // 再拉两次 playlist 不应继续重试已缓存的片（无无限重试）。
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await getLocalPlaylist();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await getLocalPlaylist();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(origin.segmentHits.values.fold(0, (a, b) => a + b), afterRetry);
  });

  test('长窗口完整透传、不裁片，MEDIA-SEQUENCE 不变，ENDLIST 去掉', () async {
    final StringBuffer sb = StringBuffer('#EXTM3U\n#EXT-X-VERSION:3\n'
        '#EXT-X-TARGETDURATION:2\n#EXT-X-MEDIA-SEQUENCE:100\n');
    for (int i = 0; i < 20; i++) {
      sb.writeln('#EXTINF:2.0,');
      sb.writeln('${origin.baseUrl}/seg$i.ts');
    }
    sb.writeln('#EXT-X-ENDLIST');
    origin.playlistBody = sb.toString();

    final String body = await getLocalPlaylist();
    final List<String> lines = body.split('\n').map((String l) => l.trim()).toList();
    final int segCount = lines
        .where((String l) => l.startsWith('http://127.0.0.1') && l.contains('/seg/'))
        .length;
    // 2026-11-20：裁头是周期性卡顿根因，已移除；20 片必须原样全给播放器。
    expect(segCount, 20);
    expect(body, contains('#EXT-X-MEDIA-SEQUENCE:100')); // 不再前移
    expect(body, isNot(contains('#EXT-X-ENDLIST')));
    // 每片都要有自己的 #EXTINF，标签与 URL 不能错位。
    expect(lines.where((String l) => l.startsWith('#EXTINF')).length, 20);
  });

  test('短窗口也完整透传，不裁剪', () async {
    // setUp 的默认源就是 2 片。
    final String body = await getLocalPlaylist();
    final int segCount = body
        .split('\n')
        .map((String l) => l.trim())
        .where((String l) => l.startsWith('http://127.0.0.1') && l.contains('/seg/'))
        .length;
    expect(segCount, 2);
    expect(body, contains('#EXT-X-TARGETDURATION:2'));
  });

  test('302 跳转：用重定向后的 base 拼分片，且继承 jsbt/jsbk 鉴权', () async {
    origin.redirectMode = true;
    proxy.bind('${origin.baseUrl}/live.m3u8');

    final String body = await getLocalPlaylist();
    final String segUrl = body
        .split('\n')
        .map((String l) => l.trim())
        .firstWhere((String l) => l.startsWith('http://127.0.0.1') && l.contains('/seg/'));

    // 通过本地代理请求分片：代理应请求 /real/seg/segment_1.ts 并带上鉴权 query。
    await fetchSegment(segUrl);
    expect(origin.segmentHits.keys.any((String k) => k.startsWith('/real/seg/')), isTrue);
    expect(origin.segmentQuerySeen.any((String q) => q.contains('jsbt=') && q.contains('jsbk=')), isTrue);
    // 没有鉴权 query 的裸分片请求必须为 0（否则会 404）。
    expect(origin.segmentQuerySeen.where((String q) => q.isEmpty).length, 0);
  });

  test('签名刷新后同一分片 hash 稳定，缓存命中不重复回源', () async {
    origin.redirectMode = true;
    proxy.bind('${origin.baseUrl}/live.m3u8');

    final String firstBody = await getLocalPlaylist();
    await waitWarmup(2);
    final int beforeReload = totalSegmentHits();
    final String hash1 = firstBody
        .split('\n')
        .map((String l) => l.trim())
        .firstWhere((String l) => l.startsWith('http://127.0.0.1') && l.contains('/seg/'))
        .split('/seg/')
        .last;

    // 过期 TTL，触发重新拉 playlist（签名会递增、jsbt/jsbk 变化）。
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final String secondBody = await getLocalPlaylist();
    final String hash2 = secondBody
        .split('\n')
        .map((String l) => l.trim())
        .firstWhere((String l) => l.startsWith('http://127.0.0.1') && l.contains('/seg/'))
        .split('/seg/')
        .last;

    // 逻辑 key 与签名无关 → 同一个分片 hash 不变。
    expect(hash2, hash1);
    expect(origin.playlistHits, greaterThanOrEqualTo(2));

    // 签名刷新后同一分片 hash 不变 → 两次请求都命中缓存，不再回源。
    await fetchSegment(firstBody
        .split('\n')
        .map((String l) => l.trim())
        .firstWhere((String l) => l.startsWith('http://127.0.0.1') && l.contains('/seg/')));
    await fetchSegment(secondBody
        .split('\n')
        .map((String l) => l.trim())
        .firstWhere((String l) => l.startsWith('http://127.0.0.1') && l.contains('/seg/')));
    expect(totalSegmentHits(), beforeReload);
  });
}
