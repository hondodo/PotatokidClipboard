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

  /// 窗口预热：每次重写 playlist 后，后台把窗口内尚未缓存的分片提前拉进来，
  /// 让播放器请求时直接命中本地缓存。没有它时，只有录制在顺带预热窗口
  /// （录制 poll 会拉全部落后分片）；不录制时缓存长期只有 4~5 片，播放器
  /// 按需单片回源，偶发网络抖动即表现为 1~2s 卡顿（2026-11-20 实测）。
  ///
  /// 预热失败静默（只记诊断日志），绝不影响播放；与播放器请求共享
  /// single-flight（_inflight），不会重复回源。
  ///
  /// 并发 4：单片 400KB 走公网要 1~2.5s，并发 2 的填充速率仅勉强跟上窗口
  /// 每 2s 进 1 片，一次抖动就欠账，cache 常年停在 5~7 填不满 8（11-20 实测）。
  static const int _warmupMaxConcurrent = 4;
  int _warmupRunning = 0;
  final List<MapEntry<String, String>> _warmupQueue = <MapEntry<String, String>>[];
  final Set<String> _warmupQueued = <String>{};
  /// 预热失败次数：同一片最多重试 [_warmupMaxRetries] 次，避免无限打上游；
  /// 滑出窗口后清理。播放器真要这片时仍会走 [_getSegment] 正常回源兜底，
  /// 所以放弃预热不影响播放。
  static const int _warmupMaxRetries = 2;
  final Map<String, int> _warmupFailCount = <String, int>{};

  // 历史背景：这里曾有 _playlistKeepSegments 把 relay 的 8 片窗口再裁到尾部 6 片，
  // 目的是压缩 mpv 重载时"从第一行重播"的回退量、并给录制留锚点。
  //
  // 2026-11-20 实测确认这是周期性卡顿的根因，已移除裁剪、完整透传 relay 窗口：
  // - relay 侧 LIVE_HIDE_TAIL=4 已把播放器放在产出边缘后方约 8s 吸收抖动，
  //   代理再掐头部等于双重压缩：窗口只剩 12s，播放器每隔 4s 贴到尾部等新片浮出，
  //   表现为 1.4~2.8s 周期性卡顿；
  // - A/B 验证：直连（无代理）不卡、保留代理但不裁剪（8片->8片）也不卡；
  // - "mpv 每次 open 都从第一行播"的假设未成立，实测不裁剪也没出现重复播放。
  //
  // 若将来重载回退确实困扰，应只在 reload 那一次给短窗口，不要全局裁剪——
  // singleReload 分支在 live_player_widget.dart 的 _openChannel(isReload) 有标记可复用。

  /// 动态签名参数：每次请求都会变（jsbt=时间戳、jsbk=签名、auth/token 等）。
  /// 这类参数不能进缓存 key，也不能用来生成 hash，否则签名一变缓存就永不命中、
  /// 本地分片 URL 每次都不同 → mpv 误判为全新分片、窗口乱跳、反复重载。
  static const Set<String> _authParamKeys = <String>{
    'jsbt',
    'jsbk',
    'auth',
    'token',
    'sign',
    'signature',
    't',
    'st',
    'ts',
    'time',
    'timestamp',
    'nonce',
    'key',
    'k',
    'e',
    'expires',
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
      _clearWarmup();
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
    _clearWarmup();
  }

  void _clearWarmup() {
    _warmupQueue.clear();
    _warmupQueued.clear();
    _warmupFailCount.clear();
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
    _clearWarmup();
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
        _diag(
          'variant redirect ${variant.host}${variant.path} -> '
          '${mediaBase.host}${mediaBase.path}',
        );
      }
    }

    final HlsPlaylist parsed = parsePlaylist(mediaText, mediaBase);
    // 完整透传上游窗口，不再裁头（详见 _playlistKeepSegments 移除说明）。
    // ENDLIST 由 _rewritePlaylist 顺手剔除，直播不能有。
    final String rewritten = _rewritePlaylist(mediaText, mediaBase);
    _pruneCache();
    // 后台预热窗口分片：播放器和录制都还没请求的片提前拉进缓存。
    // 不录制时这是唯一的热源，缺了它缓存长期 4~5 片、播放器按需回源易卡。
    final int queued = _warmupWindow();
    // 日志带上首末片的 f 序号：现场对比相邻两次即可判断窗口是否在前进，
    // 区分「播放器反复重载回放」与「上游窗口停滞导致真重复」。
    // warmup=本轮新入队的预热数；cache 稳定在窗口大小即说明预热生效。
    _diag(
      'playlist rewritten: ${parsed.segments.length}片 '
      'seq=${parsed.mediaSequence} '
      'first=${_segTag(parsed.segments.isEmpty ? null : parsed.segments.first)} '
      'last=${_segTag(parsed.segments.isEmpty ? null : parsed.segments.last)} '
      'base=${base.host}${base.path} cache=${_segmentCache.length} warmup=$queued',
    );
    return rewritten;
  }

  /// 从分片 URL 里取可辨认的序号：relay 的 `f=segNNNNN.ts` 或路径末段。
  static String _segTag(Uri? u) {
    if (u == null) return '-';
    return u.queryParameters['f'] ?? u.pathSegments.last;
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
      // 直播不能有 ENDLIST，否则播放器会当 VOD 播完即停。原先由
      // _trimPlaylistTail 顺手去掉；裁剪移除后在这里兜底。
      if (trimmed.toUpperCase().startsWith('#EXT-X-ENDLIST')) continue;
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
        .map((MapEntry<String, String> e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
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

  /// 后台预热当前窗口里尚未缓存的分片。
  ///
  /// - 只预热 [_activeHashes]（本窗口的 hash），不碰历史；
  /// - 已缓存或正在拉取（[_inflight]）的跳过 —— [_getSegment] 自身就会比对，
  ///   这里再显式判一次是为了少建 Future；
  /// - 并发上限 [_warmupMaxConcurrent]，避免和播放器/录制抢同一时刻的带宽；
  /// - 完全 fire-and-forget：失败静默、不触发熔断（预热失败不该让播放回退直连），
  ///   播放器真要这片时 [_getSegment] 仍会正常回源兜底。
  /// 返回本轮新入队的预热分片数（用于诊断日志）。
  int _warmupWindow() {
    // 滑出窗口的失败片清掉计数，允许它下次再进窗口时重新尝试。
    _warmupFailCount.removeWhere((String h, int _) => !_activeHashes.contains(h));
    if (!isUsable) return 0;
    final List<MapEntry<String, String>> pending = <MapEntry<String, String>>[];
    for (final String hash in _activeHashes) {
      if (_segmentCache.containsKey(hash) ||
          _inflight.containsKey(hash) ||
          _warmupQueued.contains(hash) ||
          (_warmupFailCount[hash] ?? 0) >= _warmupMaxRetries) {
        continue;
      }
      final String? url = _hashToUrl[hash];
      if (url != null) pending.add(MapEntry<String, String>(hash, url));
    }
    if (pending.isEmpty) return 0;
    // 从窗口尾部往回预热：播放器最可能先要新片，优先填尾部。
    pending.sort((MapEntry<String, String> a, MapEntry<String, String> b) =>
        _segTag(Uri.parse(b.value)).compareTo(_segTag(Uri.parse(a.value))));
    for (final MapEntry<String, String> e in pending) {
      _warmupQueue.add(e);
      _warmupQueued.add(e.key);
    }
    _pumpWarmup();
    return pending.length;
  }

  /// 按并发上限消费预热队列。
  void _pumpWarmup() {
    while (_warmupRunning < _warmupMaxConcurrent && _warmupQueue.isNotEmpty) {
      final MapEntry<String, String> e = _warmupQueue.removeAt(0);
      _warmupQueued.remove(e.key);
      // 入队到出队间可能已被播放器/录制拉到，复查一次。
      if (_segmentCache.containsKey(e.key) || _inflight.containsKey(e.key)) continue;
      // 出队时重新取最新签名 URL：排队期间 playlist 可能已刷新多次，
      // 入队时记下的 e.value 签名可能已过期导致 403/404（实测隐患）。
      final String? freshUrl = _hashToUrl[e.key];
      final String fetchUrl = freshUrl ?? e.value;
      _warmupRunning++;
      unawaited(
        _getSegment(e.key, fetchUrl).then(
          (Object? _) {},
          onError: (Object error) {
            // 预热失败只记日志，绝不 _recordFailure：不能因预热失败让播放降级。
            // 有界重试：累计到上限才放弃本窗口，避免一次性失败就永久欠缓存，
            // 又不会每次重写都重试同一片打爆上游。
            final int count = (_warmupFailCount[e.key] ?? 0) + 1;
            _warmupFailCount[e.key] = count;
            _diag('warmup failed($count/${_warmupMaxRetries}) '
                'seg=${_segTag(Uri.parse(fetchUrl))}: $error');
          },
        ).whenComplete(() {
          _warmupRunning--;
          _pumpWarmup();
        }),
      );
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
