import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:pscreen_screen/features/iptv/application/recording/hls_playlist.dart';

/// 一次 playlist 拉取的结果：[text] 是响应体，[realUri] 是 Dio 跟随 302
/// 之后的最终地址。带鉴权跳转的源（如广电源 302 到带 jsbt/jsbk 的地址）
/// 必须以 [realUri] 作 base 拼分片，否则分片会落在跳转前的域名上导致 404。
class _FetchedPlaylist {
  const _FetchedPlaylist(this.text, this.realUri);
  final String text;
  final Uri realUri;
}

/// App 进程内的 HLS 本地代理（纯 Dart，无原生依赖）。
///
/// 定位：**不是**云端 relay 的替代品。relay（`.env` 的 `REPLY_SOURCE`）是特定
/// 链接的必经可达通道，改写仍发生在播放器入口之前、原样保留。本代理只面对
/// 「已经确定下来的最终地址」（relay 地址或原始地址），做一件事：
/// **对上游拉一次，缓存分片，再分发给播放器和录制** —— 把原本的两路外网
/// （播放器一路 + 录制一路）合并成一路，消除录制时的带宽争用卡顿。
///
/// 工作模型：
/// - `bind(finalUrl)` 在播放器 open 前调用，设置上游最终地址并清空缓存；
/// - 播放器 `open(playlistUrl)`（本地地址 http://127.0.0.1:PORT/live.m3u8）；
/// - 录制 controller 的 fetch 也指向本代理；
/// - m3u8 里的分片 URL 被重写成本地 `seg/<md5(归一化后的分片URL)>`，
///   播放器与录制请求同一分片时命中同一缓存条目；
/// - single-flight：同一分片的并发请求合并为一个上游请求；
/// - 缓存按当前 m3u8 窗口修剪，避免无限增长。
///
/// 带鉴权跳转的源（广电源等）：上游 m3u8 会 302 到带 jsbt/jsbk 签名的新地址，
/// 且每次跳转的 IP/签名都不同。代理用 Dio 跟随后的 [Response.realUri] 作 base
/// 拼分片，并把鉴权参数继承到分片 URL；缓存 key/hash 会剔除动态签名参数，
/// 保证同一分片跨签名命中同一条目、本地 URL 不随签名变化。
///
/// 失败降级：任何启动/拉流异常都不向上传播——调用方回退直连原地址，
/// 保证"代理坏了也不影响播放"。
class HlsLocalProxy {
  HlsLocalProxy._();

  static final HlsLocalProxy instance = HlsLocalProxy._();

  /// 诊断日志回调；未设置时回落 dart:developer.log。
  void Function(String message)? onDiagnostic;

  void _diag(String message) {
    final String line = '[HlsProxy] $message';
    final void Function(String message)? sink = onDiagnostic;
    if (sink != null) {
      sink(line);
      return;
    }
    developer.log(line, name: 'HlsProxy');
  }

  HttpServer? _server;
  int _port = 0;

  /// 当前上游最终地址（relay 改写后的地址，或直连的原始地址）。
  String? _upstream;
  Uri? _upstreamUri;

  /// 分片缓存：key = 逻辑 key（剔除动态签名），value = 字节。
  final LinkedHashMap<String, List<int>> _segmentCache = LinkedHashMap<String, List<int>>();

  /// hash(逻辑 key) → 上游分片「实际可访问 URL」（含当次签名）的登记。
  /// 每次重写 playlist 都会刷新为最新签名 URL，播放器拿到的本地 hash 不变。
  final Map<String, String> _hashToUrl = <String, String>{};

  /// single-flight：同一逻辑分片的并发拉取合并。
  final Map<String, Future<List<int>>> _inflight = <String, Future<List<int>>>{};

  /// 当前窗口里所有分片的逻辑 key（重写 playlist 时重建），用于修剪缓存。
  Set<String> _activeHashes = <String>{};

  /// playlist 拉取的短 TTL 缓存：播放器与录制在 1 秒内的重复请求只拉一次上游。
  DateTime? _playlistAt;
  String? _playlistText;
  Future<String>? _playlistInflight;
  static const Duration _playlistTtl = Duration(seconds: 1);

  /// 连续失败熔断：达到阈值后 [isUsable] 转 false，调用方回退直连。
  int _consecutiveFailures = 0;
  static const int _maxFailures = 3;

  /// 交给播放器的 playlist 只保留尾部这些分片。
  ///
  /// mpv 每次 open / 看门狗重载都会从 m3u8 第一行开始播。上游窗口再短也有
  /// 十几秒历史，反复重载时用户看到的就是"同一段一直重复"。裁到尾部几片
  /// 把回退压到几秒，重载后几乎无感。录制侧也读同一份裁剪后的列表——
  /// poll 间隔 = targetDuration(2s)，尾部 6 片足够锚点不滑出。
  static const int _playlistKeepSegments = 6;

  /// 动态签名参数：每次请求都会变（jsbt=时间戳、jsbk=签名、auth/token 等）。
  /// 这类参数不能进缓存 key，也不能用来生成 hash，否则签名一变缓存就永不命中、
  /// 本地分片 URL 每次都不同 → mpv 误判为全新分片、窗口乱跳、反复重载。
  static const Set<String> _authParamKeys = <String>{
    'jsbt', 'jsbk', 'auth', 'token', 'sign', 'signature',
    't', 'st', 'ts', 'time', 'timestamp', 'nonce', 'key', 'k', 'e', 'expires',
  };

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 60),
      headers: const <String, dynamic>{'accept-encoding': 'identity'},
    ),
  );

  bool get isRunning => _server != null;
  bool get isUsable => isRunning && _upstream != null && _consecutiveFailures < _maxFailures;

  /// 本地播放列表地址（交给播放器 open）。
  String get playlistUrl => 'http://127.0.0.1:$_port/live.m3u8';

  /// 本地分片地址前缀（重写 m3u8 的分片行时使用）。
  String get _segmentBaseUrl => 'http://127.0.0.1:$_port/seg/';

  /// 启动进程内 HTTP 服务（幂等）。失败返回 false，调用方应回退直连。
  Future<bool> ensureStarted() async {
    if (_server != null) return true;
    try {
      final HttpServer server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _server = server;
      _port = server.port;
      server.listen(_handleRequest, onError: (Object e) => _diag('server error: $e'));
      _diag('started at $playlistUrl');
      return true;
    } catch (e) {
      _diag('start failed: $e');
      return false;
    }
  }

  /// 供播放器入口调用：确保服务已启动并绑定上游最终地址。
  ///
  /// 返回播放器应 open 的地址 —— 代理可用时是本地 `playlistUrl`，
  /// 否则原样返回 [finalUrl]（回退直连，不影响播放）。
  Future<String> prepare(String finalUrl) async {
    final bool ok = await ensureStarted();
    if (!ok) return finalUrl;
    bind(finalUrl);
    return playlistUrl;
  }

  /// 绑定上游最终地址。每次播放器 open 新源时调用，源变化时清空缓存。
  void bind(String finalUrl) {
    final bool changed = _upstream != finalUrl;
    _upstream = finalUrl;
    _upstreamUri = Uri.tryParse(finalUrl);
    _consecutiveFailures = 0;
    _playlistAt = null;
    _playlistText = null;
    if (changed) {
      _segmentCache.clear();
      _hashToUrl.clear();
      _inflight.clear();
      _activeHashes = <String>{};
      _diag('bind upstream=$finalUrl (cache cleared)');
    }
  }

  /// 清空缓存但保留服务与上游（用于同源 reload）。
  void invalidate() {
    _playlistAt = null;
    _playlistText = null;
    _segmentCache.clear();
    _hashToUrl.clear();
    _inflight.clear();
  }

  /// 停止服务（应用退出时调用）。
  Future<void> stop() async {
    final HttpServer? server = _server;
    _server = null;
    _upstream = null;
    _upstreamUri = null;
    _segmentCache.clear();
    _hashToUrl.clear();
    _inflight.clear();
    _playlistAt = null;
    _playlistText = null;
    if (server != null) {
      try {
        await server.close(force: true);
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // 录制侧 fetch（注入到 RecordingController）
  // ---------------------------------------------------------------------------

  /// 录制拉 playlist：走代理上游 + 重写。
  /// 代理不可用时回退直连传入的 [url]（改写前原始地址，保持旧行为）。
  Future<String> fetchPlaylistText(Uri url) async {
    if (!isUsable) return _defaultText(url);
    try {
      return await _getPlaylistText();
    } catch (e) {
      _recordFailure();
      _diag('fetchPlaylistText failed: $e');
      return _defaultText(url);
    }
  }

  /// 录制拉分片：传入的是代理重写后的本地 URL，命中缓存直接返回。
  /// 解析不出上游时回退直连传入 URL。
  Future<List<int>> fetchSegmentBytes(Uri url) async {
    final String? hash = _localSegmentHash(url);
    final String? upstream = _decodeLocalSegmentUrl(url);
    if (!isUsable || hash == null || upstream == null) return _defaultBytes(url);
    try {
      return await _getSegment(hash, upstream);
    } catch (e) {
      _recordFailure();
      _diag('fetchSegmentBytes failed: $e');
      return _defaultBytes(Uri.parse(upstream));
    }
  }

  Future<String> _defaultText(Uri url) async {
    final Response<String> r = await _dio.get<String>(
      url.toString(),
      options: Options(responseType: ResponseType.plain),
    );
    return r.data ?? '';
  }

  /// 拉 playlist 并记住 Dio 跟随 302 后的最终地址。
  /// [Response.realUri] 是重定向后的真实 URI，用它作 base 才能正确拼分片。
  Future<_FetchedPlaylist> _fetchPlaylistWithRealUri(Uri url) async {
    final Response<String> r = await _dio.get<String>(
      url.toString(),
      options: Options(responseType: ResponseType.plain),
    );
    return _FetchedPlaylist(r.data ?? '', r.realUri);
  }

  Future<List<int>> _defaultBytes(Uri url) async {
    final Response<List<int>> r = await _dio.get<List<int>>(
      url.toString(),
      options: Options(responseType: ResponseType.bytes),
    );
    return r.data ?? const <int>[];
  }

  // ---------------------------------------------------------------------------
  // HTTP 请求处理（播放器）
  // ---------------------------------------------------------------------------

  Future<void> _handleRequest(HttpRequest req) async {
    final HttpResponse res = req.response;
    try {
      final String path = req.uri.path;
      if (path == '/live.m3u8') {
        if (!isUsable) {
          res.statusCode = 503;
          await res.close();
          return;
        }
        final String text = await _getPlaylistText();
        final List<int> bytes = utf8.encode(text);
        res.headers.contentType = ContentType('application', 'vnd.apple.mpegurl', charset: 'utf-8');
        res.headers.add('Cache-Control', 'no-store');
        res.contentLength = bytes.length;
        res.add(bytes);
        await res.close();
        return;
      }
      if (path.startsWith('/seg/')) {
        final String hash = path.substring('/seg/'.length);
        final String? upstream = _hashToUrl[hash];
        if (upstream == null || !isUsable) {
          res.statusCode = 404;
          await res.close();
          return;
        }
        final List<int> bytes = await _getSegment(hash, upstream);
        res.headers.contentType = ContentType('video', 'mp2t');
        res.headers.add('Cache-Control', 'public, max-age=3600');
        res.contentLength = bytes.length;
        res.add(bytes);
        await res.close();
        return;
      }
      res.statusCode = 404;
      await res.close();
    } catch (e) {
      _recordFailure();
      _diag('request ${req.uri} failed: $e');
      try {
        res.statusCode = 502;
        await res.close();
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // playlist 拉取与重写
  // ---------------------------------------------------------------------------

  Future<String> _getPlaylistText() async {
    final DateTime? at = _playlistAt;
    final String? cached = _playlistText;
    if (cached != null && at != null && DateTime.now().difference(at) < _playlistTtl) {
      return cached;
    }
    final Future<String>? flying = _playlistInflight;
    if (flying != null) return flying;

    final Future<String> job = _fetchAndRewritePlaylist();
    _playlistInflight = job;
    try {
      final String text = await job;
      _playlistText = text;
      _playlistAt = DateTime.now();
      _consecutiveFailures = 0;
      return text;
    } finally {
      _playlistInflight = null;
    }
  }

  Future<String> _fetchAndRewritePlaylist() async {
    final Uri configured = _upstreamUri!;
    // 用重定向后的真实地址作 base。广电源会 302 到另一 IP + 动态签名，
    // 若用配置地址拼分片会落到错误域名 → 全部 404。
    final _FetchedPlaylist firstFetch = await _fetchPlaylistWithRealUri(configured);
    final Uri base = firstFetch.realUri;
    if (base != configured) {
      _diag('redirect ${configured.host}${configured.path} -> ${base.host}${base.path}');
    }
    final String original = firstFetch.text;
    final HlsPlaylist first = parsePlaylist(original, base);

    Uri mediaBase = base;
    String mediaText = original;
    if (first.isMaster) {
      // master：展开到选定码率分支（当前口径 = 最低码率，与录制既有逻辑一致）。
      // 分支地址用重定向后的 base resolve；分支本身也可能再 302。
      final Uri variant = first.selectedVariantUrl;
      final _FetchedPlaylist variantFetch = await _fetchPlaylistWithRealUri(variant);
      mediaBase = variantFetch.realUri;
      mediaText = variantFetch.text;
      if (mediaBase != variant) {
        _diag('variant redirect ${variant.host}${variant.path} -> '
            '${mediaBase.host}${mediaBase.path}');
      }
    }

    final HlsPlaylist before = parsePlaylist(mediaText, mediaBase);
    final String trimmed = _trimPlaylistTail(mediaText);
    final String rewritten = _rewritePlaylist(trimmed, mediaBase);
    final HlsPlaylist after = parsePlaylist(trimmed, mediaBase);
    _pruneCache();
    // 日志带上首末片的 f 序号：现场对比相邻两次即可判断窗口是否在前进，
    // 区分「播放器反复重载回放」与「上游窗口停滞导致真重复」。
    _diag('playlist rewritten: ${before.segments.length}片 -> ${after.segments.length}片 '
        'seq=${before.mediaSequence}->${after.mediaSequence} '
        'first=${_segTag(after.segments.isEmpty ? null : after.segments.first)} '
        'last=${_segTag(after.segments.isEmpty ? null : after.segments.last)} '
        'base=${base.host}${base.path} cache=${_segmentCache.length}');
    return rewritten;
  }

  /// 从分片 URL 里取可辨认的序号：relay 的 `f=segNNNNN.ts` 或路径末段。
  static String _segTag(Uri? u) {
    if (u == null) return '-';
    return u.queryParameters['f'] ?? u.pathSegments.last;
  }

  /// 裁掉 playlist 头部的历史分片，只留尾部 [_playlistKeepSegments] 片。
  ///
  /// 每片的伴随标签（#EXTINF 等）随片一起保留；全局标签里
  /// `#EXT-X-MEDIA-SEQUENCE` 按被裁掉的数量前移，`#EXT-X-ENDLIST` 去掉
  /// （直播不能有）。分片数不足时原样返回，不破坏启动期的短窗口。
  String _trimPlaylistTail(String text) {
    final List<String> lines = text.split(RegExp(r'\r?\n'));
    final List<int> uriIdx = <int>[];
    for (int i = 0; i < lines.length; i++) {
      final String t = lines[i].trim();
      if (t.isNotEmpty && !t.startsWith('#')) uriIdx.add(i);
    }
    if (uriIdx.length <= _playlistKeepSegments) return text;

    final int cut = uriIdx.length - _playlistKeepSegments;
    final int firstKeepUri = uriIdx[cut];
    // 从第一片保留分片往前，把它自己的 #EXTINF 等标签收进来；
    // 上一个 URI 行是天然边界，不会吃到全局标签。
    int bodyStart = firstKeepUri;
    while (bodyStart > 0 && lines[bodyStart - 1].trim().startsWith('#')) {
      bodyStart--;
    }

    // 头部只保留全局标签；#EXTINF / #EXT-X-KEY 等属于第一片的伴随标签，
    // 必须随 body 走，否则会留下无主标签让 mpv 的 EXTINF↔URI 配对错位。
    const List<String> globalTags = <String>[
      '#EXTM3U',
      '#EXT-X-VERSION',
      '#EXT-X-TARGETDURATION',
      '#EXT-X-PLAYLIST-TYPE',
      '#EXT-X-INDEPENDENT-SEGMENTS',
      '#EXT-X-I-FRAMES-ONLY',
      '#EXT-X-START',
      '#EXT-X-ALLOW-CACHE',
      '#EXT-X-DISCONTINUITY-SEQUENCE',
      '#EXT-X-KEY',
    ];
    final int headEnd = uriIdx.first;
    int sequence = 0;
    final List<String> head = <String>[];
    for (int i = 0; i < headEnd; i++) {
      final String t = lines[i].trim();
      if (t.isEmpty) continue;
      final String upper = t.toUpperCase();
      if (upper.startsWith('#EXT-X-ENDLIST')) continue;
      if (upper.startsWith('#EXT-X-MEDIA-SEQUENCE')) {
        sequence = int.tryParse(t.substring(t.lastIndexOf(':') + 1).trim()) ?? 0;
        continue; // 下面按裁剪后的起点重算
      }
      if (upper.startsWith('#') && !globalTags.any(upper.startsWith)) continue;
      head.add(lines[i]);
    }
    int insertAt = 1; // 默认跟在 #EXTM3U 后面
    for (int i = 0; i < head.length; i++) {
      if (head[i].trim().toUpperCase().startsWith('#EXT-X-TARGETDURATION')) {
        insertAt = i + 1;
        break;
      }
    }
    head.insert(
      insertAt.clamp(0, head.length),
      '#EXT-X-MEDIA-SEQUENCE:${sequence + cut}',
    );

    final List<String> tail = lines
        .sublist(bodyStart)
        .where((String l) => !l.trim().toUpperCase().startsWith('#EXT-X-ENDLIST'))
        .toList();
    final List<String> out = <String>[...head, ...tail];
    return '${out.join('\n')}\n';
  }

  /// 把 m3u8 里的分片 URL 重写为本地 seg URL 并登记 hash→上游，其他行原样保留。
  ///
  /// [base] 必须是重定向后的真实地址（见 [_fetchAndRewritePlaylist]）。分片的
  /// 逻辑身份用 [_logicalSegmentKey] 算（剔除动态签名 + 重定向 IP），hash 稳定；
  /// 实际抓取 URL 用 base resolve 后再继承 base 上的鉴权参数，保证能取到字节。
  String _rewritePlaylist(String text, Uri base) {
    final StringBuffer out = StringBuffer();
    final Set<String> active = <String>{};
    final String configured = _upstream ?? '';
    for (final String raw in text.split(RegExp(r'\r?\n'))) {
      final String line = raw.trimRight();
      final String trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        out.writeln(line);
        continue;
      }
      // 逻辑 key：基于「原始分片行 + 绑定地址」，与重定向 IP / 动态签名无关。
      // 这样源每次刷新换了签名或 GSLB IP，同一分片的 hash 仍不变——否则
      // 播放器会把它当成全新分片反复重载，就是之前"一直重复"的根源。
      final String logical = '$configured|$trimmed';
      final String hash = md5.convert(utf8.encode(logical)).toString();
      // 实际可访问 URL：用重定向后的 base 拼相对路径。
      Uri abs = base.resolve(trimmed);
      abs = _withAuthQuery(abs, base);
      _hashToUrl[hash] = abs.toString();
      active.add(hash);
      out.writeln('$_segmentBaseUrl$hash');
    }
    _activeHashes = active;
    return out.toString();
  }

  /// 把 [base] 上的鉴权类 query（jsbt/jsbk/auth/token…）继承到分片 URL。
  /// 分片自带同名参数时不覆盖（relay 的 t/sid/f 是它自己的，不能被污染）。
  static Uri _withAuthQuery(Uri segment, Uri base) {
    if (base.query.isEmpty) return segment;
    final Map<String, String> existing = segment.queryParameters;
    final Map<String, String> add = <String, String>{};
    base.queryParameters.forEach((String k, String v) {
      if (_authParamKeys.contains(k.toLowerCase()) && !existing.containsKey(k)) {
        add[k] = v;
      }
    });
    if (add.isEmpty) return segment;
    final Map<String, String> merged = <String, String>{...existing, ...add};
    final String query = merged.entries
        .map((MapEntry<String, String> e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return segment.replace(query: query);
  }

  // ---------------------------------------------------------------------------
  // 分片缓存
  // ---------------------------------------------------------------------------

  /// 拉分片。[cacheKey] 是稳定 hash（缓存/single-flight 用它），
  /// [fetchUrl] 是当次实际可访问 URL（含最新签名，用它请求上游）。
  /// 两者分离：签名刷新后 fetchUrl 变但 cacheKey 不变，命中同一缓存条目。
  Future<List<int>> _getSegment(String cacheKey, String fetchUrl) async {
    final List<int>? cached = _segmentCache[cacheKey];
    if (cached != null) return cached;

    final Future<List<int>>? flying = _inflight[cacheKey];
    if (flying != null) return flying;

    final Future<List<int>> job = _defaultBytes(Uri.parse(fetchUrl));
    _inflight[cacheKey] = job;
    try {
      final List<int> bytes = await job;
      _segmentCache[cacheKey] = bytes;
      _consecutiveFailures = 0;
      return bytes;
    } finally {
      _inflight.remove(cacheKey);
    }
  }

  /// 只保留当前窗口内的分片，外加 4 个冗余容忍窗口滑动边界。
  /// 缓存 key 已是逻辑 hash（见 [_rewritePlaylist]），直接用 [_activeHashes] 比对。
  void _pruneCache() {
    if (_segmentCache.isEmpty) return;
    final Set<String> keep = _activeHashes;
    final List<String> stale = _segmentCache.keys.where((String k) => !keep.contains(k)).toList();
    for (final String k in stale) {
      // 保留最近滑出窗口的 4 条，防止 mpv 回看。
      if (_segmentCache.length - stale.indexOf(k) - 1 < 4) continue;
      _segmentCache.remove(k);
    }
  }

  void _recordFailure() {
    _consecutiveFailures += 1;
    if (_consecutiveFailures == _maxFailures) {
      _diag('consecutive failures=$_consecutiveFailures, degrade to direct');
    }
  }

  // ---------------------------------------------------------------------------
  // 本地 seg URL 编解码
  // ---------------------------------------------------------------------------

  /// 从本地 seg URL 取 hash（`127.0.0.1:port/seg/<hash>`）；非本地返回 null。
  static String? _localSegmentHash(Uri url) {
    final String raw = url.toString();
    if (!raw.contains('127.0.0.1') && !raw.contains('localhost')) return null;
    final String path = url.path;
    if (!path.startsWith('/seg/')) return null;
    final String hash = path.substring('/seg/'.length);
    return hash.isEmpty ? null : hash;
  }

  /// 从本地 seg URL 解析出上游分片地址；非本地 URL 原样返回（直连兜底）。
  String? _decodeLocalSegmentUrl(Uri url) {
    final String? hash = _localSegmentHash(url);
    if (hash != null) return _hashToUrl[hash];
    // 非本地 URL 直接作为上游地址（录制直连兜底）。
    final String raw = url.toString();
    if (raw.contains('127.0.0.1') || raw.contains('localhost')) return null;
    return raw;
  }
}
