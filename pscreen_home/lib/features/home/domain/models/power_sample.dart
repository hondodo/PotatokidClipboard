/// 单个功率采样点：采样时刻 + 功率（W）。
///
/// 由 `PowerSampler` 按固定间隔从 Home Assistant 的最新状态采集，
/// 仅驻内存、不落盘（退出应用即丢弃）。
class PowerSample {
  const PowerSample({required this.at, required this.watts});

  /// 采样时刻（本地时间）。
  final DateTime at;

  /// 功率值（W），无数据时记 0。
  final double watts;
}
