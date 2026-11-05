import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pscreen_screen/core/update/app_update_api.dart';
import 'package:pscreen_screen/core/update/app_update_cache.dart';
import 'package:pscreen_screen/core/update/app_update_downloader.dart';
import 'package:pscreen_screen/core/update/app_update_installer.dart';
import 'package:pscreen_screen/core/update/app_update_models.dart';

/// 更新模块阶段。
///
/// - [idle]：无更新 / 查询失败放行（fail-open）/ iOS 仅提示；
/// - [checking]：正在查询；
/// - [downloading]：后台静默下载（**不阻断使用**）；
/// - [ready]：已下载且 sha256 校验通过（强更时进入不可关闭更新页）；
/// - [installing]：已拉起系统安装器；
/// - [failed]：下载失败，仅静默重试（下次启动 / 回前台 / 网络恢复）。
enum AppUpdatePhase { idle, checking, downloading, ready, installing, failed }

@immutable
class AppUpdateState {
  const AppUpdateState({
    this.phase = AppUpdatePhase.idle,
    this.result,
    this.received = 0,
    this.total = 0,
    this.error,
    this.attempt = 0,
    this.cachedPath,
  });

  final AppUpdatePhase phase;
  final AppUpdateCheckResult? result;
  final int received;
  final int total;
  final String? error;
  final int attempt;
  final String? cachedPath;

  double? get progress => total > 0 ? (received / total).clamp(0.0, 1.0) : null;

  /// 强更且已下载校验通过 → 必须展示不可关闭的更新页。
  bool get forceBlocked => phase == AppUpdatePhase.ready && result?.forceRequired == true;

  /// 非强更：AppBar 显示「更新」胶囊；有进度时展示百分比。
  bool get showPill =>
      result?.hasUpdate == true &&
      (phase == AppUpdatePhase.downloading || phase == AppUpdatePhase.ready || phase == AppUpdatePhase.installing);

  AppUpdateState copyWith({
    AppUpdatePhase? phase,
    AppUpdateCheckResult? result,
    int? received,
    int? total,
    String? error,
    int? attempt,
    String? cachedPath,
  }) =>
      AppUpdateState(
        phase: phase ?? this.phase,
        result: result ?? this.result,
        received: received ?? this.received,
        total: total ?? this.total,
        error: error,
        attempt: attempt ?? this.attempt,
        cachedPath: cachedPath ?? this.cachedPath,
      );
}

/// 更新模块运行时配置（由各 App 在启动时注入身份与环境）。
@immutable
class AppUpdateRuntime {
  const AppUpdateRuntime({
    required this.appId,
    required this.platform,
    required this.baseUrl,
    required this.version,
    required this.build,
    this.deviceId = '',
    this.maxBytesPerSecond,
  });

  final String appId;

  /// `apk / ios / windows / macos / linux`（web 不检查更新）。
  final String platform;

  /// 本地 pscreen_server 根地址（运行期可变，来自 App 现有配置）。
  final String baseUrl;
  final String version;
  final int build;
  final String deviceId;

  /// 可选限速；null 表示不限速。
  final int? maxBytesPerSecond;
}

/// 更新状态机（单例）：启动查一次 → 静默下载 → 校验 → 提示/强更。
///
/// 设计约束（已与产品确认）：
/// - 任何阶段都不阻断使用；只有「强更 + 下载校验通过」才出现不可关闭页；
/// - 下载失败只静默重试（启动 / 回前台 / 网络恢复 + 指数退避），不转阻断；
/// - 缓存按 `releaseId + sha256` 复用，换版本或文件被清理才重下；
/// - 查询失败 fail-open（只记日志）。
class AppUpdateController extends ChangeNotifier implements ValueListenable<AppUpdateState> {
  AppUpdateController({
    AppUpdateApi? api,
    AppUpdateCache? cache,
    AppUpdateDownloader? downloader,
    AppUpdateInstaller installer = const AppUpdateInstaller(),
    DateTime Function()? now,
  })  : _api = api,
        _cache = cache,
        _downloader = downloader,
        _installer = installer,
        _now = now ?? DateTime.now;

  static final AppUpdateController instance = AppUpdateController();

  AppUpdateApi? _api;
  AppUpdateCache? _cache;
  AppUpdateDownloader? _downloader;
  final AppUpdateInstaller _installer;
  final DateTime Function() _now;
  AppUpdateRuntime? _runtime;

  AppUpdateState _state = const AppUpdateState();

  @override
  AppUpdateState get value => _state;

  AppUpdateState get state => _state;

  Future<void>? _inflight;
  Timer? _retryTimer;
  int _attempt = 0;
  DateTime? _lastNotifyAt;
  bool _disposed = false;

  AppUpdateRuntime? get runtime => _runtime;

  /// 启动阶段调用一次：注入身份并立即开始查询（失败不阻塞启动）。
  void configure(AppUpdateRuntime runtime) {
    _runtime = runtime;
    _api = _api ?? AppUpdateApi(baseUrl: runtime.baseUrl);
    _downloader = _downloader ?? AppUpdateDownloader(maxBytesPerSecond: runtime.maxBytesPerSecond);
    unawaited(start());
  }

  Future<void> start() => check();

  /// 查询更新；[manual] 表示用户主动点开更新入口（允许重新取链）。
  Future<void> check({bool manual = false}) async {
    final AppUpdateRuntime? runtime = _runtime;
    if (runtime == null) return;
    final AppUpdateApi? api = _api;
    if (api == null) return;

    final AppUpdateState checking = _state.copyWith(phase: AppUpdatePhase.checking, error: null);
    _emit(checking);
    try {
      final AppUpdateCheckResult result = await api.check(
        appId: runtime.appId,
        platform: runtime.platform,
        version: runtime.version,
        build: runtime.build,
        deviceId: runtime.deviceId,
      );
      _emit(AppUpdateState(phase: AppUpdatePhase.idle, result: result));
      if (result.canSilentlyDownload) {
        unawaited(_ensureDownloaded(result));
      }
    } on AppUpdateException catch (error) {
      // fail-open：查询失败只记录，保留上一次结果，不阻断使用。
      _emit(_state.copyWith(phase: AppUpdatePhase.failed, error: error.message));
      _scheduleRetry();
    } catch (error) {
      _emit(_state.copyWith(phase: AppUpdatePhase.failed, error: '$error'));
      _scheduleRetry();
    }
  }

  /// 手动触发下载 / 重试（用户点「立即安装」或「重试」）。
  Future<void> ensureDownloadedNow() async {
    final AppUpdateCheckResult? result = _state.result;
    if (result == null) {
      await check(manual: true);
      return;
    }
    await _ensureDownloaded(result);
  }

  Future<void> _ensureDownloaded(AppUpdateCheckResult result) async {
    if (_inflight != null) return _inflight;
    final AppUpdateDownload? download = result.download;
    if (download == null || !download.isUsable) {
      _emit(_state.copyWith(phase: AppUpdatePhase.failed, error: '服务端未提供安装包'));
      return;
    }
    final AppUpdateRuntime runtime = _runtime!;
    final AppUpdateCache? cache = _cache;
    if (cache == null) {
      _cache = await AppUpdateCache.open();
    }
    final Future<void> task = _download(result, runtime, _cache!);
    _inflight = task;
    try {
      await task;
    } finally {
      _inflight = null;
    }
  }

  Future<void> _download(AppUpdateCheckResult result, AppUpdateRuntime runtime, AppUpdateCache cache) async {
    final String releaseId = result.latest?.releaseId ?? '';
    final AppUpdateDownload download = result.download!;
    final File cached = cache.finalFile(appId: runtime.appId, releaseId: releaseId, sha256: download.sha256);

    // 缓存复用：sha256 一致直接进入「可安装」，不重复下载。
    if (await cache.isReady(appId: runtime.appId, releaseId: releaseId, sha256: download.sha256)) {
      _emit(_state.copyWith(
        phase: AppUpdatePhase.ready,
        cachedPath: cached.path,
        received: download.size,
        total: download.size,
        error: null,
      ));
      return;
    }

    _emit(_state.copyWith(
      phase: AppUpdatePhase.downloading,
      received: 0,
      total: download.size,
      error: null,
      attempt: _attempt,
    ));

    for (int round = 0; round < 3; round++) {
      try {
        final File file = await _downloader!.download(
          appId: runtime.appId,
          result: result,
          cache: cache,
          onProgress: (int received, int total) => _emit(
            _state.copyWith(phase: AppUpdatePhase.downloading, received: received, total: total),
            throttle: true,
          ),
          renewDownload: () async {
            // 签名过期 / 文件被清理：重新查询一次（force 模式要求必须拿到）。
            try {
              final AppUpdateCheckResult fresh = await _api!.check(
                appId: runtime.appId,
                platform: runtime.platform,
                version: runtime.version,
                build: runtime.build,
                deviceId: runtime.deviceId,
              );
              if (fresh.download != null && fresh.download!.isUsable) {
                _emit(_state.copyWith(result: fresh));
                return fresh.download;
              }
            } catch (_) {}
            return null;
          },
        );
        _attempt = 0;
        _emit(_state.copyWith(
          phase: AppUpdatePhase.ready,
          cachedPath: file.path,
          received: download.size,
          total: download.size,
          error: null,
          attempt: 0,
        ));
        return;
      } on AppUpdateShaMismatchException {
        // 校验不一致：文件已删除，重下一轮（不增加退避计数）。
        continue;
      } on AppUpdateDownloadException catch (error) {
        if (!error.retryable) {
          _emit(_state.copyWith(phase: AppUpdatePhase.failed, error: error.message));
          return;
        }
        // 网络波动 / 300008 / 限流：保留断点，退避后静默重试。
        await Future<void>.delayed(_backoffDelay(round));
      } catch (error) {
        await Future<void>.delayed(_backoffDelay(round));
      }
    }

    _emit(_state.copyWith(phase: AppUpdatePhase.failed, error: '下载未完成，将在下次启动/回前台时重试'));
    _scheduleRetry();
  }

  Duration _backoffDelay(int round) {
    const List<int> seconds = <int>[5, 20, 60];
    return Duration(seconds: seconds[round.clamp(0, seconds.length - 1)]);
  }

  /// 回前台 / 网络恢复：只对「未完成」状态补一次重试，已就绪不重复下载。
  void onForeground() {
    final AppUpdatePhase phase = _state.phase;
    if (phase == AppUpdatePhase.downloading) return;
    if (phase == AppUpdatePhase.ready || phase == AppUpdatePhase.installing) {
      // 可能已安装完成但未重启：重新校验版本，装好后就不应再提示。
      unawaited(check());
      return;
    }
    if (phase == AppUpdatePhase.failed) {
      _scheduleRetry(immediate: true);
    }
  }

  void onNetworkRestored() => onForeground();

  void _scheduleRetry({bool immediate = false}) {
    final AppUpdateRuntime? runtime = _runtime;
    if (runtime == null) return;
    _retryTimer?.cancel();
    const List<int> seconds = <int>[10, 30, 120, 600];
    final int delay = immediate ? 0 : seconds[_attempt.clamp(0, seconds.length - 1)];
    _attempt += 1;
    _retryTimer = Timer(Duration(seconds: delay), () {
      if (_disposed) return;
      final AppUpdateState state = _state;
      if (state.phase == AppUpdatePhase.downloading) return;
      if (state.result == null || state.result!.hasUpdate) {
        // 已有结果：直接重试下载；无结果（查询失败）则重新查询。
        if (state.result != null && state.result!.canSilentlyDownload) {
          unawaited(_ensureDownloaded(state.result!));
        } else {
          unawaited(check());
        }
      }
    });
  }

  /// 拉起系统安装器（仅 Android/桌面自托管包）。
  Future<bool> install() async {
    final String? path = _state.cachedPath;
    if (path == null) return false;
    try {
      final bool started = await _installer.installApk(path);
      if (started) _emit(_state.copyWith(phase: AppUpdatePhase.installing));
      return started;
    } on AppUpdateException catch (error) {
      _emit(_state.copyWith(error: error.message));
      return false;
    }
  }

  /// iOS：打开外部链接（store / TestFlight）。
  Future<bool> openExternalUrl() async {
    final String? url = _state.result?.latest?.externalUrl;
    if (url == null) return false;
    return _installer.openExternal(url);
  }

  void _emit(AppUpdateState next, {bool throttle = false}) {
    if (_disposed) return;
    if (throttle) {
      final DateTime now = _now();
      final DateTime? last = _lastNotifyAt;
      if (last != null && now.difference(last) < const Duration(milliseconds: 120)) return;
      _lastNotifyAt = now;
    }
    if (_state.phase == next.phase &&
        _state.received == next.received &&
        _state.total == next.total &&
        _state.error == next.error &&
        identical(_state.result, next.result) &&
        _state.cachedPath == next.cachedPath) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    super.dispose();
  }
}
