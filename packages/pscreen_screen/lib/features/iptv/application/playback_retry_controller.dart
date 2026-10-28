import 'dart:async';

/// 打开「第 sourceIndex 个源」（宿主的完整打开链路：属性设置 / 日志 /
/// 重置判定器与看门狗 / 上报 play_start）。
typedef PlaybackOpenFn = Future<void> Function(int sourceIndex);

/// 「换路由重试同一个源」的宿主实现（可选注入）。
///
/// 返回 true = 已用备用路由重新打开了同一个源，状态机到此为止；
/// 返回 false = 没有可用路由（或宿主不需要），继续走换源回退。
///
/// 路由是抽象概念，宿主自行定义：电视端 = 代理池 + 直连（失败先试下一个代理，
/// 试满若干次才换源），触屏端 = 仅直连（不注入本回调）。
typedef PlaybackRouteFn = Future<bool> Function(int failedSourceIndex, String reason);

/// 播放失败重试状态机（纯 Dart，无 Flutter 依赖，可单测）。
///
/// 职责（逻辑抽自电视端 `LivePlayerWidget`，所有客户端一致）：
/// - **冷却**：open 后 [cooldown]（默认 700ms）内到来的事件多为旧源残留，忽略；
///   真实的 open 失败用 [bypassCooldown] 跳过冷却，让连续打不开的源一路回退；
/// - **路由优先**：失败先给宿主一次 [retryWithRoute] 换路由重试同一源的机会，
///   路由也不行才换源；
/// - **一轮判定**：本轮试过的源集齐该频道**全部源** = 一轮失败，退避
///   1s → 2s → 4s → 8s 后再进下一轮 —— 否则「全源都打不开」时会以 mpv 报错的
///   速度（实测 20~140ms）不停 open/失败，每个 open 都要重建解码器，盒子会持续抖动；
/// - **多源循环回退**：0-1-2-0-…（单源频道为 0-0-0-…，且每次失败都算一轮、都退避）；
/// - **语义重置**：换台 [resetForChannel] / 手动换源 [setSource] / 播放成功
///   [resetRound] 各自清掉对应状态；换台与换源还会推进「世代号」，让还在
///   退避等待中的过期回退自动作废（不会顶掉用户刚选好的源）。
///
/// 宿主注入项：
/// - [sourceCount] 当前频道的源总数；
/// - [open] 打开指定源（见 [PlaybackOpenFn]）；
/// - [onEnterRetry] 进入一次重试的**失败现场**上报/日志回调 —— 在换源、换路由
///   **之前**同步调用，读到的源号 / 代理 / 轮次正是本次失败现场；
/// - [isActive] 存活复核（通常 `() => mounted`），在入口与各次 await 之后调用。
class PlaybackRetryController {
  PlaybackRetryController({
    required int Function() sourceCount,
    required PlaybackOpenFn open,
    required void Function(String reason) onEnterRetry,
    PlaybackRouteFn? retryWithRoute,
    void Function(int round, Duration wait)? onBackoff,
    void Function(int sourceIndex, String reason)? onSourceChanged,
    bool Function()? isActive,
    this.cooldown = const Duration(milliseconds: 700),
    this.roundBaseDelay = const Duration(seconds: 1),
    this.maxRoundRetryShift = 3,
  })  : _sourceCount = sourceCount,
        _open = open,
        _onEnterRetry = onEnterRetry,
        _retryWithRoute = retryWithRoute,
        _onBackoff = onBackoff,
        _onSourceChanged = onSourceChanged,
        _isActive = isActive;

  /// open 后多久内的失败事件视为旧源残留而忽略（真实 open 失败可 bypass）。
  final Duration cooldown;

  /// 一整轮失败后的基础等待（后续按 2 的幂翻倍）。
  final Duration roundBaseDelay;

  /// 退避的翻倍上限：1s → 2s → 4s → 8s（[roundBaseDelay] << 3）。设为 0 即固定不翻倍。
  final int maxRoundRetryShift;

  final int Function() _sourceCount;
  final PlaybackOpenFn _open;
  final void Function(String reason) _onEnterRetry;
  final PlaybackRouteFn? _retryWithRoute;
  final void Function(int round, Duration wait)? _onBackoff;
  final void Function(int sourceIndex, String reason)? _onSourceChanged;
  final bool Function()? _isActive;

  /// 当前正在播放的源序号（0 起）。换源由状态机完成；
  /// 宿主可在换台时直接赋值指定起播源（如「优先上次可用源」）。
  int sourceIndex = 0;

  /// 是否正在处理一次失败（并发失败的抑制开关，宿主换台播放期间也可手动置位）。
  bool get isHandlingFailure => _busy;

  /// 连续失败到「一整轮都没打开」的轮数：对外上报语义是
  /// 「正在尝试第几轮」（= failedRounds + 1）。
  int get failedRounds => _failedRounds;

  /// 本轮已试过的源序号：集齐全部源即「一轮失败」。
  final Set<int> _triedThisRound = <int>{};

  int _failedRounds = 0;
  bool _busy = false;
  DateTime _lastOpenAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 世代号：换台 / 手动换源时自增，await 之后对不上即为过期请求。
  int _generation = 0;

  /// 手动置位宿主的失败处理开关（换台播放期间抑制旧流的 error/completed 干扰）。
  void setBusy(bool value) => _busy = value;

  /// 每次 open 前由宿主调用：刷新 [cooldown] 的时间基准。
  void markOpen() => _lastOpenAt = DateTime.now();

  /// 新的一轮试源（播放成功后调用）：退避重新从 [roundBaseDelay] 起算。
  /// 不推进世代号 —— 退避等待中的回退不因「中途播起来了」而作废（与电视端一致）。
  void resetRound() {
    _triedThisRound.clear();
    _failedRounds = 0;
  }

  /// 换台 / 频道列表刷新：全新一轮试源，源序号回到 [source]（起播源）。
  void resetForChannel(int source) {
    _generation++;
    sourceIndex = source;
    resetRound();
  }

  /// 手动换源（用户主动重试）：换源 + 本轮退避清零。
  void setSource(int source) {
    _generation++;
    sourceIndex = source;
    resetRound();
  }

  /// 本轮退避时长：[roundBaseDelay]、2 倍、4 倍、8 倍（到 [maxRoundRetryShift] 封顶）。
  ///
  /// 坏台会一直重试：固定 1 秒虽远好过空转，但长期看仍是每分钟 60 次 open；
  /// 递增后逐步降到每分钟 7~8 次，持续不可用时不至于拖累盒子。
  Duration get currentRoundDelay {
    final int shift = (_failedRounds - 1).clamp(0, maxRoundRetryShift);
    return Duration(milliseconds: roundBaseDelay.inMilliseconds << shift);
  }

  /// 播放失败 / 结束 / 看门狗到期：先给宿主换路由的机会，再循环回退到下一个源。
  ///
  /// 多源时按 0-1-2-0-… 循环；单源时反复重试同一源 0-0-0-…。
  /// [bypassCooldown] 供真实的 open 失败（如 `Failed to open`）跳过冷却，
  /// 使连续打不开的源能一路回退下去，而不是被冷却卡停在当前源。
  Future<void> handleIssue({String reason = '', bool bypassCooldown = false}) async {
    if (_busy) return;
    if (_isActive != null && !_isActive()) return;
    final int count = _sourceCount();
    if (count <= 0) return;
    if (!bypassCooldown && DateTime.now().difference(_lastOpenAt) < cooldown) return;

    _busy = true;
    final int generation = _generation;
    // 失败现场上报/日志：必须在换源、换路由之前。
    _onEnterRetry(reason);
    final int failedIndex = sourceIndex.clamp(0, count - 1);

    // 第一段：宿主尝试换路由重试同一个源（如代理池）。未注入则直接走换源。
    if (_retryWithRoute != null) {
      final bool used = await _retryWithRoute(failedIndex, reason);
      // 等待期间可能已换台/手动换源/退出：过期就放弃这次处理。
      if (used || generation != _generation || !(_isActive?.call() ?? true)) {
        _busy = false;
        return;
      }
    }

    // 该频道所有源都各试过一次 = 一轮结束：回到第一个源之前先退避一会儿。
    _triedThisRound.add(failedIndex);
    if (_triedThisRound.length >= count) {
      _triedThisRound.clear();
      _failedRounds++;
      final Duration wait = currentRoundDelay;
      _onBackoff?.call(_failedRounds, wait);
      final int snapSource = sourceIndex;
      await Future<void>.delayed(wait);
      // 等待期间可能已换台 / 手动换源 / 退出：过期就放弃这次回退，
      // 否则会把用户刚选好的源又顶掉。
      if (generation != _generation || sourceIndex != snapSource || !(_isActive?.call() ?? true)) {
        _busy = false;
        return;
      }
    }

    sourceIndex = (sourceIndex + 1) % count;
    _onSourceChanged?.call(sourceIndex, reason);
    await _open(sourceIndex);
    _busy = false;
  }
}
