import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pscreen_screen/core/parental/parental_state_controller.dart';
import 'package:pscreen_screen/features/iptv/application/recording/hls_local_proxy.dart';
import 'package:pscreen_screen/features/iptv/application/recording/hls_playlist.dart';
import 'package:pscreen_screen/features/iptv/application/recording/recording_platform.dart';
import 'package:pscreen_screen/features/iptv/application/recording/recording_sink.dart';
import 'package:pscreen_screen/features/iptv/application/recording/recording_storage.dart';
import 'package:pscreen_screen/features/iptv/application/recording/stream_continuity_guard.dart';

/// 源上报来源：决定切源时录制如何处理（方案 D-11 / D-12 / D-13）。
enum RecordingSourceOrigin {
  /// 用户按左/右键手动切源 —— 录制中一律拦截。
  manual,

  /// 一级看门狗原地重载（同一 URL）—— 放行，录制继续。
  reload,

  /// 二级看门狗/失败重试真换源，或首次起播 —— 不拦截，停录保播放。
  auto,
}

/// 一次播放源上报（纯数据，可单测）。
///
/// [signature] 由「频道名 + 源索引 + 源列表」计算（D-6）：切源时 URL 可能因
/// 动态 token 变化，但源列表与索引稳定，signature 才不会误判。
class RecordingSource {
  RecordingSource({
    required this.channelName,
    required this.originalUrl,
    required this.sourceIndex,
    required this.sources,
    required this.origin,
  }) : signature = computeSignature(channelName, sourceIndex, sources);

  final String channelName;
  final String originalUrl;
  final int sourceIndex;
  final List<String> sources;
  final RecordingSourceOrigin origin;

  /// 源身份哈希（频道 + 源索引 + 全部源）。
  final String signature;

  static String computeSignature(String channelName, int sourceIndex, List<String> sources) {
    final String raw = '$channelName|$sourceIndex|${sources.join('|')}';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  @override
  String toString() => 'RecordingSource($channelName, idx=$sourceIndex, ${origin.name})';
}

/// 录制状态。
enum RecordingStatus { idle, recording, error }

/// 控制器对外暴露的不可变状态（每次 tick 生成新对象驱动 ValueListenableBuilder）。
class RecordingState {
  const RecordingState({
    this.status = RecordingStatus.idle,
    this.elapsed = Duration.zero,
    this.bytes = 0,
    this.channelName = '',
    this.error = '',
  });

  final RecordingStatus status;
  final Duration elapsed;
  final int bytes;
  final String channelName;
  final String error;

  bool get isRecording => status == RecordingStatus.recording;

  RecordingState copyWith({
    RecordingStatus? status,
    Duration? elapsed,
    int? bytes,
    String? channelName,
    String? error,
  }) {
    return RecordingState(
      status: status ?? this.status,
      elapsed: elapsed ?? this.elapsed,
      bytes: bytes ?? this.bytes,
      channelName: channelName ?? this.channelName,
      error: error ?? this.error,
    );
  }
}

/// 一次性事件（宿主据此弹 SnackBar，D-9：controller 不持有 context / 不发 UI）。
enum RecordingEvent {
  started,
  saved,
  unsupported,
  failed,
  switchBlocked,
  sourceSwitched,
  duplicate,
  lowSpace,
}

/// 事件携带的数据，供宿主拼文案（如 `已保存 X 的录制`）。
class RecordingEventData {
  const RecordingEventData(this.type, {this.channelName = '', this.path = ''});

  final RecordingEvent type;
  final String channelName;
  final String path;
}

/// 录制控制器（共享包核心，全局单例）。
///
/// 职责：
/// - 首拉 m3u8（master 取最低码率分支）、按滑动窗口追加下载 `.ts` 分片；
/// - 维护 [state]（ValueNotifier）与一次性 [onEvent] 回调，UI 由宿主实现；
/// - 切源三级策略（D-11/12/13）：manual 拦截、reload 放行、auto 停录保播放。
///
/// 依赖全部可注入（[fetchText] / [fetchBytes] / [documentsDir] / [isParentMode] /
/// [now]），便于纯 Dart 单测；默认实现用 dio 与 path_provider。
class RecordingController {
  RecordingController({
    Dio? dio,
    Future<String> Function(Uri url)? fetchText,
    Future<List<int>> Function(Uri url)? fetchBytes,
    Future<Directory> Function()? documentsDir,
    bool Function()? isParentMode,
    DateTime Function()? now,
    RecordingStorage? storage,
    this.retryDelay = const Duration(milliseconds: 300),
    int? maxFileBytes,
    this.lowSpaceBytes = 512 * 1024 * 1024, // 512MB 低空间阈值
    int? maxSegmentsPerPoll,
  })  : maxSegmentsPerPoll = maxSegmentsPerPoll ?? 2,
        _defaultDio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 60),
                headers: const <String, dynamic>{'accept-encoding': 'identity'},
              ),
            ),
        _fetchText = fetchText,
        _fetchBytes = fetchBytes,
        _storage = storage ??
            RecordingStorage(
              platform: documentsDir == null
                  ? null
                  : MethodChannelRecordingPlatform(documentsDirProvider: documentsDir),
            ),
        _isParentMode = isParentMode ?? (() => !ParentalStateController.instance.enabled),
        _now = now ?? DateTime.now,
        maxFileBytes = maxFileBytes ?? 2 * 1024 * 1024 * 1024;

  /// 全局单例。测试可自行构造隔离实例。
  static final RecordingController instance = RecordingController();

  /// 仅在未注入 [fetchText]/[fetchBytes] 时使用的默认 Dio。
  final Dio _defaultDio;

  /// 注入的文本/分片下载器。null 表示回落到 [_defaultDio]。
  final Future<String> Function(Uri url)? _fetchText;
  final Future<List<int>> Function(Uri url)? _fetchBytes;
  final RecordingStorage _storage;
  final bool Function() _isParentMode;
  final DateTime Function() _now;

  /// 单分片失败的重试间隔（测试可设 Duration.zero）。
  final Duration retryDelay;

  /// 文件软上限，到限自动 stop。
  final int maxFileBytes;

  /// 低空间阈值；可用空间低于此值时停止并保存（<=0 或探测失败时跳过）。
  final int lowSpaceBytes;

  /// 单次 poll 最多下载的分片数（保留构造参数以兼容调用方）。
  ///
  /// 自本地代理落地后不再用于「跳过旧片」：跳片会主动丢弃中间内容，
  /// 是回放「一跳一跳」的直接原因之一。现在始终下载全部落后分片，
  /// 宁可录制落后也不丢片；带宽争用已由本地代理的缓存合并解决。
  final int maxSegmentsPerPoll;

  /// 诊断日志回调（可选）：宿主接到自己的 LogService，日志格式与播放日志一致。
  /// 未设置时回落到 dart:developer.log（name='Recording'）。
  void Function(String message)? onDiagnostic;

  void _diag(String message) {
    final String line = '[Recording] $message';
    final void Function(String message)? sink = onDiagnostic;
    if (sink != null) {
      sink(line);
      return;
    }
    developer.log(line, name: 'Recording');
  }

  final ValueNotifier<RecordingState> state = ValueNotifier<RecordingState>(const RecordingState());

  /// 一次性事件回调（宿主监听后弹 SnackBar / 更新提示）。
  void Function(RecordingEventData event)? onEvent;

  RecordingSource? _recordingSource;
  Uri? _mediaPlaylistUrl;
  String? _lastSegmentUrl;
  RecordingSink? _sink;
  Timer? _pollTimer;
  Timer? _tickTimer;
  int _bytes = 0;
  int _consecutiveFailures = 0;
  DateTime? _startedAt;

  /// 录制连续性闸门：拦截重复分片、检测会话归零（PCR 断崖）。
  final SegmentQualityGate _gate = SegmentQualityGate();

  /// 文件名去重后缀：同一秒因会话归零另起新文件时递增，避免覆盖。
  int _fileSeq = 0;

  bool get isRecording => state.value.isRecording;
  RecordingSource? get recordingSource => _recordingSource;

  void _emit(RecordingEvent type, {String channelName = '', String path = ''}) {
    onEvent?.call(RecordingEventData(type, channelName: channelName, path: path));
  }

  void _set(RecordingState s) => state.value = s;

  // ---------------------------------------------------------------------------
  // 切源决策（供 RecordingSourceProvider.report 调用）
  // ---------------------------------------------------------------------------

  /// 源变化上报：返回 false 表示拦截本次换源（播放器不得切源）。
  ///
  /// - 非录制中：一律放行（D-11 只约束录制中）；
  /// - signature 未变（reload 同一 URL / 重复上报）：放行；
  /// - manual + signature 变（用户按左右切源）：拦截 + `switch_blocked` 事件；
  /// - auto + signature 变（看门狗/重试真换源、切台）：放行，由
  ///   [RecordingSourceProvider] 随即调用 [onSourceChanged] 停录。
  bool onSourceReport(RecordingSource s) {
    if (!isRecording || _recordingSource == null) return true;
    if (s.signature == _recordingSource!.signature) return true;
    // 切台（频道名变化）不属于「切源」，任何 origin 都放行，交由
    // onSourceChanged 停录保存 —— 否则用户切台会被误判为切源而卡住。
    final bool sameChannel = s.channelName == _recordingSource!.channelName;
    if (sameChannel && s.origin == RecordingSourceOrigin.manual) {
      _emit(RecordingEvent.switchBlocked, channelName: _recordingSource!.channelName);
      return false;
    }
    return true;
  }

  /// provider 检测到 signature 变化时调用：停录并保存已录部分。
  ///
  /// 返回 Future 便于宿主/测试等待收尾；调用方可 fire-and-forget。
  Future<void> onSourceChanged(RecordingSource s) async {
    if (!isRecording || _recordingSource == null) return;
    if (s.signature == _recordingSource!.signature) return;
    final bool sameChannel = s.channelName == _recordingSource!.channelName;
    // 先同步取值，stop() 是异步且会清空 _recordingSource。
    await stop(event: sameChannel ? RecordingEvent.sourceSwitched : RecordingEvent.saved);
  }

  // ---------------------------------------------------------------------------
  // 生命周期
  // ---------------------------------------------------------------------------

  /// 开始录制。已在录制 / 儿童模式 / 源不支持时返回 false。
  Future<bool> start(RecordingSource source) async {
    if (isRecording) {
      _emit(RecordingEvent.duplicate, channelName: source.channelName);
      return false;
    }
    if (!_isParentMode()) return false;

    HlsPlaylist playlist;
    try {
      playlist = await _resolveMediaPlaylist(source.originalUrl);
    } catch (_) {
      _enterError('无法获取频道流地址');
      return false;
    }
    if (playlist.encrypted) {
      _emit(RecordingEvent.unsupported, channelName: source.channelName);
      return false;
    }
    if (playlist.segments.isEmpty) {
      _enterError('频道暂无可录制分片');
      return false;
    }

    // 低空间预检：仅当平台返回有效值时判断，未知（-1）跳过。
    final int free = await _storage.freeBytes();
    if (free >= 0 && free < lowSpaceBytes) {
      _emit(RecordingEvent.lowSpace, channelName: source.channelName);
      return false;
    }

    final String fileName = _buildFileName(source.channelName, _now());
    final RecordingSink sink;
    try {
      sink = await _storage.createSink(fileName);
      if (sink is LocalFileSink) await sink.open();
      if (sink is SafStreamSink) await sink.open();
      _sink = sink;
    } catch (_) {
      _enterError('无法创建录制文件');
      return false;
    }

    _recordingSource = source;
    _mediaPlaylistUrl = playlist.base;
    _lastSegmentUrl = null;
    _bytes = 0;
    _consecutiveFailures = 0;
    _startedAt = _now();
    _gate.reset();
    _fileSeq = 0;
    _set(
      RecordingState(
        status: RecordingStatus.recording,
        channelName: source.channelName,
      ),
    );
    _emit(RecordingEvent.started, channelName: source.channelName, path: sink.location);

    // 从最后一个分片开始（"正在观看"从此刻起），不回录已有内容。
    final Uri last = playlist.segments.last;
    final Stopwatch firstSw = Stopwatch()..start();
    final List<int>? firstBytes = await _downloadSegment(last);
    if (firstBytes == null) {
      // 首个分片都拉不到 → 视为失败，保留空文件由调用方决定清理。
      await stop(event: RecordingEvent.failed);
      return false;
    }
    // 首片过闸门：登记字节指纹与 PCR 基准（首片不可能重复/归零）。
    final GateDecision firstDecision = _gate.evaluate(firstBytes);
    await _appendBytes(firstBytes);
    firstSw.stop();
    _lastSegmentUrl = last.toString();
    final String firstPcrLabel = firstDecision.pcrTicks != null
        ? '${(firstDecision.pcrTicks! / 90000).toStringAsFixed(1)}s'
        : 'n/a';
    _diag('首分片 ${firstBytes.length}B，下载+写入 ${firstSw.elapsedMilliseconds}ms '
        'pcr=$firstPcrLabel');

    final int intervalSeconds = playlist.targetDuration > 0 ? playlist.targetDuration : 4;
    _pollTimer = Timer.periodic(Duration(seconds: intervalSeconds), (_) => unawaited(_poll()));
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    return true;
  }

  /// 会话归零（relay 换 sid，PCR 从 0 重启）时：保存当前文件，另起新文件
  /// 继续录制，保持录制状态不变。每个文件内部时间戳单调，回放不再断崖。
  Future<void> _rotateFile() async {
    final RecordingSource? source = _recordingSource;
    final RecordingSink? oldSink = _sink;
    if (source == null) return;

    try {
      await oldSink?.close();
    } catch (_) {}

    _fileSeq += 1;
    final String base = _buildFileName(source.channelName, _now());
    // 同秒多次归零时加 _2 / _3 后缀，避免覆盖。
    final String fileName = _fileSeq > 1
        ? base.replaceFirst(RegExp(r'\.ts$'), '_$_fileSeq.ts')
        : base;
    try {
      final RecordingSink newSink = await _storage.createSink(fileName);
      if (newSink is LocalFileSink) await newSink.open();
      if (newSink is SafStreamSink) await newSink.open();
      _sink = newSink;
      _bytes = 0;
      // 不重置闸门：归零片已 evaluate，其 PCR 正是新文件的单调基准；
      // 字节指纹跨文件保留，可拦截整窗重下带来的重复片。
      _lastSegmentUrl = null;
      _diag('会话归零：已保存并另起新文件 $fileName（录制继续，PCR 单调）');
    } catch (_) {
      _diag('会话归零：另起新文件失败，原文件已保存，停止录制');
      await stop(event: RecordingEvent.failed);
    }
  }

  /// 停止录制。[event] 指定完成事件（默认 saved）；[silent] 用于退出场景不发提示。
  Future<void> stop({bool save = true, RecordingEvent? event, bool silent = false}) async {
    if (state.value.status == RecordingStatus.idle) return;
    final RecordingSource? source = _recordingSource;
    final RecordingSink? sink = _sink;
    final String path = sink?.location ?? '';

    _pollTimer?.cancel();
    _pollTimer = null;
    _tickTimer?.cancel();
    _tickTimer = null;

    try {
      await sink?.close();
    } catch (_) {
      // 关闭失败不影响状态收尾。
    }
    _sink = null;

    // save=false 时删除空文件（仅本地位置可直接删；SAF 空文件保留由用户处理）。
    if (!save && sink is LocalFileSink) {
      try {
        final File f = sink.file;
        if (f.existsSync()) await f.delete();
      } catch (_) {}
    }

    _recordingSource = null;
    _mediaPlaylistUrl = null;
    _lastSegmentUrl = null;
    _startedAt = null;
    _set(const RecordingState());

    if (!silent && save) {
      _emit(event ?? RecordingEvent.saved, channelName: source?.channelName ?? '', path: path);
    }
  }

  /// 桌面端（Windows/Linux/macOS）窗口失焦 / 最小化只是 lifecycle 的
  /// inactive/hidden，并非真后台，录制应继续跑完；移动端（Android/iOS）
  /// 退后台会被系统冻结网络与文件写入，必须停录保存。
  static bool get keepRecordingInBackground =>
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;

  /// 退出 / 离页：静默停止并保存，不弹提示。
  Future<void> stopOnExit() => stop(silent: true);

  /// 测试辅助：重置全部状态（不影响单例引用）。
  Future<void> reset() => stop(silent: true);

  // ---------------------------------------------------------------------------
  // 内部轮询与下载
  // ---------------------------------------------------------------------------

  Future<void> _poll() async {
    if (!isRecording || _mediaPlaylistUrl == null) return;
    HlsPlaylist playlist;
    final Stopwatch playlistSw = Stopwatch()..start();
    try {
      final String text = await _fetchPlaylistText(_mediaPlaylistUrl!);
      playlist = parsePlaylist(text, _mediaPlaylistUrl!);
    } catch (_) {
      _recordFailure();
      return;
    }
    playlistSw.stop();
    if (playlist.segments.isEmpty) return;

    // 以「上次下载的分片 URL」为锚点：找到它在最新窗口的位置，下载其后的新分片。
    // 找不到（窗口已滑走 / relay 换 sid）则从头算。本地代理已合并播放与录制的
    // 下载，补整窗不再抢带宽，因此不再跳片——录制宁可落后也不丢中间内容。
    // 重复分片由 [SegmentQualityGate] 按字节指纹拦截，不会写进文件。
    int start = 0;
    if (_lastSegmentUrl != null) {
      final int idx = playlist.segments.indexWhere((Uri u) => u.toString() == _lastSegmentUrl);
      if (idx >= 0) start = idx + 1;
    }
    final int pendingAll = playlist.segments.length - start;
    if (pendingAll <= 0) {
      _diag('poll playlist=${playlistSw.elapsedMilliseconds}ms 无新片 '
          'window=${playlist.segments.length}');
      _tick();
      return;
    }
    _diag('poll playlist=${playlistSw.elapsedMilliseconds}ms 待取 $pendingAll 片 '
          'window=${playlist.segments.length} anchor=${idxOf(_lastSegmentUrl, playlist)}');

    try {
      for (int i = start; i < playlist.segments.length; i++) {
        if (!isRecording) return;
        final Uri segment = playlist.segments[i];
        final Stopwatch fetchSw = Stopwatch()..start();
        final List<int>? bytes = await _downloadSegment(segment);
        fetchSw.stop();
        if (bytes == null) return; // 已按连续失败计数处理

        // 连续性闸门：重复片跳过；归零片正常写入后另起新文件。
        final GateDecision decision = _gate.evaluate(bytes);
        if (!decision.write) {
          _lastSegmentUrl = segment.toString();
          _diag('分片 ${i - start + 1}/$pendingAll 重复片跳过 '
              '${bytes.length}B url=$segment');
          continue;
        }

        // 归零片属于新会话：先另起新文件，再把它写进新文件（成为新文件首片）。
        // 这样旧文件在归零前干净收尾，新文件从归零片起 PCR 单调。
        if (decision.pcrReset) await _rotateFile();

        final Stopwatch writeSw = Stopwatch()..start();
        await _appendBytes(bytes);
        writeSw.stop();
        _lastSegmentUrl = segment.toString();
        _diag('分片 ${i - start + 1}/$pendingAll ${bytes.length}B '
            '下载=${fetchSw.elapsedMilliseconds}ms 写入=${writeSw.elapsedMilliseconds}ms '
            '累计=$_bytes gate=${decision.reason}');

        if (_bytes >= maxFileBytes) {
          await stop(); // 到软上限，保存
          return;
        }
        // 每落一个分片检查一次剩余空间，低于阈值先保存再停。
        final int free = await _storage.freeBytes();
        if (free >= 0 && free < lowSpaceBytes) {
          _emit(RecordingEvent.lowSpace, channelName: _recordingSource?.channelName ?? '');
          await stop();
          return;
        }
      }
      _consecutiveFailures = 0;
      _tick();
    } catch (_) {
      _recordFailure();
    }
  }

  /// 诊断用：锚点在窗口中的索引（-1 表示已滑走）。
  static int idxOf(String? lastUrl, HlsPlaylist playlist) =>
      lastUrl == null ? -1 : playlist.segments.indexWhere((Uri u) => u.toString() == lastUrl);

  /// 单分片下载，失败重试 2 次（共 3 次）。返回 null 表示三次都失败。
  Future<List<int>?> _downloadSegment(Uri url) async {
    Object? lastError;
    for (int attempt = 0; attempt < 3; attempt++) {
      if (!isRecording) return null;
      try {
        final List<int> bytes = await _fetchSegmentBytes(url);
        if (bytes.isEmpty) throw const SocketException('空分片');
        _consecutiveFailures = 0;
        return bytes;
      } catch (e) {
        lastError = e;
        if (attempt < 2 && retryDelay > Duration.zero) {
          await Future<void>.delayed(retryDelay);
        }
      }
    }
    _recordFailure(lastError);
    return null;
  }

  void _recordFailure([Object? _]) {
    _consecutiveFailures += 1;
    if (_consecutiveFailures >= 3) {
      // stop() 会清空 _recordingSource，先捕获频道名。
      final String channelName = _recordingSource?.channelName ?? '';
      unawaited(
        stop(event: RecordingEvent.failed).then((_) {
          _set(RecordingState(status: RecordingStatus.error, error: '录制失败，已保存部分内容'));
          _emit(RecordingEvent.failed, channelName: channelName);
        }),
      );
    }
  }

  Future<void> _appendBytes(List<int> bytes) async {
    await _sink?.append(bytes);
    _bytes += bytes.length;
    _tick();
  }

  void _tick() {
    if (!isRecording) return;
    final DateTime? started = _startedAt;
    if (started == null) return;
    _set(
      RecordingState(
        status: RecordingStatus.recording,
        elapsed: _now().difference(started),
        bytes: _bytes,
        channelName: _recordingSource?.channelName ?? '',
      ),
    );
  }

  void _enterError(String message) {
    _set(RecordingState(status: RecordingStatus.error, error: message));
    _emit(RecordingEvent.failed);
  }

  Future<HlsPlaylist> _resolveMediaPlaylist(String url) async {
    final Uri uri = Uri.parse(url);
    final HlsPlaylist first = parsePlaylist(await _fetchPlaylistText(uri), uri);
    if (!first.isMaster) return first;
    final Uri variant = first.selectedVariantUrl;
    return parsePlaylist(await _fetchPlaylistText(variant), variant);
  }

  /// 拉取 playlist：注入 fetch 优先（单测）；否则进程内本地代理可用时走代理
  /// 缓存（与播放器共用同一份下载），再否则回落默认 Dio 直连。
  Future<String> _fetchPlaylistText(Uri url) {
    final Future<String> Function(Uri url)? injected = _fetchText;
    if (injected != null) return injected(url);
    final HlsLocalProxy proxy = HlsLocalProxy.instance;
    if (proxy.isUsable) return proxy.fetchPlaylistText(url);
    return _defaultFetchText(_defaultDio, url);
  }

  /// 拉取分片：优先级同 [_fetchPlaylistText]。
  Future<List<int>> _fetchSegmentBytes(Uri url) {
    final Future<List<int>> Function(Uri url)? injected = _fetchBytes;
    if (injected != null) return injected(url);
    final HlsLocalProxy proxy = HlsLocalProxy.instance;
    if (proxy.isUsable) return proxy.fetchSegmentBytes(url);
    return _defaultFetchBytes(_defaultDio, url);
  }

  static Future<String> _defaultFetchText(Dio dio, Uri url) async {
    final Response<String> response = await dio.get<String>(
      url.toString(),
      options: Options(responseType: ResponseType.plain),
    );
    return response.data ?? '';
  }

  static Future<List<int>> _defaultFetchBytes(Dio dio, Uri url) async {
    final Response<List<int>> response = await dio.get<List<int>>(
      url.toString(),
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? const <int>[];
  }

  static String _buildFileName(String channelName, DateTime now) {
    final String safe = channelName.replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_');
    String two(int v) => v.toString().padLeft(2, '0');
    final String stamp = '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}${two(now.second)}';
    return '${safe}_$stamp.ts';
  }
}
