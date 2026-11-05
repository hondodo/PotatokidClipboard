/// 「持续缓冲卡死」两级看门狗（纯逻辑 + 宿主每秒 tick，不持有播放器）。
///
/// 宿主的 1 秒计时器每秒调用 [notifyState]（读一次播放器状态）：
/// - **一级**：playing 且 buffering 累计 ≥ [reloadThreshold]（默认 10s）且本源
///   重载额度未用尽 → [onReload]（宿主重开**同一地址**，吸收 relay 会话重建
///   等瞬时空窗，不换源），额度 [reloadMax]（默认 2）次；
/// - **二级**：额度用尽仍卡 ≥ [stallThreshold]（默认 60s）→ [onStuck]（宿主交
///   给重试状态机换源回退）。
///
/// 与「打开后无画面」[PlaybackWatchdog] 互补：那个管**建立播放之前**（到期即
/// 换源、且出画面即取消）；本看门狗管**出过画面之后**再次陷入持续缓冲的时段。
///
/// 重载额度补满时机：[onFreshOpen]（切台/换源/重试等非重载 open）与缓冲恢复
/// 期间出过真实画面（[notifyState] 的 hasFrame）。因此正常播放 / 短暂缓冲
/// 永远不会误杀。
class BufferStallWatchdog {
  BufferStallWatchdog({
    required this.onReload,
    required this.onStuck,
    this.reloadThreshold = const Duration(seconds: 10),
    this.stallThreshold = const Duration(seconds: 60),
    this.reloadMax = 2,
  });

  /// 一级回调：原地重载当前源。参数 = 本次是第几次重载（1 起）。
  final void Function(int attempt) onReload;

  /// 二级回调：持续缓冲卡死，应交给重试状态机换源。
  /// 参数 = 触发时的累计时长（默认阈值下为 60s）。
  final void Function(Duration accumulated) onStuck;

  /// 一级阈值：连续缓冲多久触发原地重载。
  final Duration reloadThreshold;

  /// 二级阈值：额度用尽后连续缓冲多久判定卡死回退。
  final Duration stallThreshold;

  /// 单个源的原地重载额度。
  final int reloadMax;

  Duration _accum = Duration.zero;
  int _used = 0;

  /// 非重载的 open（切台/换源/重试）：额度与累计双清。
  /// 注意：原地重载的 open **不要**调用它，否则额度永不消耗、无限重载。
  void onFreshOpen() {
    _used = 0;
    _accum = Duration.zero;
  }

  /// 每秒喂一次播放器状态。
  void notifyState({
    required bool playing,
    required bool buffering,
    required bool hasFrame,
  }) {
    if (playing && buffering) {
      _accum += const Duration(seconds: 1);
      // 一级：额度内先原地重载（不换源），吸收瞬时空窗。
      if (_accum >= reloadThreshold && _used < reloadMax) {
        _used++;
        final int attempt = _used;
        _accum = Duration.zero;
        onReload(attempt);
        return;
      }
      // 二级：额度用尽仍持续缓冲 → 判定卡死，交给宿主回退换源。
      if (_accum >= stallThreshold) {
        final Duration stuck = _accum;
        _accum = Duration.zero;
        onStuck(stuck);
      }
    } else {
      // 缓冲恢复且出过真实画面 = 已恢复健康，重载额度补满。
      if (hasFrame) _used = 0;
      _accum = Duration.zero;
    }
  }
}
