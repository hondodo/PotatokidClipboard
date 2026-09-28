/// 首页「当前频道提示」的控制器（纯字段，不派发通知）。
///
/// 当左下角的频道名提示可见时，壳层「左/右」键不再切 tab，而是切换当前频道的源。
/// 这里只存状态与回调；真正的切源由 [LivePlayerWidget] 注册到 [onSwitchSource]。
class HomeNowPlayingController {
  HomeNowPlayingController._();

  /// 全局单例。
  static final HomeNowPlayingController instance = HomeNowPlayingController._();

  /// 左下角频道名提示是否可见（由播放器在显示/隐藏 toast 时更新）。
  bool toastVisible = false;

  /// 切源回调（播放器注册），delta 为 +1/-1。
  void Function(int delta)? onSwitchSource;

  /// 左/右切换当前频道源。
  void switchSource(int delta) => onSwitchSource?.call(delta);
}