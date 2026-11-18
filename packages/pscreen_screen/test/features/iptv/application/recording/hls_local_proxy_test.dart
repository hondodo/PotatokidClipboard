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

  test('分片缓存命中：重复请求同一分片只回源一次', () async {
    final String body = await getLocalPlaylist();
    final String segUrl = body
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.startsWith('http://127.0.0.1') && l.contains('/seg/'));

    await fetchSegment(segUrl);
    await fetchSegment(segUrl);
    await fetchSegment(segUrl);

    expect(origin.segmentHits.values.fold(0, (a, b) => a + b), 1);
  });

  test('playlist TTL：1 秒内重复请求只拉一次上游', () async {
    await getLocalPlaylist();
    await getLocalPlaylist();
    expect(origin.playlistHits, 1);
  });

  test('长窗口只输出尾部 6 片，MEDIA-SEQUENCE 前移，ENDLIST 去掉', () async {
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
    expect(segCount, 6);
    expect(body, contains('#EXT-X-MEDIA-SEQUENCE:114')); // 100 + (20 - 6)
    expect(body, isNot(contains('#EXT-X-ENDLIST')));
    // 保留的每片都要有自己的 #EXTINF，标签与 URL 不能错位。
    expect(lines.where((String l) => l.startsWith('#EXTINF')).length, 6);
  });

  test('窗口不足 6 片时原样保留，不误裁启动期短列表', () async {
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

    // 两次请求同一本地分片 URL：结果都来自缓存，上游只回源一次。
    await fetchSegment(firstBody
        .split('\n')
        .map((String l) => l.trim())
        .firstWhere((String l) => l.startsWith('http://127.0.0.1') && l.contains('/seg/')));
    await fetchSegment(secondBody
        .split('\n')
        .map((String l) => l.trim())
        .firstWhere((String l) => l.startsWith('http://127.0.0.1') && l.contains('/seg/')));
    expect(origin.segmentHits.values.fold(0, (int a, int b) => a + b), 1);
  });
}
