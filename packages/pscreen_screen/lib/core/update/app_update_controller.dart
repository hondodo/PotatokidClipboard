import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pscreen_screen/core/update/app_update_api.dart';
import 'package:pscreen_screen/core/update/app_update_cache.dart';
import 'package:pscreen_screen/core/update/app_update_downloader.dart';
import 'package:pscreen_screen/core/update/app_update_installer.dart';
import 'package:pscreen_screen/core/update/app_update_models.dart';

/// 更新链路诊断日志：统一前缀 `[AppUpdate]`，便于 `flutter run` 控制台 / logcat 过滤。
void _updateLog(String message) => debugPrint('[AppUpdate] $message');

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
    this.forcePending = false,
  });

  final AppUpdatePhase phase;
  final AppUpdateCheckResult? result;
  final int received;
  final int total;
  final String? error;
  final int attempt;
  final String? cachedPath;

  /// 强更已下载并校验通过后置为 true；在 checking/idle/failed/installing
  /// 期间都保持不变，只有「成功查询且不再有更新」才清除。
  final bool forcePending;

  double? get progress => total > 0 ? (received / total).clamp(0.0, 1.0) : null;

  /// 粘性强更：不依赖当前 phase/result，避免重查或拉起安装器时短暂放开拦截。
  bool get forceBlocked => forcePending;

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
    bool? forcePending,
  }) =>
      AppUpdateState(
        phase: phase ?? this.phase,
        result: result ?? this.result,
        received: received ?? this.received,
        total: total ?? this.total,
        error: error,
        attempt: attempt ?? this.attempt,
        cachedPath: cachedPath ?? this.cachedPath,
        forcePending: forcePending ?? this.forcePending,
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
    this.checkInterval = const Duration(hours: 12),
    this.checkJitter = const Duration(minutes: 30),
    this.foregroundCheckAfter = const Duration(hours: 1),
    this.canStartDownload,
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

  /// 周期检查间隔；<= 0 表示不启动周期检查。
  final Duration checkInterval;

  /// 首次检查的随机抖动上限：按 deviceId 稳定派生，避免断电重启后同时请求。
  final Duration checkJitter;

  /// 前台补查阈值：从上次成功检查起算，超过该间隔且发生 `resumed` 才补查。
  ///
  /// 与 [checkInterval] 独立：后台周期检查仍按 12 小时，前台回来时更积极。
  final Duration foregroundCheckAfter;

  /// 当前场景是否允许开始静默下载；null 表示不限制。
  ///
  /// 由宿主注入：TV 不限页面（靠 [maxBytesPerSecond] 限速），中控按屏保开关与直播状态判断。
  /// 强更与普通更新都遵守该判定，只有用户手动点「重试/立即安装」才绕过。
  final bool Function()? canStartDownload;
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
  Future<void>? _checkingFuture;
  Timer? _retryTimer;
  Timer? _checkTimer;
  int _attempt = 0;
  DateTime? _lastNotifyAt;
  DateTime? _lastCheckAt;
  AppUpdateCheckResult? _deferredDownload;
  bool _ownsApi = false;
  bool _ownsDownloader = false;
  bool _disposed = false;

  AppUpdateRuntime? get runtime => _runtime;

  /// 启动阶段调用一次：注入身份、恢复粘性强更、启动周期检查并立即查询。
  ///
  /// 返回的 Future 只等待本地 pending 恢复完成；查询失败不阻塞启动。
  Future<void> configure(AppUpdateRuntime runtime) async {
    _runtime = runtime;
    // baseUrl 可能被设置页热改：自身构造的 Api 必须按新地址重建，
    // 否则周期检查会一直请求旧服务器（注入的 Api 由调用方负责）。
    if (_api == null) {
      _api = AppUpdateApi(baseUrl: runtime.baseUrl);
      _ownsApi = true;
    } else if (_ownsApi) {
      _api = AppUpdateApi(baseUrl: runtime.baseUrl);
    }
    if (_downloader == null) {
      _downloader = AppUpdateDownloader(maxBytesPerSecond: runtime.maxBytesPerSecond);
      _ownsDownloader = true;
    } else if (_ownsDownloader) {
      // 预留限速接入：后续只需在 AppUpdateRuntime 传入 maxBytesPerSecond。
      _downloader = AppUpdateDownloader(maxBytesPerSecond: runtime.maxBytesPerSecond);
    }
    _updateLog(
      'configure appId=${runtime.appId} platform=${runtime.platform} '
      'v${runtime.version}+${runtime.build} deviceId=${runtime.deviceId} '
      'baseUrl=${runtime.baseUrl.isEmpty ? '<空>' : runtime.baseUrl} '
      '周期=${runtime.checkInterval} 前台补查=${runtime.foregroundCheckAfter} '
      '限速=${runtime.maxBytesPerSecond ?? -1}B/s '
      '门控=${runtime.canStartDownload != null ? '已注入' : '未注入'}',
    );
    _startPeriodicCheck(runtime);
    await _restorePendingForce();
    unawaited(start());
  }

  Future<void> start() => check();

  /// 周期检查：首次按 deviceId 稳定抖动，之后固定 [AppUpdateRuntime.checkInterval]。
  void _startPeriodicCheck(AppUpdateRuntime runtime) {
    _checkTimer?.cancel();
    if (runtime.checkInterval <= Duration.zero) return;
    // 启动时已查一次，首次周期检查放在 12h + 稳定抖动之后。
    final Duration firstDelay =
        runtime.checkInterval + Duration(seconds: _stableJitterSeconds(runtime));
    _scheduleCheckIn(firstDelay);
    _updateLog('周期检查已排定：首次 ${firstDelay.inMinutes} 分钟后触发');
  }

  void _scheduleCheckIn(Duration delay) {
    _checkTimer?.cancel();
    if (delay <= Duration.zero) {
      unawaited(_runScheduledCheck());
      return;
    }
    _checkTimer = Timer(delay, () => unawaited(_runScheduledCheck()));
  }

  Future<void> _runScheduledCheck() async {
    final AppUpdateRuntime? runtime = _runtime;
    if (runtime == null || _disposed) return;
    if (_state.phase != AppUpdatePhase.downloading) {
      await check();
    }
    if (_disposed) return;
    if (runtime.checkInterval <= Duration.zero) return;
    _scheduleCheckIn(runtime.checkInterval);
  }

  /// 同一设备每次启动得到相同偏移（FNV-1a），避免重启后同时打服务器。
  int _stableJitterSeconds(AppUpdateRuntime runtime) {
    final int max = runtime.checkJitter.inSeconds;
    if (max <= 0) return 0;
    final String seed = runtime.deviceId.isNotEmpty ? runtime.deviceId : runtime.appId;
    int hash = 0x811c9dc5;
    for (final int unit in seed.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash % (max + 1);
  }

  /// 启动时恢复已下载的粘性强更（只认 build 仍落后于 pending 的情况）。
  Future<void> _restorePendingForce() async {
    final AppUpdateRuntime? runtime = _runtime;
    if (runtime == null) return;
    try {
      final AppUpdateCache cache = _cache ??= await AppUpdateCache.open();
      final Map<String, dynamic>? pending = cache.readPendingForce(appId: runtime.appId);
      if (pending == null) {
        _updateLog('启动恢复：无粘性强更记录');
        return;
      }
      final int targetBuild = _asInt(pending['build']);
      final String path = pending['path']?.toString() ?? '';
      if (runtime.build >= targetBuild || path.isEmpty || !File(path).existsSync()) {
        await cache.clearPendingForce();
        _updateLog('启动恢复：粘性强更记录失效（已装上或文件缺失），已清除 target=$targetBuild');
        return;
      }
      final AppUpdateCheckResult result = AppUpdateCheckResult(
        appId: runtime.appId,
        platform: runtime.platform,
        currentVersion: runtime.version,
        currentBuild: runtime.build,
        hasUpdate: true,
        forceUpdate: true,
        latest: AppUpdateRelease(
          releaseId: pending['releaseId']?.toString() ?? '',
          version: pending['version']?.toString() ?? '',
          build: targetBuild,
          distribution: 'file',
          fileAvailable: true,
          forceUpdate: true,
          notes: pending['notes']?.toString() ?? '',
        ),
      );
      _emit(AppUpdateState(
        phase: AppUpdatePhase.ready,
        result: result,
        cachedPath: path,
        forcePending: true,
      ));
      _updateLog('启动恢复：粘性强更拦截生效 v${pending['version']}+$targetBuild path=$path');
    } catch (error) {
      // 本地状态损坏 / 插件暂不可用：忽略，继续正常查询。
      _updateLog('启动恢复：粘性强更恢复失败（忽略）$error');
    }
  }

  /// 查询更新；并发调用复用同一个 Future。
  Future<void> check({bool manual = false}) {
    final Future<void>? inflight = _checkingFuture;
    if (inflight != null) return inflight;
    final Future<void> task = _runCheck(manual: manual);
    _checkingFuture = task;
    return task.whenComplete(() {
      if (identical(_checkingFuture, task)) _checkingFuture = null;
    });
  }

  Future<void> _runCheck({required bool manual}) async {
    final AppUpdateRuntime? runtime = _runtime;
    if (runtime == null) return;
    final AppUpdateApi? api = _api;
    if (api == null) return;

    _emit(_state.copyWith(phase: AppUpdatePhase.checking, error: null));
    _updateLog('开始查询 manual=$manual appId=${runtime.appId} v${runtime.version}+${runtime.build} deviceId=${runtime.deviceId}');
    try {
      final AppUpdateCheckResult result = await api.check(
        appId: runtime.appId,
        platform: runtime.platform,
        version: runtime.version,
        build: runtime.build,
        deviceId: runtime.deviceId,
      );
      _lastCheckAt = _now();
      if (!result.hasUpdate) {
        _updateLog('查询成功：无更新（当前 v${runtime.version}+${runtime.build}）');
        _deferredDownload = null;
        // 成功查询且无更新才清除粘性强更与缓存路径。
        _emit(AppUpdateState(phase: AppUpdatePhase.idle, result: result));
        unawaited(_cache?.clearPendingForce());
        return;
      }
      // 保留 forcePending / cachedPath：checking 期间也不能放开强更拦截。
      _emit(_state.copyWith(phase: AppUpdatePhase.idle, result: result, error: null));
      _updateLog(
        '查询成功：有更新 force=${result.forceRequired} '
        'latest=v${result.latest?.version}+${result.latest?.build} '
        'size=${result.download?.size ?? 0}B '
        'release=${result.latest?.releaseId}',
      );
      _scheduleDownload(result);
    } on AppUpdateException catch (error) {
      // fail-open：查询失败只记录，保留上一次结果，不阻断使用。
      _updateLog('查询失败 fail-open: code=${error.code} msg=${error.message}');
      _emit(_state.copyWith(phase: AppUpdatePhase.failed, error: error.message));
      _scheduleRetry();
    } catch (error) {
      _updateLog('查询异常 fail-open: $error');
      _emit(_state.copyWith(phase: AppUpdatePhase.failed, error: '$error'));
      _scheduleRetry();
    }
  }

  /// 手动触发下载 / 重试（用户点「立即安装」或「重试」）。
  Future<void> ensureDownloadedNow() async {
    _deferredDownload = null;
    final AppUpdateCheckResult? result = _state.result;
    if (result == null) {
      await check(manual: true);
      final AppUpdateCheckResult? fresh = _state.result;
      if (fresh != null) await _ensureDownloaded(fresh);
      return;
    }
    await _ensureDownloaded(result);
  }

  /// 自动下载入口：忙碌场景先挂起，等宿主调用 [onSceneChanged] 再开始。
  void _scheduleDownload(AppUpdateCheckResult result) {
    if (!result.canSilentlyDownload) {
      _updateLog('静默下载不可用（iOS 或无安装包链接），仅展示提示');
      return;
    }
    if (_inflight != null) {
      // 已有下载在跑：先记下，完成后再由 onSceneChanged 续跑，避免丢失。
      _deferredDownload = result;
      _updateLog('已有下载在跑，本次更新记录为待续跑');
      return;
    }
    if (_downloadAllowed()) {
      _deferredDownload = null;
      _updateLog('门控放行，开始静默下载 release=${result.latest?.releaseId}');
      unawaited(_ensureDownloaded(result));
    } else {
      _deferredDownload = result;
      _updateLog('门控拦截（canStartDownload=false），下载挂起，等场景变化后恢复');
    }
  }

  bool _downloadAllowed() => _runtime?.canStartDownload?.call() ?? true;

  /// 宿主场景变化（直播结束 / 退出屏保 / 离开直播页）时调用。
  void onSceneChanged() {
    final AppUpdateCheckResult? deferred = _deferredDownload;
    if (deferred == null) return;
    if (_inflight != null) return;
    if (!_downloadAllowed()) {
      _updateLog('场景变化：门控仍拦截，继续挂起');
      return;
    }
    _deferredDownload = null;
    _updateLog('场景变化：门控放行，恢复挂起的下载');
    unawaited(_ensureDownloaded(deferred));
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
    // 下载期间被挂起的更新在这里续跑。
    onSceneChanged();
  }

  Future<void> _download(AppUpdateCheckResult result, AppUpdateRuntime runtime, AppUpdateCache cache) async {
    final String releaseId = result.latest?.releaseId ?? '';
    final AppUpdateDownload download = result.download!;
    final File cached = cache.finalFile(appId: runtime.appId, releaseId: releaseId, sha256: download.sha256);

    // 缓存复用：sha256 一致直接进入「可安装」，不重复下载。
    if (await cache.isReady(appId: runtime.appId, releaseId: releaseId, sha256: download.sha256)) {
      _updateLog('缓存命中，跳过下载直接 ready: $cached');
      _emit(_state.copyWith(
        phase: AppUpdatePhase.ready,
        cachedPath: cached.path,
        received: download.size,
        total: download.size,
        error: null,
        forcePending: result.forceRequired || _state.forcePending,
      ));
      await _rememberPendingForce(result, download, cached.path, runtime);
      return;
    }

    _emit(_state.copyWith(
      phase: AppUpdatePhase.downloading,
      received: 0,
      total: download.size,
      error: null,
      attempt: _attempt,
    ));
    _updateLog('开始下载 release=$releaseId size=${download.size}B attempt=$_attempt');

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
        _updateLog('下载完成并 sha256 校验通过，ready: $file');
        _emit(_state.copyWith(
          phase: AppUpdatePhase.ready,
          cachedPath: file.path,
          received: download.size,
          total: download.size,
          error: null,
          attempt: 0,
          forcePending: result.forceRequired || _state.forcePending,
        ));
        await _rememberPendingForce(result, download, file.path, runtime);
        return;
      } on AppUpdateShaMismatchException {
        // 校验不一致：文件已删除，重下一轮（不增加退避计数）。
        _updateLog('sha256 校验不一致，第 ${round + 2} 轮重下');
        continue;
      } on AppUpdateDownloadException catch (error) {
        if (!error.retryable) {
          _updateLog('下载失败（不可重试）: ${error.message}');
          _emit(_state.copyWith(phase: AppUpdatePhase.failed, error: error.message));
          return;
        }
        // 网络波动 / 300008 / 限流：保留断点，退避后静默重试。
        _updateLog('下载错误（可重试）round=${round + 1}: ${error.message}，退避后重试');
        await Future<void>.delayed(_backoffDelay(round));
      } catch (error) {
        _updateLog('下载异常 round=${round + 1}: $error，退避后重试');
        await Future<void>.delayed(_backoffDelay(round));
      }
    }

    _updateLog('连续 3 轮下载未完成，转入退避重试');
    _emit(_state.copyWith(phase: AppUpdatePhase.failed, error: '下载未完成，将在下次启动/回前台时重试'));
    _scheduleRetry();
  }

  Duration _backoffDelay(int round) {
    const List<int> seconds = <int>[5, 20, 60];
    return Duration(seconds: seconds[round.clamp(0, seconds.length - 1)]);
  }

  /// 回前台 / 网络恢复：距上次成功检查超过阈值就补查（覆盖 idle 态）。
  void onForeground() {
    final AppUpdatePhase phase = _state.phase;
    if (phase == AppUpdatePhase.downloading) {
      _updateLog('回前台：下载进行中，跳过补查');
      return;
    }
    if (phase == AppUpdatePhase.ready || phase == AppUpdatePhase.installing) {
      // 可能已安装完成但未重启：重新校验版本，装好后就不应再提示。
      _updateLog('回前台：phase=$phase，重新校验版本');
      unawaited(check());
      return;
    }
    final AppUpdateRuntime? runtime = _runtime;
    if (runtime != null) {
      final DateTime? last = _lastCheckAt;
      if (last == null || _now().difference(last) >= runtime.foregroundCheckAfter) {
        final String elapsed = last == null ? '从未查询' : '距上次 ${_now().difference(last).inMinutes} 分钟';
        _updateLog('回前台：$elapsed，达到补查阈值 ${runtime.foregroundCheckAfter}，补查');
        unawaited(check());
        return;
      }
      _updateLog('回前台：距上次 ${_now().difference(last).inMinutes} 分钟，未到补查阈值 ${runtime.foregroundCheckAfter}，跳过');
    }
    if (phase == AppUpdatePhase.failed) {
      _updateLog('回前台：查询失败态，立即重试');
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
    _updateLog('排定退避重试：${delay}s 后（第 $_attempt 次尝试）');
    _retryTimer = Timer(Duration(seconds: delay), () {
      if (_disposed) return;
      final AppUpdateState state = _state;
      if (state.phase == AppUpdatePhase.downloading) return;
      if (state.result == null || state.result!.hasUpdate) {
        // 已有结果：直接重试下载；无结果（查询失败）则重新查询。
        if (state.result != null && state.result!.canSilentlyDownload) {
          _scheduleDownload(state.result!);
        } else {
          unawaited(check());
        }
      }
    });
  }

  /// 记住粘性强更：releaseId / 文件路径 / 目标 build，供下次启动直接拦截。
  Future<void> _rememberPendingForce(
    AppUpdateCheckResult result,
    AppUpdateDownload download,
    String path,
    AppUpdateRuntime runtime,
  ) async {
    if (!result.forceRequired && !_state.forcePending) return;
    final AppUpdateCache? cache = _cache;
    if (cache == null) return;
    await cache.savePendingForce(
      appId: runtime.appId,
      releaseId: result.latest?.releaseId ?? '',
      path: path,
      sha256: download.sha256,
      version: result.latest?.version ?? result.currentVersion,
      build: result.latest?.build ?? result.currentBuild,
      notes: result.latest?.notes ?? '',
    );
    _updateLog('粘性强更已持久化：v${result.latest?.version ?? result.currentVersion}+${result.latest?.build ?? result.currentBuild}');
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  /// 拉起系统安装器（仅 Android/桌面自托管包）。
  Future<bool> install() async {
    final String? path = _state.cachedPath;
    if (path == null) return false;
    try {
      _updateLog('拉起系统安装器: $path');
      final bool started = await _installer.installApk(path);
      _updateLog(started ? '安装器已启动（用户需在系统弹窗确认）' : '安装器未能启动');
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
        _state.cachedPath == next.cachedPath &&
        _state.forcePending == next.forcePending) {
      return;
    }
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _retryTimer?.cancel();
    _checkTimer?.cancel();
    super.dispose();
  }
}
